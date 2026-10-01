-- ================================================================ research build only
-- Built by `python tools/picker.py research`; never part of a release. It answers one
-- question for a future feature: is an armor's weight class (light / medium / heavy)
-- plain data we can change, and does changing it change speed and stamina in game?
--
-- 1. Every armor kit record (HelldiverCustomizationKit, LDLD type 0xD9A55AA0) is written
--    to ArmoryForge\kits-dump.txt: id, passive, and every piece with its slot and weight.
-- 2. With MOD.research.weight set, the weight of every ARMOR piece of every armor kit is
--    set to it (memory only; restart the game to undo).
-- 3. Every LDLD table type seen in memory is counted, to spot other stat tables.
--
-- Layout from FileDiver datalibrary/armor_sets.go (xypwn, BSD-3-Clause):
--   kit   +0 Id  +4 DlcId  +8 SetId  +12 NameUpper  +16 NameCased  +20 Description
--         +24 Rarity  +28 Passive  +32 Archive(u64)  +40 Type(0 armor,1 helmet,2 cape)
--         +44 Unk  +48 BodyArray(ptr)  +56 BodyCount                          = 64 bytes
--   body  +0 Type(0 stocky,1 slim,3 any)  +4 Unk  +8 Pieces(ptr)  +16 PieceCount = 24
--   piece +0 Path(u64)  +8 Slot  +12 Type(0 armor,1 undergarment,2 accessory)
--         +16 Weight(0 light,1 medium,2 heavy)  +20 Unk  ... hashes, tones     = 96
-- Pointers are offsets from the record in the game files and absolute once loaded.
research = { kits = {}, order = {}, types = {}, changed = 0, failed = 0, written = 0 }

do   -- locals stay in this block: the main chunk is near Lua's 200-local limit

local R = research
local KIT_BYTES, BODY_BYTES, PIECE_BYTES = 64, 24, 96
local WEIGHT = { [0] = 'light', [1] = 'medium', [2] = 'heavy' }
local SLOT = { [0] = 'helmet', 'cape', 'torso', 'hips', 'left_leg', 'right_leg', 'left_arm',
               'right_arm', 'left_shoulder', 'right_shoulder' }

