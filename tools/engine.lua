-- ================================================================ passive-picker engine
-- Shared by every MostlyCloudy tuning mod (credit to SHODAN); the MOD table above says what to change.
--
-- This engine extends one armour PERK's modifier list. It is not a stat patcher:
-- instead of overwriting a field, it grows a variable-length array inside a live
-- game record and repoints the record's descriptor at the enlarged copy.
--
-- The game lays its settings tables down in memory as LDLD blocks. The perk table
-- (HelldiverCustomizationPassiveBonusSettings, type 0x63CE0FEB) stores, per perk:
--
--   +0  u32     PassiveBonus        <- the perk id (19 = Adreno-Defibrillator)
--   +4  u32     Name
--   +8  u64     Icon
--   +16 DLArray PassiveModifiers    <- (i64 pointer, u64 count)  <-- we grow this
--   +32 DLArray StatModifiers       <- also grown when the perk is a stat user
--   +48 u32     SomeHash
--
-- In the FILE the DLArray holds a relative offset (always 56, i.e. the modifier
-- rows sit inline right after the 56-byte record). In MEMORY it holds an absolute
-- pointer. We detect which one we are looking at by checking whether the pointer
-- equals record+56; that is the only form we rewrite. Anything else means another
-- mod has already replaced the array, so we leave it alone rather than fight.
--
-- Every write is read back and the descriptor is checked, or it is rolled back.
-- Changes live in memory only.
--
-- ---- v4 changes (community edit, built on mostlycloudy's v3) --------------------
--   * MULTIPLE PROFILES: MOD.profiles holds one stack per trigger perk, so e.g.
--     Med-Kit armour and Siege-Ready armour can carry different stacks at once.
--     Each profile owns its own destination buffers.
--   * OVERRIDES: a profile can REPLACE the value of the trigger perk's own rows
--     (matched on modifier id + type, or stat id), so the base perk is tunable
--     too -- v3 could only append, which stacked a second copy on top.
--   * The old single trigger_perk / rows / stat_rows layout is still accepted.
--
-- ---- v3 changes -----------------------------------------------------------------
--   * ROWS ARE SKIPPED WHEN ALREADY PRESENT, compared on identity (modifier id +
--     type + value). v3 lists EVERY passive including the base perk, so without
--     this the base perk would be applied twice. Identity, not the whole row,
--     because we write description=0 while the game's own rows carry a hash.
--   * AN ABSENT ARRAY IS NOW CREATED, not refused. A perk that ships zero stat
--     rows stores offset -1; the old code called that "foreign" and returned
--     'partial: stat array ...' AFTER the passive array had already been repointed.
--     add_site() counts that as refused, so the mod mutated the record and still
--     reported "perk not found". That hit 25 of the 31 passives.
--   * Conflicting rows are KEPT, not deduplicated: two passives sharing a modifier
--     id at different values both apply. Only exact repeats are collapsed.
--
-- Safety rules, learned from the previous implementation of this idea:
--   * the pointer and the count are written as ONE 16-byte store, so the game can
--     never observe a fresh pointer with a stale count;
--   * a record whose array is already relocated is treated as another mod's work;
--   * retire = true patches once and unregisters, so nothing races an armour swap.

if rawget(_G, MOD.global) then return end

local HEADER_BYTES = 24
local MAX_PAYLOAD = 64 * 1024 * 1024
local FRAME_BUDGET = 0.006
local CHUNK = 262144
local START_FRAME = 300
local PROBE_MIN_ALLOC = 64 * 1024
local PROBE_BYTES = 128 * 1024
local SELF_MARGIN = 4096
local MAX_ROUNDS = 12
local ROUND_DELAY_SECONDS = 10
local ENFORCE_SECONDS = 5
local MAX_LOG_LINES = 400

-- record layout offsets, from FileDiver datalibrary/passive_bonuses.go
local REC_ID = 0
local REC_PM = 16            -- DLArray for PassiveModifiers
local REC_SM = 32            -- DLArray for StatModifiers
local REC_HEAD = 56          -- rows sit inline at record+56 in the shipped form
local ROW_BYTES = 16         -- one passive modifier
local STAT_BYTES = 12        -- one stat modifier
-- Row IDENTITY, used to decide "this row is already present". The description
-- field is deliberately excluded from a passive row's identity: we write 0 there
-- while the game's own rows carry a real hash, so a whole-row compare would never
-- match the base perk's rows -- and v3's tables list the base perk, so that would
-- apply it twice.
local ROW_IDENT = ROW_BYTES - 4    -- modifier id + type + value
local STAT_IDENT = STAT_BYTES      -- stat + unk1 + unk2 (no description field)

local MEM_COMMIT, MEM_PRIVATE = 0x1000, 0x20000
local PAGE_READONLY, PAGE_READWRITE = 0x02, 0x04

local state = {
    title = MOD.title, version = MOD.version, phase = 'starting', status = 'starting',
    frame = 0, rounds = 0, applied = 0, reapplied = 0, refused = 0,
}
rawset(_G, MOD.global, state)

-- ---------------------------------------------------------------- byte helpers
local function u32_bytes(value)
    value = value % 4294967296
    return string.char(value % 256,
                       math.floor(value / 256) % 256,
                       math.floor(value / 65536) % 256,
                       math.floor(value / 16777216) % 256)
end

local function u32(blob, offset)
    local a, b, c, d = blob:byte(offset + 1, offset + 4)
    if not d then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function u64(blob, offset)
    local lo = u32(blob, offset)
    local hi = u32(blob, offset + 4)
    if not lo or not hi then return nil end
    return lo + hi * 4294967296
end

local function u64_bytes(value)
    local lo = value % 4294967296
    local hi = math.floor(value / 4294967296) % 4294967296
    return u32_bytes(lo) .. u32_bytes(hi)
end

local NEEDLE = 'LDLD' .. u32_bytes(1)

-- ---------------------------------------------------------------- windows api
local ffi_ok, ffi = pcall(require, 'ffi')
local api = nil
local REGION_TYPE = MOD.global .. 'Region'

local function build_api()
    for _, declaration in ipairs({
        'void *GetCurrentProcess(void);',
        'int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);',
        'int WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);',
        'size_t VirtualQuery(const void *address, void *region, size_t size);',
        'int VirtualProtect(void *address, size_t size, uint32_t new_protection, uint32_t *old_protection);',
        'void *VirtualAllocEx(void *process, void *address, size_t size, uint32_t type, uint32_t protect);',
        'int CreateDirectoryA(const char *path, void *security);',
        'uint32_t GetLastError(void);',
    }) do
        pcall(ffi.cdef, declaration)
    end
    pcall(ffi.cdef, [[typedef struct {
        void *base; void *allocation_base; uint32_t allocation_protection;
        uint16_t partition; uint16_t reserved; size_t size;
        uint32_t state; uint32_t protection; uint32_t type;
    } ]] .. REGION_TYPE .. ';')

    local kernel = ffi.load('kernel32')
    local query = ffi.cast('size_t (*)(const void *, void *, size_t)', kernel.VirtualQuery)
    local virtual_protect = ffi.cast('int (*)(void *, size_t, uint32_t, uint32_t *)', kernel.VirtualProtect)
    local process = kernel.GetCurrentProcess()
    local region = ffi.new(REGION_TYPE .. '[1]')
    local region_size = ffi.sizeof(region[0])
    local counter = ffi.new('size_t[1]')

    local self = {}

    function self.read(address, size)
        if size <= 0 then return nil end
        local buffer = ffi.new('uint8_t[?]', size)
        if kernel.ReadProcessMemory(process, ffi.cast('const void *', address),
                                    buffer, size, counter) == 0 then return nil end
        if tonumber(counter[0]) ~= size then return nil end
        return ffi.string(buffer, size)
    end

    function self.query(address)
        if query(ffi.cast('const void *', address), region, region_size) ~= region_size then
            return nil
        end
        local base = tonumber(ffi.cast('uintptr_t', region[0].base))
        local size = tonumber(region[0].size)
        if not base or not size or size <= 0 then return nil end
        return { base = base, size = size, state = region[0].state,
                 protection = region[0].protection, kind = region[0].type }
    end

    function self.write(address, bytes)
        if #bytes <= 0 then return false end
        local info = self.query(address)
        if not info or info.state ~= MEM_COMMIT or info.kind ~= MEM_PRIVATE
            or address < info.base or address + #bytes > info.base + info.size
            or (info.protection ~= PAGE_READONLY and info.protection ~= PAGE_READWRITE) then
            return false
        end
        local old_protection = ffi.new('uint32_t[1]')
        local changed = info.protection == PAGE_READONLY
        if changed and virtual_protect(ffi.cast('void *', address), #bytes,
                                       PAGE_READWRITE, old_protection) == 0 then
            return false
        end
        local wrote = kernel.WriteProcessMemory(process, ffi.cast('void *', address),
                                                bytes, #bytes, counter) ~= 0
                      and tonumber(counter[0]) == #bytes
        local restored = not changed or virtual_protect(
            ffi.cast('void *', address), #bytes, old_protection[0], old_protection) ~= 0
        return wrote and restored
    end

    -- Private committed block for the enlarged modifier array.
    function self.alloc(size)
        if type(size) ~= 'number' or size <= 0 or size > 1048576 then return nil end
        local p = kernel.VirtualAllocEx(process, nil, size, 0x3000, PAGE_READWRITE)
        if p == nil then return nil end
        local v = tonumber(ffi.cast('uintptr_t', p))
        if not v or v < 65536 then return nil end
        return v
    end

    function self.regions()
        local out = {}
        local address = 0
        while address < 0x7FFFFFFF0000 do
            if query(ffi.cast('const void *', address), region, region_size) ~= region_size then break end
            local base = tonumber(ffi.cast('uintptr_t', region[0].base))
            local size = tonumber(region[0].size)
            if not base or not size or size <= 0 then break end
            if region[0].state == MEM_COMMIT and region[0].type == MEM_PRIVATE
                and (region[0].protection == PAGE_READONLY or region[0].protection == PAGE_READWRITE) then
                out[#out + 1] = { base = base, size = size,
                                  allocation_base = tonumber(ffi.cast('uintptr_t', region[0].allocation_base)) }
            end
            address = base + size
        end
        table.sort(out, function(a, b) return a.size > b.size end)
        return out
    end

    function self.address_of(text)
        local ok, value = pcall(function()
            return tonumber(ffi.cast('uintptr_t', ffi.cast('const char *', text)))
        end)
        if ok then return value end
        return nil
    end

    function self.mkdir(path)
        return kernel.CreateDirectoryA(path, nil) ~= 0 or kernel.GetLastError() == 183
    end

    return self
end

-- ---------------------------------------------------------------- log
local log_path, status_path, log_lines, log_counts = nil, nil, {}, {}
local last_status_seen = nil
local write_status

local function write_file(path, text)
    if not path then return false end
    local ok, handle = pcall(io.open, path, 'wb')
    if not ok or not handle then return false end
    pcall(function() handle:write(text) end)
    pcall(function() handle:close() end)
    return true
end

local function ensure_path(file)
    local ok, resolved = pcall(function()
        local base = os.getenv('LOCALAPPDATA')
        if not base or base == '' then return nil end
        for _, part in ipairs({ 'CowboyBingus', 'Helldivers2', 'Logs' }) do
            base = base .. '/' .. part
            if not api.mkdir(base) then return nil end
        end
        return base .. '/' .. file
    end)
    if ok and resolved then return resolved end
    return nil
end

local function ensure_log_path()
    if log_path ~= nil then return log_path end
    log_path = ensure_path(MOD.log) or false
    return log_path
end

local function ensure_status_path()
    if status_path ~= nil then return status_path end
    status_path = ensure_path(MOD.global .. '-STATUS.txt') or false
    return status_path
end

local function flush_log()
    local path = ensure_log_path()
    if not path then return end
    local lines = {
        MOD.title .. ' v' .. MOD.version .. ' by ' .. MOD.author,
        'status: ' .. tostring(state.phase) .. ' - ' .. tostring(state.status),
        'applied ' .. state.applied .. ', re-applied ' .. state.reapplied .. ', refused ' .. state.refused,
        '',
    }
    for _, line in ipairs(log_lines) do lines[#lines + 1] = line end
    write_file(path, table.concat(lines, '\r\n') .. '\r\n')
end

local function log(message)
    local count = (log_counts[message] or 0) + 1
    log_counts[message] = count
    if count > 3 or #log_lines >= MAX_LOG_LINES then return end
    local line = '[frame ' .. tostring(state.frame) .. '] ' .. message
    if count == 3 then line = line .. ' (further repeats not logged)' end
    log_lines[#log_lines + 1] = line
    print('[' .. MOD.global .. '] ' .. line)
end

local function set_status(phase, status)
    state.phase, state.status = phase, status
    log(phase .. ': ' .. status)
    pcall(flush_log)
    if last_status_seen ~= phase and write_status then
        last_status_seen = phase
        pcall(write_status)
    end
end

local function hex(n) return string.format('0x%X', n) end

-- ---------------------------------------------------------------- the rows
-- v4: MOD.profiles is a list, one entry per trigger perk. Each profile carries
--   rows           passive rows to APPEND   { modifier_id, type, value }
--   stat_rows      stat rows to APPEND      { stat, unk1, unk2 }
--   overrides      REPLACE the value of the perk's OWN rows, matched on
--                  modifier id + type        { modifier_id, type, value }
--   stat_overrides REPLACE the perk's own stat rows, matched on stat id
--                                            { stat, unk1, unk2 }
-- Everything is validated once at load and packed into byte blobs.
local PROFILES = {}      -- perk id -> prepared profile
local PROFILE_LIST = {}  -- same profiles, in config order
local row_count = 0
local stat_count = 0

local function f32(value)
    local cell = ffi.new('float[1]')
    cell[0] = value
    return ffi.string(cell, 4)
end

local function check_row(where, id, kind, value)
    assert(type(id) == 'number' and id >= 0 and id <= 4294967295,
           where .. ' modifier id is not a u32')
    assert(type(kind) == 'number' and kind >= 0 and kind <= 3,
           where .. ' type must be 0..3 (0 Set, 1 Add, 2 Multiply, 3 Time)')
    assert(type(value) == 'number', where .. ' value is not a number')
end

local function check_stat(where, stat, unk1, unk2)
    assert(type(stat) == 'number' and stat >= 0 and stat <= 4294967295,
           where .. ' stat is not a u32')
    assert(type(unk1) == 'number' and type(unk2) == 'number',
           where .. ' values must be numbers')
end

local function prepare_profile(index, p)
    local tag = 'profiles[' .. index .. ']'
    assert(type(p.perk) == 'number', tag .. '.perk is not a number')
    assert(not PROFILES[p.perk], tag .. ': perk ' .. p.perk .. ' is listed twice')

    local blob = {}
    for i, row in ipairs(p.rows or {}) do
        check_row(tag .. '.rows[' .. i .. ']', row[1], row[2], row[3])
        blob[#blob + 1] = u32_bytes(row[1]) .. u32_bytes(row[2]) .. f32(row[3]) .. u32_bytes(0)
    end
    local sblob = {}
    for i, row in ipairs(p.stat_rows or {}) do
        check_stat(tag .. '.stat_rows[' .. i .. ']', row[1], row[2], row[3])
        sblob[#sblob + 1] = u32_bytes(row[1]) .. f32(row[2]) .. f32(row[3])
    end
    -- overrides: key = the bytes that identify a row, repl = the bytes that follow it
    local ovr = { key_len = 8, map = {}, n = 0 }
    for i, row in ipairs(p.overrides or {}) do
        check_row(tag .. '.overrides[' .. i .. ']', row[1], row[2], row[3])
        ovr.map[u32_bytes(row[1]) .. u32_bytes(row[2])] = f32(row[3])
        ovr.n = ovr.n + 1
    end
    local sovr = { key_len = 4, map = {}, n = 0 }
    for i, row in ipairs(p.stat_overrides or {}) do
        check_stat(tag .. '.stat_overrides[' .. i .. ']', row[1], row[2], row[3])
        sovr.map[u32_bytes(row[1])] = f32(row[2]) .. f32(row[3])
        sovr.n = sovr.n + 1
    end

    local prof = {
        perk = p.perk, name = p.name or ('perk ' .. p.perk),
        ROWS = table.concat(blob), STATS = table.concat(sblob),
        OVR = ovr, SOVR = sovr, sites = 0,
    }
    assert(#prof.ROWS % ROW_BYTES == 0, tag .. ': row blob is not whole 16-byte rows')
    assert(#prof.STATS % STAT_BYTES == 0, tag .. ': stat blob is not whole 12-byte rows')
    PROFILES[p.perk] = prof
    PROFILE_LIST[#PROFILE_LIST + 1] = prof
    row_count = row_count + #prof.ROWS / ROW_BYTES
    stat_count = stat_count + #prof.STATS / STAT_BYTES
end

local function prepare_rows()
    -- v3 compatibility: a single trigger_perk + rows/stat_rows still works.
    local list = MOD.profiles
    if not list then
        list = { { perk = MOD.trigger_perk, rows = MOD.rows, stat_rows = MOD.stat_rows } }
    end
    for i, p in ipairs(list) do prepare_profile(i, p) end
    return row_count, stat_count
end

-- Each profile gets its own private block per array: two perks can hold
-- different stacks, so they cannot share one destination buffer.
local function alloc_buffers()
    for _, prof in ipairs(PROFILE_LIST) do
        prof.buffer = api.alloc(#prof.ROWS + 4096)
        assert(prof.buffer, 'could not allocate the passive buffer for ' .. prof.name)
        if #prof.STATS > 0 or prof.SOVR.n > 0 then
            prof.stat_buffer = api.alloc(#prof.STATS + 4096)
            assert(prof.stat_buffer, 'could not allocate the stat buffer for ' .. prof.name)
        end
    end
end

-- ---------------------------------------------------------------- record location
-- The perk block's payload is one record, so the perk id is the first u32.
local function locate_perk(blob)
    return PROFILES[u32(blob, REC_ID)]
end

-- ---------------------------------------------------------------- sites
local sites = {}

-- Rewrite rows already present whose identity key is in ovr.map. Only the value
-- bytes change; the game's own description hash (and everything else) is kept.
-- Returns the new blob and whether anything changed.
local function apply_overrides(existing, row_bytes, ovr)
    if not ovr or ovr.n == 0 or #existing == 0 then return existing, false end
    local parts, changed = {}, false
    for i = 0, #existing / row_bytes - 1 do
        local row = existing:sub(i * row_bytes + 1, (i + 1) * row_bytes)
        local key = row:sub(1, ovr.key_len)
        local repl = ovr.map[key]
        if repl then
            local new = key .. repl .. row:sub(ovr.key_len + #repl + 1)
            if new ~= row then row, changed = new, true end
        end
        parts[#parts + 1] = row
    end
    return table.concat(parts), changed
end

-- Grow ONE array and repoint its descriptor. Both arrays share this logic; only
-- the row width, the descriptor offset, the inline offset, the appended rows,
-- the overrides and the destination buffer differ.
--
-- inline_off matters: the shipped form points each array at its OWN inline
-- position. The passive rows start at record+56; the stat rows start after them.
-- Returns: 'applied', before_n, after_n | 'already' | 'foreign...' | reason
local function grow_array(record, pointer, count, desc_off, inline_off, row_bytes, ident_bytes, rows, ovr, dest)
    local pointer_off = record + desc_off
    local inline = record + inline_off

    --   count == 0            the perk ships no rows in this array: CREATE it.
    --   pointer == dest       we already own it; read back what we wrote.
    --   pointer == inline     the shipped inline form.
    -- Anything else is another mod's array, which we leave alone rather than fight.
    local existing
    if count == 0 then
        existing = ''
    elseif pointer == dest then
        existing = api.read(pointer, count * row_bytes)
        if not existing or #existing ~= count * row_bytes then return 'our buffer unreadable' end
    elseif pointer == inline then
        existing = api.read(pointer, count * row_bytes)
        if not existing then return 'inline rows unreadable' end
        if #existing ~= count * row_bytes then return 'inline rows truncated' end
    else
        return 'foreign pointer ' .. hex(pointer)
    end

    -- v4: overrides first, so the base perk's own values can be changed. This is
    -- idempotent: once our buffer holds the new value, a re-check changes nothing.
    local changed
    existing, changed = apply_overrides(existing, row_bytes, ovr)

    -- A row is skipped ONLY when an identical row is already present, compared on
    -- IDENTITY (modifier id + type + value), never on the description field.
    local seen = {}
    for i = 0, #existing / row_bytes - 1 do
        seen[existing:sub(i * row_bytes + 1, i * row_bytes + ident_bytes)] = true
    end
    local kept = {}
    for i = 0, #rows / row_bytes - 1 do
        local row = rows:sub(i * row_bytes + 1, (i + 1) * row_bytes)
        local key = row:sub(1, ident_bytes)
        if not seen[key] then
            seen[key] = true
            kept[#kept + 1] = row
        end
    end
    if #kept == 0 and not changed then
        return 'already'
    end

    local total = existing .. table.concat(kept)
    if #total > 65536 then return 'array would be too large' end
    if #total > #rows + 4096 then return 'array larger than our buffer' end
    if not api.write(dest, total) then return 'dest write failed' end
    if api.read(dest, #total) ~= total then return 'dest read-back failed' end
    -- ONE 16-byte store: pointer and count together.
    local new_count = #existing / row_bytes + #kept
    local descriptor = u64_bytes(dest) .. u64_bytes(new_count)
    local before = api.read(pointer_off, 16)
    if not before then return 'descriptor unreadable before write' end
    if not api.write(pointer_off, descriptor) then return 'descriptor write failed' end
    local after = api.read(pointer_off, 16)
    if after ~= descriptor then
        api.write(pointer_off, before)              -- roll back
        return 'descriptor read-back did not match'
    end
    return 'applied', count, new_count
end

-- Grow BOTH arrays of one record for one profile. Returns:
--   'applied', pm_before, pm_after | 'already' | 'partial: ...' | reason
local function apply_stack(record, prof)
    if not prof or not prof.buffer then return 'no buffer' end
    local head = api.read(record, REC_HEAD)
    if not head then return 'unreadable' end
    local id = u32(head, REC_ID)
    if id ~= prof.perk then return 'not our perk (' .. tostring(id) .. ')' end

    local pm_ptr, pm_cnt = u64(head, REC_PM), u64(head, REC_PM + 8)
    if not pm_ptr or not pm_cnt then return 'passive descriptor unreadable' end

    local before_n, after_n = pm_cnt, pm_cnt
    local final_res = 'already'
    if #prof.ROWS > 0 or prof.OVR.n > 0 then
        local res
        res, before_n, after_n = grow_array(
            record, pm_ptr, pm_cnt, REC_PM, REC_HEAD, ROW_BYTES, ROW_IDENT,
            prof.ROWS, prof.OVR, prof.buffer)
        if res ~= 'applied' and res ~= 'already' then return res end
        if res == 'applied' then final_res = res else before_n, after_n = pm_cnt, pm_cnt end
    end

    if prof.stat_buffer then
        local head2 = api.read(record, REC_HEAD)
        if not head2 then return 'partial: record unreadable' end
        local sm_ptr, sm_cnt = u64(head2, REC_SM), u64(head2, REC_SM + 8)
        if not sm_ptr or not sm_cnt then return 'partial: stat descriptor unreadable' end
        -- The stat rows sit inline AFTER the shipped passive rows. pm_cnt is read
        -- before the passive grow, so on the first patch this is exact; on later
        -- re-checks the stat array already points at our buffer and this is unused.
        local inline_stat = record + REC_HEAD + pm_cnt * ROW_BYTES
        local sres = grow_array(
            record, sm_ptr, sm_cnt, REC_SM, inline_stat - record,
            STAT_BYTES, STAT_IDENT, prof.STATS, prof.SOVR, prof.stat_buffer)
        if sres ~= 'applied' and sres ~= 'already' then
            return 'partial: stat array ' .. tostring(sres)
        end
        if sres == 'applied' then final_res = 'applied' end
    end
    return final_res, before_n, after_n
end

local function complete()
    for _, prof in ipairs(PROFILE_LIST) do
        if prof.sites == 0 then return false end
    end
    return #PROFILE_LIST > 0
end

local function summary()
    local parts = {}
    for _, prof in ipairs(PROFILE_LIST) do
        parts[#parts + 1] = prof.name .. ' (perk ' .. prof.perk .. '): ' ..
            (prof.sites > 0 and ('stacked on ' .. prof.sites .. ' record(s)') or 'not found yet')
    end
    return table.concat(parts, '; ')
end

write_status = function()
    local path = ensure_status_path()
    if not path then return false end
    local verdict
    if state.phase == 'done' or state.phase == 'active' then
        verdict = complete() and 'OK - perk stacked' or 'PARTIAL - perk not found yet'
    elseif state.phase == 'gave_up' then
        verdict = 'FAILED - ' .. tostring(state.status)
    elseif state.phase == 'waiting' then
        verdict = 'WAITING - ' .. tostring(state.status)
    else
        verdict = 'WORKING - ' .. tostring(state.status)
    end
    local lines = {
        verdict,
        'mod=' .. MOD.id,
        'version=' .. MOD.version .. ' author=' .. MOD.author,
        'phase=' .. tostring(state.phase) .. ' frame=' .. tostring(state.frame),
        'applied=' .. state.applied .. ' re-applied=' .. state.reapplied
            .. ' refused=' .. state.refused,
        'rows_appended=' .. tostring(row_count) .. ' passive, ' .. tostring(stat_count) .. ' stat',
        'records_patched=' .. tostring(#sites),
        'profiles: ' .. summary(),
        'revision=' .. MOD.version .. '+v4',
        '',
        'Per-record detail:',
    }
    for i, s in ipairs(sites) do
        lines[#lines + 1] = string.format('  [%d] record=0x%X block=0x%X', i, s.record, s.block)
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Bingus Shared Loader: see BingusSharedLoader.log first line for loader-vN; API N'
    lines[#lines + 1] = 'Log: ' .. tostring(ensure_log_path() or '(log path unavailable)')
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'This file is rewritten only when the mod changes state.'
    return write_file(path, table.concat(lines, '\r\n') .. '\r\n')
end

local function add_site(record, block, prof)
    for _, s in ipairs(sites) do
        if s.record == record then return end
    end
    local result, before_n, after_n = apply_stack(record, prof)
    if result == 'applied' or result == 'already' then
        sites[#sites + 1] = { record = record, block = block, prof = prof }
        prof.sites = prof.sites + 1
        state.applied = state.applied + 1
        log('stacked at ' .. hex(record) .. ' rows ' ..
            tostring(before_n or '?') .. ' -> ' .. tostring(after_n or '?'))
    else
        state.refused = state.refused + 1
        log('record at ' .. hex(record) .. ' left alone: ' .. tostring(result))
    end
end

-- ---------------------------------------------------------------- scanning
local self_addresses = {}
local seen_blocks = {}
local LUA_HEAP_LIMIT = 0x80000000
local skip_low = false

local function handle_block(address)
    if seen_blocks[address] then return end
    seen_blocks[address] = true
    if skip_low and address < LUA_HEAP_LIMIT then return end
    local header = api.read(address, HEADER_BYTES)
    if not header or header:sub(1, 8) ~= NEEDLE then return end
    local kind, payload = u32(header, 8), u32(header, 12)
    if not payload or payload < REC_HEAD or payload > MAX_PAYLOAD then return end
    if kind ~= MOD.type_passive then return end
    -- read the payload only, so our own copy carries no LDLD header for a later sweep
    local blob = api.read(address + HEADER_BYTES, payload)
    if not blob then return end
    local prof = locate_perk(blob)
    if prof then
        add_site(address + HEADER_BYTES, address, prof)
    end
end

local function scan_chunk(addr, size)
    local blob = api.read(addr, size)
    if not blob then return end
    local position = 1
    while true do
        local hit = blob:find(NEEDLE, position, true)
        if not hit then break end
        local address = addr + hit - 1
        local skip = false
        for _, own in ipairs(self_addresses) do
            if own and math.abs(address - own) <= SELF_MARGIN then skip = true break end
        end
        if not skip then pcall(handle_block, address) end
        position = hit + 1
    end
end

local probe, scan

local function begin_round()
    probe = { regions = {}, index = 1, seen = {}, done = false }
    scan = { regions = {}, index = 1, cursor = 0, overlap = #NEEDLE - 1 }
    seen_blocks = {}
    state.rounds = state.rounds + 1
    for _, region in ipairs(api.regions()) do
        if region.allocation_base and region.size >= PROBE_MIN_ALLOC then
            probe.regions[#probe.regions + 1] = region
        end
        scan.regions[#scan.regions + 1] = region
    end
end

local function scan_step()
    local deadline = os.clock() + FRAME_BUDGET
    while not probe.done and probe.index <= #probe.regions do
        local region = probe.regions[probe.index]
        probe.index = probe.index + 1
        local key = string.format('%X', region.allocation_base)
        if not probe.seen[key] then
            probe.seen[key] = true
            pcall(scan_chunk, region.allocation_base, math.min(PROBE_BYTES, region.size))
        end
        if os.clock() >= deadline then return false end
    end
    probe.done = true
    if complete() and skip_low then return true end
    while scan.index <= #scan.regions do
        local region = scan.regions[scan.index]
        if scan.cursor >= region.size then
            scan.index = scan.index + 1
            scan.cursor = 0
        else
            local take = math.min(CHUNK, region.size - scan.cursor)
            pcall(scan_chunk, region.base + scan.cursor, take)
            scan.cursor = scan.cursor + math.max(take - scan.overlap, 1)
            if os.clock() >= deadline then return false end
        end
    end
    return true
end

-- ---------------------------------------------------------------- keeping values applied
local function enforce()
    local kept = {}
    for _, site in ipairs(sites) do
        local header = api.read(site.block, HEADER_BYTES)
        if header and header:sub(1, 8) == NEEDLE and u32(header, 8) == MOD.type_passive then
            local result = apply_stack(site.record, site.prof)
            if result == 'applied' then
                state.reapplied = state.reapplied + 1
                log('was changed by something else; restacked at ' .. hex(site.record))
                pcall(flush_log)
            elseif result ~= 'already' then
                log('no longer fits: ' .. tostring(result))
            end
            kept[#kept + 1] = site
        else
            log('perk table at ' .. hex(site.block) .. ' is gone')
            site.prof.sites = site.prof.sites - 1
        end
    end
    sites = kept
end

-- ---------------------------------------------------------------- tick
local BUS = nil
local next_action = 0

local function tick()
    state.frame = state.frame + 1
    if state.frame < START_FRAME or state.phase == 'gave_up' then return end
    local now = os.time()

    if state.phase == 'searching' then
        local ok, finished = pcall(scan_step)
        if not ok then
            set_status('gave_up', 'scan error: ' .. tostring(finished))
            if BUS then BUS.jobs[MOD.global] = nil end
            return
        end
        if not finished then return end
        if complete() then
            set_status(MOD.retire and 'done' or 'active', 'perk stacked (' .. summary() .. ')')
            next_action = now + ENFORCE_SECONDS
        elseif state.rounds >= MAX_ROUNDS then
            set_status(MOD.retire and 'done' or 'active', 'perk not found (' .. summary() .. ')')
            next_action = now + ENFORCE_SECONDS
        end
        if state.phase == 'done' then
            if BUS then BUS.jobs[MOD.global] = nil end
            return
        end
        if state.phase ~= 'active' then
            set_status('waiting', 'round ' .. state.rounds .. ' incomplete (' .. summary() .. ')')
            next_action = now + ROUND_DELAY_SECONDS
        end
        return
    end

    if now < next_action then return end
    if state.phase == 'active' then
        pcall(enforce)
        next_action = now + ENFORCE_SECONDS
        if complete() or state.rounds >= MAX_ROUNDS then return end
        state.rounds = 0
    end
    begin_round()
    state.phase = 'searching'
end

-- ---------------------------------------------------------------- startup
local ok, failure = pcall(function()
    local loader = rawget(_G, 'CowboyBingusModLoader')
    assert(type(loader) == 'table' and type(loader.api) == 'number' and loader.api >= 1,
           'Bingus Shared Loader v15 or newer (API 1) is required')
    assert(ffi_ok and ffi, 'LuaJIT FFI is unavailable')
    assert(ffi.abi('64bit'), 'Windows x64 is required')
    assert(type(update) == 'function', 'the game update hook is unavailable')
    api = build_api()
    row_count, stat_count = prepare_rows()
    alloc_buffers()
    self_addresses = { api.address_of(NEEDLE) }
    skip_low = (self_addresses[1] or LUA_HEAP_LIMIT) < LUA_HEAP_LIMIT
end)

if not ok then
    state.phase, state.status = 'gave_up', tostring(failure)
    print('[' .. MOD.global .. '] ' .. tostring(failure))
    if api then pcall(flush_log) end
    return
end

set_status('starting', 'waiting for the game to settle')

BUS = rawget(_G, 'OCLAW_UPDATE_BUS')
if not BUS then
    BUS = { jobs = {}, base = update }
    if type(BUS.base) ~= 'function' then return end
    local dispatcher
    dispatcher = function(...)
        local ok, first, second = pcall(BUS.base, ...)
        for _, job in pairs(BUS.jobs) do pcall(job) end
        if ok then return first, second end
    end
    BUS.dispatcher = dispatcher
    _G.OCLAW_UPDATE_BUS = BUS
    update = dispatcher
end
BUS.jobs[MOD.global] = tick