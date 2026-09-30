-- ================================================================ Super Earth Armory Forge engine
-- Shared by every MostlyCloudy tuning mod (credit to SHODAN); the MOD table above says what to change.
--
-- This engine extends armour PERK modifier lists. It is not a stat patcher:
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
-- In the FILE the DLArray holds a relative offset (the modifier rows sit inline right
-- after the 56-byte record). In MEMORY it holds an absolute pointer. We only take a
-- record over when both arrays still point at their inline rows; anything else means
-- another mod has already replaced the array, so we leave it alone rather than fight.
--
-- Every write is read back and the descriptor is checked, or it is rolled back.
-- Changes live in memory only; the game files are never touched.
--
-- ---- v5 (community edit, built on mostlycloudy's v3) ------------------------------
--   * The loadout (which passives, which values) is resolved HERE at runtime, so the
--     in-game panel (F7) can change it live. tools/picker.py and the web builder only
--     store the loadout; tests/test_ingame.py and tests/test_web_parity.js check them against it.
--   * Every perk record is snapshotted when first found. Each apply rebuilds the
--     arrays from the record's own inline rows, so unticking a passive restores the
--     game's data exactly (the descriptor is put back byte for byte).
--   * The inline rows are re-read on every apply, so values another mod edits in place
--     (e.g. SHODAN Stat Editor's Armors tab) are kept.
--   * The panel's changes are saved to %LOCALAPPDATA%\CowboyBingus\Helldivers2\
--     ArmoryForge\loadout.ini (same format as the web builder). Installing a build
--     with a different built-in loadout starts from that loadout again.
--
-- ---- v4 -----------------------------------------------------------------------------
--   * Multiple profiles (one stack per trigger perk) and overrides of the trigger
--     perk's own values.
--
-- ---- v3 changes -----------------------------------------------------------------
--   * ROWS ARE SKIPPED WHEN ALREADY PRESENT, compared on identity (modifier id +
--     type + value), so listing the base perk never applies it twice.
--   * AN ABSENT ARRAY IS CREATED, not refused (a perk with zero stat rows).
--   * Conflicting rows are KEPT: two passives sharing a modifier id at different
--     values both apply (unless the loadout says conflicts = strongest).
--
-- Safety rules, learned from the previous implementation of this idea:
--   * the pointer and the count are written as ONE 16-byte store, so the game can
--     never observe a fresh pointer with a stale count;
--   * a record whose array is already relocated is treated as another mod's work.

if rawget(_G, MOD.global) then return end

local HEADER_BYTES = 24
local MAX_PAYLOAD = 64 * 1024 * 1024
local BUDGET_MIN, BUDGET_MAX, BUDGET_SHARE = 0.0015, 0.004, 0.2   -- seconds of scanning per frame
local HOT_WINDOW = 4 * 1024 * 1024    -- after the first armor-passive block, look this far around it
local CHUNK = 262144
local START_FRAME = 300
local PROBE_MIN_ALLOC = 64 * 1024
local PROBE_BYTES = 128 * 1024
local SELF_MARGIN = 4096
local MAX_ROUNDS = 12
local ROUND_DELAY_SECONDS = 10
local ENFORCE_SECONDS = 5
local SAVE_DELAY_SECONDS = 1
local MAX_LOG_LINES = 400
local PM_BUFFER = 16384      -- bytes of our passive-row copy per record (1024 rows)
local SM_BUFFER = 8192       -- bytes of our stat-row copy per record (682 rows)

-- record layout offsets, from FileDiver datalibrary/passive_bonuses.go
local REC_ID = 0
local REC_PM = 16            -- DLArray for PassiveModifiers
local REC_SM = 32            -- DLArray for StatModifiers
local REC_HEAD = 56          -- rows sit inline at record+56 in the shipped form
local ROW_BYTES = 16         -- one passive modifier
local STAT_BYTES = 12        -- one stat modifier
-- Row IDENTITY, used to decide "this row is already present". The description field
-- is excluded from a passive row's identity: we write 0 there while the game's own
-- rows carry a real hash.
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

local function f32(value)
    local cell = ffi.new('float[1]')
    cell[0] = value
    return ffi.string(cell, 4)
end

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
        'int QueryPerformanceCounter(int64_t *count);',
        'int QueryPerformanceFrequency(int64_t *frequency);',
        'void *GetModuleHandleA(const char *name);',
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

    -- Read into ONE reused buffer (the scan reads hundreds of MB: allocating a fresh
    -- buffer and Lua string per chunk made the garbage collector stutter the game).
    local scratch, scratch_size = nil, 0
    function self.read_into(address, size)
        if size <= 0 then return nil end
        if size > scratch_size then scratch, scratch_size = ffi.new('uint8_t[?]', size), size end
        if kernel.ReadProcessMemory(process, ffi.cast('const void *', address),
                                    scratch, size, counter) == 0 then return nil end
        if tonumber(counter[0]) ~= size then return nil end
        return scratch
    end

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

    local ticks, frequency = ffi.new('int64_t[1]'), ffi.new('int64_t[1]')
    kernel.QueryPerformanceFrequency(frequency)
    local per_second = tonumber(frequency[0])
    function self.now()   -- seconds, high resolution
        kernel.QueryPerformanceCounter(ticks)
        return tonumber(ticks[0]) / per_second
    end

    function self.module_base(name)
        local base = kernel.GetModuleHandleA(name)
        if base == nil then return nil end
        return tonumber(ffi.cast('uintptr_t', base))
    end

    return self
end

-- ---------------------------------------------------------------- files and log
local log_path, status_path, log_lines, log_counts = nil, nil, {}, {}
local last_status_seen = nil
local write_status

local function write_file(path, text)
    if not path then return false end
    local ok, handle = pcall(io.open, path, 'wb')
    if not ok or not handle then return false end
    local wrote = pcall(function() handle:write(text) end)
    pcall(function() handle:close() end)
    return wrote
end

local function read_file(path)
    if not path then return nil end
    local ok, handle = pcall(io.open, path, 'rb')
    if not ok or not handle then return nil end
    local text = handle:read('*a')
    handle:close()
    return text
end

local function data_dir(leaf)
    local ok, resolved = pcall(function()
        local base = os.getenv('LOCALAPPDATA')
        if not base or base == '' then return nil end
        for _, part in ipairs({ 'CowboyBingus', 'Helldivers2', leaf }) do
            base = base .. '/' .. part
            if not api.mkdir(base) then return nil end
        end
        return base
    end)
    if ok then return resolved end
    return nil
end

-- Files the mod keeps: %LOCALAPPDATA%\CowboyBingus\Helldivers2\ArmoryForge\. Saves made
-- before the rename (the PassivePicker folder) are still read until a new one is written.
local function forge_file(name)
    local dir = data_dir('ArmoryForge')
    return dir and (dir .. '/' .. name) or nil
end

local function read_saved(name)
    local text = read_file(forge_file(name))
    if text then return text end
    local base = os.getenv('LOCALAPPDATA')
    if not base or base == '' then return nil end
    return read_file(base .. '/CowboyBingus/Helldivers2/PassivePicker/' .. name)
end

local function ensure_path(file)
    local dir = data_dir('Logs')
    return dir and (dir .. '/' .. file) or nil
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

-- ---------------------------------------------------------------- catalog
-- CATALOG / EFFECT_NAMES / STAT_NAMES / ALIASES are generated above this engine by
-- tools/picker.py. Each passive gets an ordered effect list: its rows, then its stats.
local CAT, CAT_LIST, BY_NAME = {}, {}, {}

local function norm(s) return (s:lower():gsub('[^a-z0-9]', '')) end

for _, c in ipairs(CATALOG) do
    local entry = { id = c.id, name = c.name, rows = c.rows, stats = c.stats, effects = {}, by_key = {} }
    for _, r in ipairs(c.rows) do
        local names = EFFECT_NAMES[r[1]]
        local e = { key = names[1], hint = names[2], kind = 'row', a = r[1], b = r[2], def = r[3], type = r[2] }
        entry.effects[#entry.effects + 1] = e
        entry.by_key[e.key] = e
    end
    for _, s in ipairs(c.stats) do
        local names = STAT_NAMES[s[1]]
        local e = { key = names[1], hint = names[2], kind = 'stat', a = s[1], b = s[2], def = s[3], type = 2 }
        entry.effects[#entry.effects + 1] = e
        entry.by_key[e.key] = e
    end
    CAT[c.id] = entry
    CAT_LIST[#CAT_LIST + 1] = entry
    BY_NAME[norm(c.name)] = c.id
end
for k, v in pairs(ALIASES) do BY_NAME[k] = v end

local function find_perk(text)
    local t = text:match('^%s*(.-)%s*$')
    if t:match('^%d+$') and CAT[tonumber(t)] then return tonumber(t) end
    return BY_NAME[norm(t)]
end

-- ---------------------------------------------------------------- loadout
-- A loadout: { name, retire, hotkey, swap_hotkey, profiles = { profile... } }
-- profile:   { perk, conflicts = 'stack'|'strongest', enabled = { [pid] = true },
--              tweaks = { ['pid.key'] = value }, raw = { {id,type,value} }, raw_stats = { {stat,u1,u2} } }
local function copy_profile(p)
    local out = { perk = p.perk, conflicts = p.conflicts or 'stack', enabled = {}, tweaks = {},
                  raw = {}, raw_stats = {}, swap = p.swap }
    for k, v in pairs(p.enabled or {}) do out.enabled[k] = v end
    for k, v in pairs(p.tweaks or {}) do out.tweaks[k] = v end
    for _, r in ipairs(p.raw or {}) do out.raw[#out.raw + 1] = { r[1], r[2], r[3] } end
    for _, r in ipairs(p.raw_stats or {}) do out.raw_stats[#out.raw_stats + 1] = { r[1], r[2], r[3] } end
    return out
end

-- MOD.default (generated) -> loadout
local function default_loadout()
    local l = { name = MOD.name or MOD.title, retire = MOD.retire, hotkey = MOD.hotkey or 'F7',
                swap_hotkey = MOD.swap_hotkey or 'F9', panel_scale = MOD.panel_scale or 1, profiles = {} }
    for _, d in ipairs(MOD.default or {}) do
        local p = { perk = d.perk, conflicts = d.conflicts, enabled = {}, tweaks = {},
                    raw = d.raw, raw_stats = d.raw_stats }
        for _, pid in ipairs(d.enabled or {}) do p.enabled[pid] = true end
        for _, t in ipairs(d.tweaks or {}) do p.tweaks[t[1] .. '.' .. t[2]] = t[3] end
        l.profiles[#l.profiles + 1] = copy_profile(p)
    end
    return l
end

local function sorted_enabled(p)
    local list = {}
    for pid, on in pairs(p.enabled) do
        if on and pid ~= p.perk and CAT[pid] then list[#list + 1] = pid end
    end
    table.sort(list)
    return list
end

local function strength(typ, v)
    if typ == 2 then
        if v <= 0 then return math.huge end
        return math.abs(math.log(v))
    end
    return math.abs(v)
end

-- Exact duplicates collapse to one; rows sharing an identity at different values all
-- apply ('stack') or only the strongest does. Same rules and order as picker.py resolve().
local function collapse(rows, policy, ident, typ_of)
    local groups, order = {}, {}
    for _, r in ipairs(rows) do
        local g = ident(r)
        if not groups[g] then groups[g] = {}; order[#order + 1] = g end
        local list = groups[g]
        list[#list + 1] = r
    end
    local out, conflicts = {}, 0
    for _, g in ipairs(order) do
        local uniq = {}
        for _, r in ipairs(groups[g]) do
            local dup = false
            for _, u in ipairs(uniq) do if u[3] == r[3] then dup = true break end end
            if not dup then uniq[#uniq + 1] = r end
        end
        if #uniq > 1 then
            conflicts = conflicts + 1
            if policy == 'strongest' then
                local best = uniq[1]
                for k = 2, #uniq do
                    if strength(typ_of(uniq[k]), uniq[k][3]) > strength(typ_of(best), best[3]) then best = uniq[k] end
                end
                uniq = { best }
            end
        end
        for _, u in ipairs(uniq) do out[#out + 1] = u end
    end
    return out, conflicts
end

-- profile -> the rows to append and the base-perk values to replace
local function resolve_profile(p)
    -- Passive Swap edition: the armor gets ONE other passive, exactly as the game ships
    -- it (copied from that passive's own record). Nothing else in the loadout counts, so
    -- no ini, preset or share code can stack passives or change values.
    if MOD.swap_only then
        local y = p.swap
        if y == p.perk or not CAT[y] then y = nil end
        return { swap = y, rows = {}, stats = {}, overrides = {}, stat_overrides = {},
                 enabled = y and { y } or {}, conflicts = 0 }
    end
    local rows, stats = {}, {}
    local function value_of(pid, e)
        local v = p.tweaks[pid .. '.' .. e.key]
        if v == nil then return e.def end
        return v
    end
    local enabled = sorted_enabled(p)
    for _, pid in ipairs(enabled) do
        local c = CAT[pid]
        for _, e in ipairs(c.effects) do
            local src = c.name .. '.' .. e.key
            if e.kind == 'row' then rows[#rows + 1] = { e.a, e.b, value_of(pid, e), src }
            else stats[#stats + 1] = { e.a, e.b, value_of(pid, e), src } end
        end
    end
    for _, r in ipairs(p.raw or {}) do rows[#rows + 1] = { r[1], r[2], r[3], 'raw' } end
    for _, r in ipairs(p.raw_stats or {}) do stats[#stats + 1] = { r[1], r[2], r[3], 'raw_stats' } end

    local overrides, stat_overrides = {}, {}
    local base = CAT[p.perk]
    if base then
        for _, e in ipairs(base.effects) do
            local v = value_of(p.perk, e)
            if v ~= e.def then
                local list = e.kind == 'row' and overrides or stat_overrides
                list[#list + 1] = { e.a, e.b, v, base.name .. '.' .. e.key }
            end
        end
    end
    local c1, c2
    rows, c1 = collapse(rows, p.conflicts, function(r) return r[1] .. '|' .. r[2] end, function(r) return r[2] end)
    stats, c2 = collapse(stats, p.conflicts, function(r) return tostring(r[1]) end, function() return 2 end)
    return { rows = rows, stats = stats, overrides = overrides, stat_overrides = stat_overrides,
             enabled = enabled, conflicts = c1 + c2 }
end

local LOADOUT = nil          -- the live loadout
local DEFAULT_KEY = nil      -- fingerprint of MOD.default, stored in the save file

local function profile_for(perk)
    if not LOADOUT then return nil end
    for _, p in ipairs(LOADOUT.profiles) do if p.perk == perk then return p end end
    return nil
end

-- ---------------------------------------------------------------- loadout file (ini)
local function fmt_num(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%d', v) .. '.0' end
    local s = string.format('%.10g', v)
    if tonumber(s) ~= v then s = string.format('%.17g', v) end
    return s
end

local function serialize(l, base_key)
    local L = {
        '; Super Earth Armory Forge loadout, saved by the in-game panel (' .. (l.hotkey or 'F7') .. ').',
        '; Same format as the web builder: https://hung1510.github.io/Super-Earth-Armory-Forge/',
        '',
        '[settings]',
        'name   = ' .. tostring(l.name or MOD.title):gsub('[;#\r\n]', ' '),
        'retire = ' .. (l.retire and 'true' or 'false'),
        'hotkey = ' .. (l.hotkey or 'F7'),
        'swap_hotkey = ' .. (l.swap_hotkey or 'F9'),
        'panel_scale = ' .. string.format('%.1f', l.panel_scale or 1),
    }
    if base_key then L[#L + 1] = 'base   = ' .. base_key end
    for _, p in ipairs(l.profiles) do
        local c = CAT[p.perk]
        L[#L + 1] = ''
        L[#L + 1] = '[profile: ' .. c.name .. ']'
        if MOD.swap_only then
            L[#L + 1] = 'swap = ' .. (CAT[p.swap] and p.swap ~= p.perk and CAT[p.swap].name or 'original')
        else
        L[#L + 1] = 'conflicts = ' .. (p.conflicts or 'stack')
        for _, e in ipairs(CAT_LIST) do
            if e.id ~= p.perk then
                L[#L + 1] = string.format('%-34s = %s', e.name, p.enabled[e.id] and 'on' or 'off')
            end
        end
        local keys = {}
        for k in pairs(p.tweaks) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local pid, key = k:match('^(%d+)%.(.+)$')
            pid = tonumber(pid)
            if CAT[pid] and (pid == p.perk or p.enabled[pid]) then
                L[#L + 1] = string.format('%-34s = %s', CAT[pid].name .. '.' .. key, fmt_num(p.tweaks[k]))
            end
        end
        local raw = {}
        for _, r in ipairs(p.raw or {}) do raw[#raw + 1] = string.format('0x%08X %d %s', r[1], r[2], fmt_num(r[3])) end
        if #raw > 0 then L[#L + 1] = 'raw       = ' .. table.concat(raw, ', ') end
        raw = {}
        for _, r in ipairs(p.raw_stats or {}) do raw[#raw + 1] = string.format('%d %s %s', r[1], fmt_num(r[2]), fmt_num(r[3])) end
        if #raw > 0 then L[#L + 1] = 'raw_stats = ' .. table.concat(raw, ', ') end
        end
    end
    return table.concat(L, '\r\n') .. '\r\n'
end

local TRUE_WORDS = { on = true, yes = true, ['true'] = true, ['1'] = true, y = true }

-- Lenient reader: anything it does not understand is skipped (and logged), never fatal.
local function parse_loadout(text)
    local l = { profiles = {} }
    local section, prof = nil, nil
    for raw_line in (text .. '\n'):gmatch('([^\n]*)\n') do
        local line = raw_line:gsub('\r$', '')
        local s = line:match('^%s*(.-)%s*$')
        if s ~= '' and not s:match('^[;#]') then
            local v = line:gsub('%s[;#].*$', ''):match('^%s*(.-)%s*$')
            local head = v:match('^%[(.+)%]$')
            if head then
                section, prof = head, nil
                local name = head:match('^%s*[Pp][Rr][Oo][Ff][Ii][Ll][Ee]%s*:%s*(.-)%s*$')
                if name then
                    local perk = find_perk(name)
                    if perk then
                        prof = { perk = perk, conflicts = 'stack', enabled = {}, tweaks = {}, raw = {}, raw_stats = {} }
                        l.profiles[#l.profiles + 1] = prof
                    else
                        log('loadout: unknown armor passive [' .. head .. '], skipped')
                    end
                end
            else
                local k, val = v:match('^(.-)%s*=%s*(.*)$')
                if k and section == 'settings' then
                    if k == 'name' then l.name = val
                    elseif k == 'retire' then l.retire = TRUE_WORDS[val:lower()] or false
                    elseif k == 'hotkey' or k == 'swap_hotkey' then
                        -- F1..F12 (quick-swap also OFF); anything else keeps the default key
                        local key, fn = val:upper(), tonumber(val:upper():match('^F(%d%d?)$'))
                        if (fn and fn >= 1 and fn <= 12) or (key == 'OFF' and k == 'swap_hotkey') then l[k] = key
                        else log('loadout: ' .. k .. ' = ' .. val .. ' is not F1..F12; using the default') end
                    elseif k == 'panel_scale' then
                        local sc = tonumber((val:gsub('%%$', '')))
                        if sc and val:find('%%$') then sc = sc / 100 end
                        if sc then l.panel_scale = math.max(0.8, math.min(1.5, math.floor(sc * 10 + 0.5) / 10)) end
                    elseif k == 'base' then l.base = val end
                elseif k and prof then
                    local lk = k:lower()
                    if lk == 'swap' then
                        local pid = find_perk(val)
                        prof.swap = (pid and pid ~= prof.perk) and pid or nil
                    elseif lk == 'conflicts' then
                        prof.conflicts = (val:lower() == 'strongest') and 'strongest' or 'stack'
                    elseif lk == 'raw' or lk == 'raw_stats' then
                        for chunk in val:gmatch('[^,]+') do
                            local a, b, c = chunk:match('^%s*(%S+)%s+(%S+)%s+(%S+)%s*$')
                            local na, nb, nc = a and tonumber(a), b and tonumber(b), c and tonumber(c)
                            if na and nb and nc then
                                local list = lk == 'raw' and prof.raw or prof.raw_stats
                                list[#list + 1] = { na, nb, nc }
                            end
                        end
                    elseif k:find('%.') then
                        local pname, key = k:match('^(.*)%.([^%.]+)$')
                        local pid = pname and find_perk(pname)
                        local n = tonumber(val)
                        if pid and n and CAT[pid].by_key[key] then prof.tweaks[pid .. '.' .. key] = n
                        else log('loadout: skipped ' .. k) end
                    else
                        local pid = find_perk(k)
                        if pid and pid ~= prof.perk then prof.enabled[pid] = TRUE_WORDS[val:lower()] or nil
                        elseif not pid then log('loadout: unknown passive ' .. k .. ', skipped') end
                    end
                end
            end
        end
    end
    return l
end

-- djb2 over the canonical text of the built-in loadout
local function fingerprint(l)
    -- settings lines added in later versions are left out, so updating the mod keeps
    -- the panel's saved edits
    local text = serialize(l, nil):gsub('swap_hotkey = [^\r\n]*\r\n', ''):gsub('panel_scale = [^\r\n]*\r\n', '')
    -- the comment header is hashed as 4.x wrote it, so renaming the mod or its web
    -- address never resets anyone's saved edits
    text = text:gsub('^;[^\r\n]*\r\n;[^\r\n]*\r\n',
        '; Passive Picker loadout, saved by the in-game panel (' .. (l.hotkey or 'F7') .. ').\r\n' ..
        '; Same format as the web builder: https://hung1510.github.io/HD2-Armor-Transmog/\r\n', 1)
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
    return string.format('%08x', h)
end

local function save_path() return forge_file(MOD.swap_only and 'loadout-swap.ini' or 'loadout.ini') end

local save_at = nil
local function save_now()
    save_at = nil
    local path = save_path()
    if not path then return false end
    local ok = write_file(path, serialize(LOADOUT, DEFAULT_KEY))
    if not ok then log('could not save ' .. path) end
    return ok
end

local function load_loadout()
    local def = default_loadout()
    DEFAULT_KEY = fingerprint(def)
    local path = save_path()
    local text = read_saved(MOD.swap_only and 'loadout-swap.ini' or 'loadout.ini')
    if text then
        local ok, saved = pcall(parse_loadout, text)
        -- a blank install (the release zip) always keeps what you built in the panel
        if ok and (saved.base == DEFAULT_KEY or MOD.blank) and (#saved.profiles > 0 or MOD.blank) then
            saved.name = saved.name or def.name
            if saved.retire == nil then saved.retire = def.retire end
            saved.hotkey = saved.hotkey or def.hotkey
            saved.swap_hotkey = saved.swap_hotkey or def.swap_hotkey
            saved.panel_scale = saved.panel_scale or def.panel_scale
            log('loadout: using the panel save ' .. path)
            return saved, 'saved'
        elseif ok and saved.base ~= DEFAULT_KEY then
            log('loadout: a different build is installed; starting from its built-in loadout')
        else
            log('loadout: could not read ' .. tostring(path) .. ': ' .. tostring(saved))
        end
    end
    return def, 'built-in'
end

-- ---------------------------------------------------------------- sites
-- One site per perk record found in memory (every perk, not only the profiles', so the
-- panel can stack onto any armor). The arrays' original descriptors are kept to put
-- the game's data back exactly.
local sites = {}             -- list
local sites_by_perk = {}     -- perk -> list of sites
local perks_found = 0

local function apply_overrides(existing, row_bytes, key_len, map)
    if not map or #existing == 0 then return existing end
    local parts = {}
    for i = 0, #existing / row_bytes - 1 do
        local row = existing:sub(i * row_bytes + 1, (i + 1) * row_bytes)
        local key = row:sub(1, key_len)
        local repl = map[key]
        if repl then row = key .. repl .. row:sub(key_len + #repl + 1) end
        parts[#parts + 1] = row
    end
    return table.concat(parts)
end

local function append_rows(existing, row_bytes, ident_bytes, rows)
    local seen = {}
    for i = 0, #existing / row_bytes - 1 do
        seen[existing:sub(i * row_bytes + 1, i * row_bytes + ident_bytes)] = true
    end
    local kept = { existing }
    for _, row in ipairs(rows) do
        local key = row:sub(1, ident_bytes)
        if not seen[key] then seen[key] = true; kept[#kept + 1] = row end
    end
    return table.concat(kept)
end

-- the arrays a site should hold for a resolved profile (nil profile = the game's own)
local function desired(site, res, inline_pm, inline_sm)
    if not res then return inline_pm, inline_sm end
    if MOD.swap_only then
        -- the swapped-in passive's own rows, read fresh from its record; the game's own
        -- rows until that record has been found
        for _, src in ipairs(res.swap and sites_by_perk[res.swap] or {}) do
            if not src.foreign then
                local pm = src.pm_count0 > 0 and api.read(src.record + REC_HEAD, src.pm_count0 * ROW_BYTES) or ''
                local sm = src.sm_count0 > 0 and api.read(src.sm_inline, src.sm_count0 * STAT_BYTES) or ''
                if pm and sm then return pm, sm end
            end
        end
        return inline_pm, inline_sm
    end
    local omap, smap = {}, {}
    for _, r in ipairs(res.overrides) do omap[u32_bytes(r[1]) .. u32_bytes(r[2])] = f32(r[3]) end
    for _, r in ipairs(res.stat_overrides) do smap[u32_bytes(r[1])] = f32(r[2]) .. f32(r[3]) end
    local prow, srow = {}, {}
    for _, r in ipairs(res.rows) do prow[#prow + 1] = u32_bytes(r[1]) .. u32_bytes(r[2]) .. f32(r[3]) .. u32_bytes(0) end
    for _, r in ipairs(res.stats) do srow[#srow + 1] = u32_bytes(r[1]) .. f32(r[2]) .. f32(r[3]) end
    local pm = append_rows(apply_overrides(inline_pm, ROW_BYTES, 8, omap), ROW_BYTES, ROW_IDENT, prow)
    local sm = append_rows(apply_overrides(inline_sm, STAT_BYTES, 4, smap), STAT_BYTES, STAT_IDENT, srow)
    return pm, sm
end

-- Point one array at `blob`: the original descriptor when blob is the game's own rows,
-- else our buffer. Returns 'same' | 'applied' | reason.
local function set_array(site, which, blob, inline)
    local desc_off = which == 'pm' and REC_PM or REC_SM
    local row_bytes = which == 'pm' and ROW_BYTES or STAT_BYTES
    local original = site[which .. '_desc0']
    local want
    local at = site.record + desc_off
    local now = api.read(at, 16)
    if not now then return 'descriptor unreadable' end
    if blob == inline then
        want = original
    else
        -- Two buffers per array, used in turn: the new rows go into the one the game is
        -- NOT reading, then one 16-byte store switches the game over. The game never
        -- sees a half-written array.
        local cap = which == 'pm' and PM_BUFFER or SM_BUFFER
        if #blob > cap then return 'too many rows for the buffer' end
        local bufs = site[which .. '_bufs']
        if not bufs then
            local a, b = api.alloc(cap), api.alloc(cap)
            if not a or not b then return 'could not allocate a buffer' end
            bufs = { a, b }
            site[which .. '_bufs'] = bufs
        end
        local count = u64_bytes(#blob / row_bytes)
        -- already showing exactly this? nothing to do
        for _, buf in ipairs(bufs) do
            if now == u64_bytes(buf) .. count and api.read(buf, #blob) == blob then return 'same' end
        end
        local buf = (u64(now, 0) == bufs[1]) and bufs[2] or bufs[1]
        if not api.write(buf, blob) then return 'buffer write failed' end
        if api.read(buf, #blob) ~= blob then return 'buffer read-back failed' end
        want = u64_bytes(buf) .. count
    end
    if now == want then return 'same' end
    if not api.write(at, want) then return 'descriptor write failed' end
    if api.read(at, 16) ~= want then
        api.write(at, now)
        return 'descriptor read-back did not match'
    end
    return 'applied'
end

local function site_intact(site)
    local header = api.read(site.block, HEADER_BYTES)
    return header and header:sub(1, 8) == NEEDLE and u32(header, 8) == MOD.type_passive
        and u32(api.read(site.record, 4) or '', 0) == site.perk
end

-- Apply the live loadout to one site. The game's inline rows are re-read every time,
-- so edits other mods make in place are kept.
local function apply_site(site, res)
    if site.foreign then return 'foreign' end
    if not site_intact(site) then return 'gone' end
    local pm = site.pm_count0 > 0 and api.read(site.record + REC_HEAD, site.pm_count0 * ROW_BYTES) or ''
    local sm = site.sm_count0 > 0 and api.read(site.sm_inline, site.sm_count0 * STAT_BYTES) or ''
    if not pm or not sm then return 'inline rows unreadable' end
    local want_pm, want_sm = desired(site, res, pm, sm)
    local r1 = set_array(site, 'pm', want_pm, pm)
    if r1 ~= 'same' and r1 ~= 'applied' then return r1 end
    local r2 = set_array(site, 'sm', want_sm, sm)
    if r2 ~= 'same' and r2 ~= 'applied' then return 'stat array: ' .. r2 end
    site.rows_now = #want_pm / ROW_BYTES
    site.stats_now = #want_sm / STAT_BYTES
    site.added = site.rows_now - site.pm_count0 + site.stats_now - site.sm_count0
    if r1 == 'applied' or r2 == 'applied' then return 'applied' end
    return 'same'
end

local last_result = {}       -- perk -> { res = resolved, text = status }

local function apply_perk(perk, quiet)
    local list = sites_by_perk[perk]
    if not list then return nil end
    local prof = profile_for(perk)
    local res = prof and resolve_profile(prof) or nil
    local worst, changed = nil, false
    for _, site in ipairs(list) do
        local r = apply_site(site, res)
        if r == 'applied' then changed = true
        elseif r ~= 'same' then worst = r end
    end
    last_result[perk] = { res = res, error = worst }
    if changed then
        state.applied = state.applied + 1
        if not quiet then log('applied ' .. CAT[perk].name .. (res and (': ' .. #res.enabled .. ' passive(s)') or ': restored')) end
    end
    if worst and worst ~= 'gone' then log(CAT[perk].name .. ': ' .. worst) end
    return changed
end

local function apply_all()
    for perk in pairs(sites_by_perk) do apply_perk(perk) end
end

local function capture(record, block, blob)
    for _, s in ipairs(sites) do if s.record == record then return end end
    local perk = u32(blob, REC_ID)
    if not CAT[perk] then return end
    local pm_ptr, pm_cnt = u64(blob, REC_PM), u64(blob, REC_PM + 8)
    local sm_ptr, sm_cnt = u64(blob, REC_SM), u64(blob, REC_SM + 8)
    if not (pm_ptr and pm_cnt and sm_ptr and sm_cnt) or pm_cnt > 64 or sm_cnt > 64 then return end
    local site = { record = record, block = block, perk = perk, pm_count0 = pm_cnt, sm_count0 = sm_cnt,
                   pm_desc0 = blob:sub(REC_PM + 1, REC_PM + 16), sm_desc0 = blob:sub(REC_SM + 1, REC_SM + 16),
                   sm_inline = record + REC_HEAD + pm_cnt * ROW_BYTES }
    local pm_ok = pm_cnt == 0 or pm_ptr == record + REC_HEAD
    local sm_ok = sm_cnt == 0 or sm_ptr == site.sm_inline
    if not (pm_ok and sm_ok) then
        site.foreign = true
        state.refused = state.refused + 1
        log(CAT[perk].name .. ' at ' .. hex(record) .. ' is already changed by another mod; left alone')
    end
    sites[#sites + 1] = site
    if not sites_by_perk[perk] then
        sites_by_perk[perk] = {}
        perks_found = perks_found + 1
    end
    local list = sites_by_perk[perk]
    list[#list + 1] = site
    if not site.foreign then apply_perk(perk) end
    if MOD.swap_only and LOADOUT then      -- armors that were waiting for this passive
        for _, p in ipairs(LOADOUT.profiles) do
            if p.swap == perk and p.perk ~= perk then apply_perk(p.perk) end
        end
    end
end

-- ---------------------------------------------------------------- passive dump
-- Every armor passive the game has, as the game shipped it (read before anything is
-- changed), written to ArmoryForge\passives-dump.txt once the scan is done. After a
-- game patch, `python tools/picker.py check-dump` compares it with the catalog and
-- prints new passives and changed values, ready to paste.
local dump, dump_order, unknown_found = {}, {}, 0

local function f32_of(bytes)
    local cell = ffi.new('float[1]')
    ffi.copy(cell, bytes, 4)
    return cell[0]
end

local function note_for_dump(record, blob)
    local perk = u32(blob, REC_ID)
    if not perk or dump[perk] then return end
    local pm_ptr, pm_cnt = u64(blob, REC_PM), u64(blob, REC_PM + 8)
    local sm_ptr, sm_cnt = u64(blob, REC_SM), u64(blob, REC_SM + 8)
    if not (pm_ptr and pm_cnt and sm_ptr and sm_cnt) or pm_cnt > 64 or sm_cnt > 64 then return end
    local sm_off = REC_HEAD + pm_cnt * ROW_BYTES
    local inline = (pm_cnt == 0 or pm_ptr == record + REC_HEAD) and (sm_cnt == 0 or sm_ptr == record + sm_off)
    local function take(ptr, off, n, width)
        if n == 0 then return '' end
        if inline and #blob >= off + n * width then return blob:sub(off + 1, off + n * width) end
        return api.read(ptr, n * width)
    end
    local pm, sm = take(pm_ptr, REC_HEAD, pm_cnt, ROW_BYTES), take(sm_ptr, sm_off, sm_cnt, STAT_BYTES)
    if not pm or not sm then return end
    local e = { perk = perk, name = u32(blob, 4) or 0, inline = inline, rows = {}, stats = {} }
    for i = 0, pm_cnt - 1 do
        local r = pm:sub(i * ROW_BYTES + 1, (i + 1) * ROW_BYTES)
        e.rows[#e.rows + 1] = { u32(r, 0), u32(r, 4), f32_of(r:sub(9, 12)) }
    end
    for i = 0, sm_cnt - 1 do
        local r = sm:sub(i * STAT_BYTES + 1, (i + 1) * STAT_BYTES)
        e.stats[#e.stats + 1] = { u32(r, 0), f32_of(r:sub(5, 8)), f32_of(r:sub(9, 12)) }
    end
    dump[perk] = e
    dump_order[#dump_order + 1] = perk
    if not CAT[perk] and perk ~= 0 then       -- perk 0: the game's empty "no passive" entry
        unknown_found = unknown_found + 1
        log('armor passive ' .. perk .. ' is not in the catalog (new in this game version?); see passives-dump.txt')
    end
end

local function game_stamp()
    local base = api.module_base and api.module_base('game.dll')
    if not base then return nil end
    local dos = api.read(base, 64)
    local pe = dos and u32(dos, 60)
    local head = pe and api.read(base + pe, 16)
    if not head or head:sub(1, 4) ~= 'PE\0\0' then return nil end
    return u32(head, 8)
end

local function dump_path() return forge_file('passives-dump.txt') end

local dump_written = 0
local function write_dump()
    local path = dump_path()
    if not path or #dump_order == 0 or #dump_order == dump_written then return false end
    table.sort(dump_order)
    local ok_stamp, stamp = pcall(game_stamp)
    local L = {
        '# Armory Forge passive dump v1: every armor passive in the game, as shipped.',
        '# Compare with the catalog: python tools/picker.py check-dump "' .. path .. '"',
        'mod ' .. MOD.version,
        'game_stamp ' .. ((ok_stamp and stamp) and string.format('0x%08X', stamp) or 'unknown'),
        'written ' .. os.date('!%Y-%m-%dT%H:%M:%SZ'),
        'passives ' .. #dump_order,
    }
    for _, perk in ipairs(dump_order) do
        local e = dump[perk]
        L[#L + 1] = string.format('perk %d name 0x%08X%s', perk, e.name, e.inline and '' or ' modified')
        for _, r in ipairs(e.rows) do L[#L + 1] = string.format('row 0x%08X %d %.9g', r[1], r[2], r[3]) end
        for _, s in ipairs(e.stats) do L[#L + 1] = string.format('stat %d %.9g %.9g', s[1], s[2], s[3]) end
        L[#L + 1] = 'end'
    end
    local ok = write_file(path, table.concat(L, '\r\n') .. '\r\n')
    if ok then dump_written = #dump_order end
    if ok then log('wrote ' .. #dump_order .. ' armor passives to ' .. path .. (unknown_found > 0
        and (' (' .. unknown_found .. ' not in the catalog)') or '')) end
    return ok
end

-- ---------------------------------------------------------------- status file
local function complete() return perks_found >= #CAT_LIST end

-- Stop searching even if a catalog passive is missing (a game patch removed or renumbered
-- it): every armor with a stack is found, most of the catalog is, and the window around
-- the table was checked. Otherwise one missing passive meant 12 full rescans.
local function good_enough()
    if complete() then return true end
    if not state.scanned_window or perks_found < #CAT_LIST - 3 then return false end
    for _, p in ipairs(LOADOUT and LOADOUT.profiles or {}) do
        if not sites_by_perk[p.perk] then return false end
    end
    return true
end

local function summary()
    local parts = {}
    for _, p in ipairs(LOADOUT and LOADOUT.profiles or {}) do
        local name = CAT[p.perk].name
        local list = sites_by_perk[p.perk]
        if not list then parts[#parts + 1] = name .. ' (perk ' .. p.perk .. '): not found yet'
        else
            local added = 0
            for _, s in ipairs(list) do added = math.max(added, s.added or 0) end
            parts[#parts + 1] = name .. ' (perk ' .. p.perk .. '): stacked on ' .. #list .. ' record(s), +' .. added .. ' rows'
        end
    end
    if #parts == 0 then return 'no stacks set (open the panel with ' .. (LOADOUT and LOADOUT.hotkey or 'F7') .. ')' end
    return table.concat(parts, '; ')
end

write_status = function()
    local path = ensure_status_path()
    if not path then return false end
    local verdict
    local stacked = false
    for _, p in ipairs(LOADOUT and LOADOUT.profiles or {}) do if sites_by_perk[p.perk] then stacked = true end end
    if state.phase == 'ready' then
        verdict = stacked and 'OK - perk stacked' or 'OK - ready (no stack found yet)'
    elseif state.phase == 'gave_up' then
        verdict = 'FAILED - ' .. tostring(state.status)
    else
        verdict = 'WORKING - ' .. tostring(state.status)
    end
    local lines = {
        verdict,
        'mod=' .. MOD.id,
        'version=' .. MOD.version .. ' author=' .. MOD.author,
        'phase=' .. tostring(state.phase) .. ' frame=' .. tostring(state.frame),
        'applied=' .. state.applied .. ' re-applied=' .. state.reapplied .. ' refused=' .. state.refused,
        'armor passives found=' .. perks_found .. ' of ' .. #CAT_LIST ..
            (unknown_found > 0 and ('; NOT in the catalog=' .. unknown_found .. ' (new passives? see passives-dump.txt)') or ''),
        'Passive dump: ' .. tostring(dump_path() or '(unavailable)'),
        'loadout=' .. tostring(state.loadout_source) .. ' (panel: ' .. (LOADOUT and LOADOUT.hotkey or 'F7') .. ')',
        'profiles: ' .. summary(),
        '',
        'Bingus Shared Loader: see BingusSharedLoader.log first line for loader-vN; API N',
        'Log: ' .. tostring(ensure_log_path() or '(log path unavailable)'),
        'Saved loadout: ' .. tostring(save_path() or '(unavailable)'),
    }
    return write_file(path, table.concat(lines, '\r\n') .. '\r\n')
end

-- The panel calls this after every change: apply at once, save a moment later.
local function loadout_changed(perks)
    for _, perk in ipairs(perks or {}) do apply_perk(perk) end
    if not perks then apply_all() end
    save_at = (api.now and api.now() or os.clock()) + SAVE_DELAY_SECONDS
    pcall(write_status)
end

-- ---------------------------------------------------------------- scanning
local self_addresses = {}
local seen_blocks = {}
local LUA_HEAP_LIMIT = 0x80000000
local skip_low = false

-- where the armor-passive blocks were found this round (see the scan below)
local found_lo, found_hi = nil, nil

local function handle_block(address)
    if seen_blocks[address] then return end
    seen_blocks[address] = true
    if skip_low and address < LUA_HEAP_LIMIT then return end
    local header = api.read(address, HEADER_BYTES)
    if not header or header:sub(1, 8) ~= NEEDLE then return end
    local kind, payload = u32(header, 8), u32(header, 12)
    if not payload or payload < REC_HEAD or payload > MAX_PAYLOAD then return end
    if kind ~= MOD.type_passive then return end
    if not found_lo or address < found_lo then found_lo = address end
    if not found_hi or address > found_hi then found_hi = address end
    -- read the payload only, so our own copy carries no LDLD header for a later sweep
    local blob = api.read(address + HEADER_BYTES, payload)
    if not blob then return end
    pcall(note_for_dump, address + HEADER_BYTES, blob)
    capture(address + HEADER_BYTES, address, blob)
end

-- APIs without read_into (tests, older builds): same thing through read()
local function ensure_read_into()
    if api.read_into then return end
    local scratch, scratch_size = nil, 0
    api.read_into = function(address, size)
        local s = api.read(address, size)
        if not s or #s ~= size then return nil end
        if size > scratch_size then scratch, scratch_size = ffi.new('uint8_t[?]', size), size end
        ffi.copy(scratch, s, size)
        return scratch
    end
end

-- The LDLD blocks of the armor-passive table sit together. Remember where the first
-- one was found; once every known passive is in, a window around that spot is checked
-- (for passives new in a game patch) and the scan stops, instead of reading all of the
-- game's memory.
local hits = {}

-- Finds LDLD headers with a byte loop over the reused buffer: no allocation, and
-- LuaJIT compiles the loop. Hits are handled after the loop because handle_block reads
-- memory itself.
local function scan_chunk(addr, size)
    local p = api.read_into(addr, size)
    if not p then return end
    local n = 0
    for i = 0, size - 8 do
        if p[i] == 0x4C and p[i + 1] == 0x44 and p[i + 2] == 0x4C and p[i + 3] == 0x44
           and p[i + 4] == 1 and p[i + 5] == 0 and p[i + 6] == 0 and p[i + 7] == 0 then
            n = n + 1
            hits[n] = addr + i
        end
    end
    for k = 1, n do
        local address = hits[k]
        hits[k] = nil
        local skip = false
        for _, own in ipairs(self_addresses) do
            if own and math.abs(address - own) <= SELF_MARGIN then skip = true break end
        end
        if not skip then pcall(handle_block, address) end
    end
end

local probe, scan

local function begin_round()
    probe = { regions = {}, index = 1, seen = {}, done = false }
    scan = { regions = {}, index = 1, cursor = 0, overlap = #NEEDLE - 1, hot = nil, hot_done = false }
    seen_blocks = {}
    found_lo, found_hi = nil, nil
    state.rounds = state.rounds + 1
    for _, region in ipairs(api.regions()) do
        if region.allocation_base and region.size >= PROBE_MIN_ALLOC then
            probe.regions[#probe.regions + 1] = region
        end
        scan.regions[#scan.regions + 1] = region
    end
end

-- A share of the frame, measured: ~3 ms at 60 fps, ~1.5 ms at 144 fps, at most 4 ms.
local last_frame_at, frame_dt = nil, 1 / 60
local function frame_budget()
    local now = api.now()
    if last_frame_at then
        local d = now - last_frame_at
        if d > 0 and d < 0.5 then frame_dt = frame_dt * 0.8 + d * 0.2 end
    end
    last_frame_at = now
    return math.max(BUDGET_MIN, math.min(BUDGET_MAX, frame_dt * BUDGET_SHARE))
end

-- the window around the first armor-passive block, clamped to the region holding it
local function hot_window()
    for _, r in ipairs(scan.regions) do
        if found_lo >= r.base and found_lo < r.base + r.size then
            local lo = math.max(r.base, found_lo - HOT_WINDOW)
            local hi = math.min(r.base + r.size, found_hi + HOT_WINDOW)
            return { base = lo, size = hi - lo, cursor = 0 }
        end
    end
    return { base = found_lo, size = 0, cursor = 0 }
end

local function scan_step()
    local deadline = api.now() + frame_budget()
    while not probe.done and probe.index <= #probe.regions do
        local region = probe.regions[probe.index]
        probe.index = probe.index + 1
        local key = string.format('%X', region.allocation_base)
        if not probe.seen[key] then
            probe.seen[key] = true
            pcall(scan_chunk, region.allocation_base, math.min(PROBE_BYTES, region.size))
        end
        if api.now() >= deadline then return false end
    end
    probe.done = true
    while true do
        if found_lo and not scan.hot_done then
            scan.hot = scan.hot or hot_window()
            local h = scan.hot
            if h.cursor >= h.size then
                scan.hot_done = true
                state.scanned_window = true
            else
                local take = math.min(CHUNK, h.size - h.cursor)
                pcall(scan_chunk, h.base + h.cursor, take)
                h.cursor = h.cursor + math.max(take - scan.overlap, 1)
            end
        elseif complete() and scan.hot_done then
            return true                      -- everything known found, its neighbourhood checked
        elseif scan.index <= #scan.regions then
            local region = scan.regions[scan.index]
            if scan.cursor >= region.size then
                scan.index = scan.index + 1
                scan.cursor = 0
            else
                local take = math.min(CHUNK, region.size - scan.cursor)
                pcall(scan_chunk, region.base + scan.cursor, take)
                scan.cursor = scan.cursor + math.max(take - scan.overlap, 1)
            end
        else
            return true
        end
        if api.now() >= deadline then return false end
    end
end

-- ---------------------------------------------------------------- keeping values applied
-- Re-applies when the game reloads a record (or another mod edits its inline rows).
local function enforce()
    local kept, gone = {}, false
    for _, site in ipairs(sites) do
        if site_intact(site) then
            kept[#kept + 1] = site
        else
            gone = true
            log(CAT[site.perk].name .. ': perk table at ' .. hex(site.block) .. ' is gone')
        end
    end
    if gone then
        sites, sites_by_perk, perks_found = kept, {}, 0
        for _, s in ipairs(kept) do
            if not sites_by_perk[s.perk] then sites_by_perk[s.perk] = {}; perks_found = perks_found + 1 end
            local list = sites_by_perk[s.perk]
            list[#list + 1] = s
        end
    end
    for perk in pairs(sites_by_perk) do
        if apply_perk(perk, true) then
            state.reapplied = state.reapplied + 1
            log('was changed by something else; re-applied ' .. CAT[perk].name)
            pcall(flush_log)
        end
    end
    return gone
end

-- ---------------------------------------------------------------- panel hook
-- tools/panel.lua (appended after this engine) replaces this with the in-game panel.
local panel_tick = function(now) end