-- 64-bit hashes stay as their 8 raw bytes: a Lua number can't hold them exactly
local NO_LUT = string.rep('\0', 8)
function R.hex8(b)
    if not b or #b ~= 8 then return '-' end
    local t = {}
    for i = 8, 1, -1 do t[#t + 1] = string.format('%02X', b:byte(i)) end
    return '0x' .. table.concat(t)
end

local function where(record, v, size)
    if not v then return nil end
    if v >= 0 and v < size then return record + v end
    return v
end

local function kit(record, blob)
    if R.kits[record] or #blob < KIT_BYTES then return end
    local k = { record = record, id = u32(blob, 0), dlc = u32(blob, 4), set = u32(blob, 8),
                rarity = u32(blob, 24), passive = u32(blob, 28), archive = u64(blob, 32),
                type = u32(blob, 40), head = blob:sub(1, KIT_BYTES), bodies = {} }
    local bptr, bcount = where(record, u64(blob, 48), #blob), u64(blob, 56)
    if not bptr or not bcount or bcount > 8 then k.bad = 'body array' end
    local bodies = (not k.bad and bcount > 0) and api.read(bptr, bcount * BODY_BYTES) or ''
    if not bodies then k.bad = 'body array unreadable' end
    for b = 0, (k.bad and -1 or bcount - 1) do
        local rb = bodies:sub(b * BODY_BYTES + 1, (b + 1) * BODY_BYTES)
        local body = { type = u32(rb, 0), pieces = {} }
        local pptr, pcount = where(record, u64(rb, 8), #blob), u64(rb, 16)
        if pptr and pcount and pcount <= 64 then
            local raw = pcount > 0 and api.read(pptr, pcount * PIECE_BYTES) or ''
            for p = 0, (raw and pcount - 1 or -1) do
                local rp = raw:sub(p * PIECE_BYTES + 1, (p + 1) * PIECE_BYTES)
                body.pieces[#body.pieces + 1] = { at = pptr + p * PIECE_BYTES, path = u64(rp, 0),
                    slot = u32(rp, 8), type = u32(rp, 12), weight = u32(rp, 16), lut = rp:sub(25, 32) }
            end
        else
            body.bad = true
        end
        k.bodies[#k.bodies + 1] = body
    end
    -- the experiment: armor pieces of armor kits get the chosen weight
    local want = MOD.research and MOD.research.weight
    if want and k.type == 0 then
        for _, body in ipairs(k.bodies) do
            for _, pc in ipairs(body.pieces) do
                if pc.type == 0 and pc.weight ~= want then
                    local ok = api.write(pc.at + 16, u32_bytes(want))
                    local back = ok and api.read(pc.at + 16, 4)
                    if back and u32(back, 0) == want then pc.now = want; R.changed = R.changed + 1
                    else R.failed = R.failed + 1 end
                end
            end
        end
    end
    R.kits[record] = k
    R.order[#R.order + 1] = record
end

-- every LDLD block the scan meets comes through here
function R.block(address, kind, payload)
    local t = R.types[kind]
    if not t then t = { n = 0, lo = payload, hi = payload }; R.types[kind] = t end
    t.n = t.n + 1
    t.lo, t.hi = math.min(t.lo, payload), math.max(t.hi, payload)
    if kind == MOD.type_kit then
        local blob = api.read(address + 24, math.min(payload, 65536))
        if blob then kit(address + 24, blob) end
    end
end

local function majority(k)
    local count = {}
    for _, body in ipairs(k.bodies) do
        for _, pc in ipairs(body.pieces) do
            if pc.type == 0 then count[pc.weight] = (count[pc.weight] or 0) + 1 end
        end
    end
    local best, n = nil, -1
    for w, c in pairs(count) do if c > n then best, n = w, c end end
    return best
end

-- after each scan round: kits-dump.txt (only when something new was found)
function R.finish()
    if #R.order == R.written then return end
    local path = forge_file('kits-dump.txt')
    if not path then return end
    local want = MOD.research and MOD.research.weight
    local kinds = { armor = 0, helmet = 0, cape = 0 }
    for _, rec in ipairs(R.order) do
        local t = R.kits[rec].type
        local name = t == 0 and 'armor' or t == 1 and 'helmet' or t == 2 and 'cape' or nil
        if name then kinds[name] = kinds[name] + 1 end
    end
    local L = {
        '# Armory Forge research dump: armor kits (HelldiverCustomizationKit) as found in memory.',
        '# Send this file to the mod author. Nothing here is personal.',
        'mod ' .. MOD.version .. ' research',
        'written ' .. os.date('!%Y-%m-%dT%H:%M:%SZ'),
        'experiment ' .. (want and ('every armor piece set to ' .. tostring(WEIGHT[want] or want)) or 'none (dump only)'),
        'kits ' .. #R.order .. ' (armor ' .. kinds.armor .. ', helmet ' .. kinds.helmet .. ', cape ' .. kinds.cape .. ')',
        'pieces changed ' .. R.changed .. ', failed ' .. R.failed,
        '',
        '# LDLD table types seen: type count min_bytes max_bytes',
    }
    local tl = {}
    for kind, t in pairs(R.types) do tl[#tl + 1] = { kind, t } end
    table.sort(tl, function(a, b) return a[2].n > b[2].n end)
    for _, e in ipairs(tl) do
        L[#L + 1] = string.format('type 0x%08X %d %d %d', e[1], e[2].n, e[2].lo, e[2].hi)
    end
    L[#L + 1] = ''
    for i, rec in ipairs(R.order) do
        local k = R.kits[rec]
        local m = majority(k)
        L[#L + 1] = string.format('kit 0x%08X type %d passive %d (%s) weight %s rarity %d dlc 0x%08X set 0x%08X archive 0x%016X at %s%s',
            k.id, k.type, k.passive, CAT[k.passive] and CAT[k.passive].name or '-', m and (WEIGHT[m] or m) or '-',
            k.rarity, k.dlc, k.set, k.archive, hex(rec), k.bad and (' BAD ' .. k.bad) or '')
        if i <= 3 then
            local hx = {}
            for j = 1, #k.head do hx[#hx + 1] = string.format('%02X', k.head:byte(j)) end
            L[#L + 1] = '  head ' .. table.concat(hx, ' ')
        end
        for b, body in ipairs(k.bodies) do
            L[#L + 1] = string.format('  body %d type %d pieces %d%s', b, body.type, #body.pieces, body.bad and ' BAD' or '')
            for _, pc in ipairs(body.pieces) do
                L[#L + 1] = string.format('    piece %-14s type %d weight %-6s path 0x%016X lut %s%s', SLOT[pc.slot] or tostring(pc.slot),
                    pc.type, WEIGHT[pc.weight] or tostring(pc.weight), pc.path, R.hex8(pc.lut), pc.now and (' -> ' .. WEIGHT[pc.now]) or '')
            end
        end
    end
    if write_file(path, table.concat(L, '\r\n') .. '\r\n') then
        R.written = #R.order
        log('research: wrote ' .. #R.order .. ' armor kits to ' .. path .. '; ' .. R.changed .. ' piece weight(s) changed')
    end
end

-- ================================================================ test A: which armor am I wearing?
-- F10 (after the scan is done): look through memory for places where an armor id, a helmet
-- id and a cape id sit close together, which is how a loadout would be stored. Change your
-- armor in the armory (EQUIP), press F10 again: the places that now hold the new armor id
-- are the loadout. Results: ArmoryForge\loadout-research.txt
local ffi_ = ffi
local LS = { history = {}, scans = 0 }
R.loadout = LS

local function kit_ids()
    local ids, bm = {}, ffi_.new('uint8_t[65536]')
    for _, rec in ipairs(R.order) do
        local k = R.kits[rec]
        if k.id and k.id ~= 0 and k.type and k.type <= 2 then
            ids[k.id] = k
            bm[k.id % 65536] = 1
        end
    end
    return ids, bm
end

local function kit_area()
    local lo, hi
    for _, rec in ipairs(R.order) do
        if not lo or rec < lo then lo = rec end
        if not hi or rec > hi then hi = rec end
    end
    return (lo or 0) - 0x10000, (hi or 0) + 0x10000
end

local function describe(k)
    if not k then return '?' end
    local kind = k.type == 0 and 'armor' or k.type == 1 and 'helmet' or 'cape'
    return string.format('%s 0x%08X%s', kind, k.id, (k.type == 0 and CAT[k.passive]) and (' (' .. CAT[k.passive].name .. ')') or '')
end

local function ls_start(now)
    if LS.busy then return end
    LS.ids, LS.bm = kit_ids()
    LS.lo, LS.hi = kit_area()
    -- what the places found last time hold now
    local moved = {}
    for _, c in ipairs(LS.last or {}) do
        local b = api.read(c.at, 4)
        local v = b and u32(b, 0)
        if v and v ~= c.armor then moved[#moved + 1] = { c = c, now = v } end
    end
    LS.moved = moved
    LS.regions, LS.idx, LS.cursor = api.regions(), 1, 0
    LS.cands, LS.ncand, LS.bytes = {}, 0, 0
    LS.busy, LS.t0 = true, now
    LS.ha, LS.hv, LS.hk = {}, {}, {}
    state.research_note = 'Loadout scan started (about a minute; keep the game open)'
    log('research: loadout scan ' .. (LS.scans + 1) .. ' started; ' .. #moved .. ' place(s) from the last scan changed')
end

local function ls_chunk(base, size)
    local p = api.read_into(base, size)
    if not p then return end
    local p32 = ffi_.cast('uint32_t *', p)
    local bm, ids = LS.bm, LS.ids
    local ha, hv, nh = LS.ha, LS.hv, 0
    for i = 0, math.floor(size / 4) - 1 do
        local v = p32[i]
        if bm[v % 65536] ~= 0 and ids[v] then
            nh = nh + 1
            ha[nh], hv[nh] = base + i * 4, v
        end
    end
    -- an armor id with a helmet id and a cape id within 256 bytes
    for j = 1, nh do
        local kj = ids[hv[j]]
        if kj.type == 0 and (ha[j] < LS.lo or ha[j] > LS.hi) then
            local helmet, cape
            for k = math.max(1, j - 64), math.min(nh, j + 64) do
                if math.abs(ha[k] - ha[j]) <= 256 then
                    local kk = ids[hv[k]]
                    if kk.type == 1 and not helmet then helmet = k end
                    if kk.type == 2 and not cape then cape = k end
                end
            end
            if helmet and cape and LS.ncand < 2000 then
                LS.ncand = LS.ncand + 1
                LS.cands[LS.ncand] = { at = ha[j], armor = hv[j], helmet = hv[helmet], cape = hv[cape],
                                       dh = ha[helmet] - ha[j], dc = ha[cape] - ha[j] }
            end
        end
    end
end

local function ls_finish(now)
    LS.busy = false
    LS.scans = LS.scans + 1
    local L = { string.format('scan %d at %s: %d place(s) with armor + helmet + cape ids close together (%.0f s, %.0f MB)',
        LS.scans, os.date('%H:%M:%S'), LS.ncand, now - LS.t0, LS.bytes / 1048576) }
    if LS.scans > 1 then
        L[#L + 1] = string.format('  places from scan %d that now hold a different id: %d', LS.scans - 1, #LS.moved)
        for i, m in ipairs(LS.moved) do
            if i > 60 then L[#L + 1] = '    ...'; break end
            L[#L + 1] = string.format('    CHANGED %s: %s -> %s', hex(m.c.at), describe(LS.ids[m.c.armor]),
                LS.ids[m.now] and describe(LS.ids[m.now]) or string.format('0x%08X', m.now))
        end
    end
    for i, c in ipairs(LS.cands) do
        if i > 200 then L[#L + 1] = '  ... ' .. (LS.ncand - 200) .. ' more'; break end
        L[#L + 1] = string.format('  at %s: %s | %s (%+d) | %s (%+d)', hex(c.at), describe(LS.ids[c.armor]),
            describe(LS.ids[c.helmet]), c.dh, describe(LS.ids[c.cape]), c.dc)
    end
    LS.history[#LS.history + 1] = table.concat(L, '\r\n')
    LS.last = LS.cands
    local path = forge_file('loadout-research.txt')
    write_file(path, '# Armory Forge research: where is the equipped armor stored?\r\n' ..
        '# Press F10, change your armor (EQUIP), press F10 again, then send this file.\r\n\r\n' ..
        table.concat(LS.history, '\r\n\r\n') .. '\r\n')
    state.research_note = 'Loadout scan ' .. LS.scans .. ' done: ' .. LS.ncand .. ' place(s)' ..
        (LS.scans > 1 and (', ' .. #LS.moved .. ' changed') or '. Now change armor and press F10 again')
    log('research: loadout scan ' .. LS.scans .. ' done, ' .. LS.ncand .. ' candidate(s), written to ' .. tostring(path))
end

local function ls_step(now)
    local deadline = api.now() + 0.004
    while LS.busy do
        local r = LS.regions[LS.idx]
        if not r then ls_finish(now); return end
        if LS.cursor >= r.size then
            LS.idx, LS.cursor = LS.idx + 1, 0
        else
            local take = math.min(1048576, r.size - LS.cursor)
            pcall(ls_chunk, r.base + LS.cursor, take)
            LS.bytes = LS.bytes + take
            LS.cursor = LS.cursor + take
        end
        if api.now() >= deadline then return end
    end
end

-- ================================================================ test B: another armor's colors
-- F11: every armor with the test passive (Siege-Ready unless set) takes the colour LUT
-- (MaterialLut, piece +24) of the next other armor; after the last one, its own again.
-- Look at it in the armory: does it change, and does it look right?
local LUT = { idx = 0 }
R.lut = LUT

local piece_lut

local function lut_kits()
    local target, sources = {}, {}
    local want = MOD.research and MOD.research.lut_passive or 16
    for _, rec in ipairs(R.order) do
        local k = R.kits[rec]
        if k.type == 0 and not k.bad then
            if k.passive == want then target[#target + 1] = k
            elseif piece_lut(k, 2, 1) then sources[#sources + 1] = k end
        end
    end
    return target, sources, want
end

piece_lut = function(k, slot, body_type)
    local first
    for _, body in ipairs(k.bodies) do
        for _, pc in ipairs(body.pieces) do
            if pc.lut and pc.lut ~= NO_LUT then
                if pc.slot == slot and body.type == body_type then return pc.lut end
                first = first or pc.lut
            end
        end
    end
    return first
end

local function lut_next()
    local target, sources, want = lut_kits()
    if #target == 0 or #sources == 0 then
        state.research_note = 'Colour test: no armor with passive ' .. tostring(want) .. ' found'
        return
    end
    LUT.idx = (LUT.idx + 1) % (#sources + 1)
    local src = LUT.idx > 0 and sources[LUT.idx] or nil
    local n, bad = 0, 0
    for _, k in ipairs(target) do
        for _, body in ipairs(k.bodies) do
            for _, pc in ipairs(body.pieces) do
                if pc.lut and pc.lut ~= NO_LUT then
                    local v = src and piece_lut(src, pc.slot, body.type) or pc.lut
                    if v and api.write(pc.at + 24, v) then n = n + 1 else bad = bad + 1 end
                end
            end
        end
    end
    local what = src and string.format('the colours of armor %d of %d (%s, kit 0x%08X)', LUT.idx, #sources,
        CAT[src.passive] and CAT[src.passive].name or 'no passive', src.id) or 'their own colours again'
    state.research_note = (CAT[want] and CAT[want].name or 'Test') .. ' armors now have ' .. what
    log('research: colour test: ' .. #target .. ' armor(s) -> ' .. what .. ' (' .. n .. ' pieces, ' .. bad .. ' failed)')
end

-- ================================================================ keys
pcall(ffi_.cdef, 'int16_t GetAsyncKeyState(int key);')
local okuser, user = pcall(ffi_.load, 'user32')
local was = {}
local function pressed(vk)
    if rawget(_G, 'PP_TEST_INPUT') then
        local down = PP_TEST_INPUT.key_down(vk)
        local edge = down and not was[vk]; was[vk] = down; return edge
    end
    if not okuser then return false end
    local ok, s = pcall(user.GetAsyncKeyState, vk)
    local down = ok and s < 0
    local edge = down and not was[vk]
    was[vk] = down
    return edge
end

function R.tick(now)
    if pressed(0x79) then pcall(ls_start, now) end              -- F10
    if pressed(0x7A) then                                       -- F11
        local ok, why = pcall(lut_next)
        if not ok then log('research: colour test: ' .. tostring(why)) end
    end
    if LS.busy then
        local ok, why = pcall(ls_step, now)
        if not ok then LS.busy = false; log('research: loadout scan failed: ' .. tostring(why)) end
    end
end

end
