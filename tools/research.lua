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
                    slot = u32(rp, 8), type = u32(rp, 12), weight = u32(rp, 16) }
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
                L[#L + 1] = string.format('    piece %-14s type %d weight %-6s path 0x%016X%s', SLOT[pc.slot] or tostring(pc.slot),
                    pc.type, WEIGHT[pc.weight] or tostring(pc.weight), pc.path, pc.now and (' -> ' .. WEIGHT[pc.now]) or '')
            end
        end
    end
    if write_file(path, table.concat(L, '\r\n') .. '\r\n') then
        R.written = #R.order
        log('research: wrote ' .. #R.order .. ' armor kits to ' .. path .. '; ' .. R.changed .. ' piece weight(s) changed')
    end
end

end
