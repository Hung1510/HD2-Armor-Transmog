-- ================================================================ in-game panel
-- The panel's drawing, input, cursor and font handling come from SHODAN Stat Editor
-- v1.4.1 by SHODAN (public domain / Unlicense, https://github.com/SHODAN-HORAI/SHODAN-Stat-Editor),
-- adapted for armor passives. Hotkey F7 by default (loadout.ini: [settings] hotkey = F7).
--
-- Layout: armor tabs across the top (one per stack) and a Presets tab; on the left every
-- passive with an on/off switch; on the right the chosen passive's values in plain units
-- (75% resist, +30%, +50 armor) with -- - + ++ and reset, or click a value to type it.
-- Every change applies at once and is saved to ArmoryForge\loadout.ini.
-- Quick-swap key (F9 by default) cycles presets without opening the panel.

-- The whole panel lives in one function: Lua allows 200 locals per function, and the
-- engine above uses most of the main chunk's. panel_tick / setup_panel are the way in.
local setup_panel
local function build_panel()

local sr, input = nil, nil
local VK = { Up = 0x26, Down = 0x28, Left = 0x25, Right = 0x27, PageUp = 0x21, PageDown = 0x22,
             Delete = 0x2E, Shift = 0x10, Enter = 0x0D, Backspace = 0x08, Escape = 0x1B, Ctrl = 0x11 }
for n = 1, 12 do VK['F' .. n] = 0x6F + n end
-- typing a value: digits, decimal point, sign
local DIGIT_KEYS = {}
for n = 0, 9 do DIGIT_KEYS[#DIGIT_KEYS + 1] = { 0x30 + n, tostring(n) }; DIGIT_KEYS[#DIGIT_KEYS + 1] = { 0x60 + n, tostring(n) } end
for _, k in ipairs({ { 0xBE, '.' }, { 0x6E, '.' }, { 0xBC, '.' }, { 0xBD, '-' }, { 0x6D, '-' },
                     { 0x6B, '+' }, { 0xBB, '+' } }) do DIGIT_KEYS[#DIGIT_KEYS + 1] = k end
-- typing a preset name: letters (Shift = capital), digits, space, - and _
local NAME_KEYS = {}
for c = 0x41, 0x5A do NAME_KEYS[#NAME_KEYS + 1] = { c, string.char(c + 32), string.char(c) } end
for n = 0, 9 do
    NAME_KEYS[#NAME_KEYS + 1] = { 0x30 + n, tostring(n), tostring(n) }
    NAME_KEYS[#NAME_KEYS + 1] = { 0x60 + n, tostring(n), tostring(n) }
end
for _, k in ipairs({ { 0x20, ' ', ' ' }, { 0xBD, '-', '_' }, { 0x6D, '-', '-' } }) do NAME_KEYS[#NAME_KEYS + 1] = k end

-- ---------------------------------------------------------------- windows input
local function build_input()
    for _, declaration in ipairs({
        'void *GetForegroundWindow(void);',
        'uint32_t GetWindowThreadProcessId(void*,void*);',
        'uint32_t GetCurrentProcessId(void);',
        'int GetCursorPos(void*);',
        'int ScreenToClient(void*,void*);',
        'int GetClientRect(void*,void*);',
        'int16_t GetAsyncKeyState(int key);',
        'int ShowCursor(int show);',
        'int ClipCursor(const void *rect);',
        'int GetClipCursor(void *rect);',
        'int OpenClipboard(void *owner);',
        'int CloseClipboard(void);',
        'int EmptyClipboard(void);',
        'void *SetClipboardData(uint32_t format, void *data);',
        'void *GetClipboardData(uint32_t format);',
        'void *GlobalAlloc(uint32_t flags, size_t bytes);',
        'void *GlobalLock(void *mem);',
        'int GlobalUnlock(void *mem);',
    }) do pcall(ffi.cdef, declaration) end
    local user = ffi.load('user32')
    local kernel = ffi.load('kernel32')
    local own_pid = kernel.GetCurrentProcessId()
    local point, rect, pid = ffi.new('int32_t[2]'), ffi.new('int32_t[4]'), ffi.new('uint32_t[1]')
    local self = {}
    function self.window()
        local window = user.GetForegroundWindow()
        if window == nil then return nil end
        if user.GetWindowThreadProcessId(window, ffi.cast('void *', pid)) == 0 or pid[0] ~= own_pid then return nil end
        return window
    end
    function self.focused() return self.window() ~= nil end
    function self.key_down(vk) return user.GetAsyncKeyState(vk) < 0 end
    -- cursor in client pixels from the top left, and the client size
    function self.cursor()
        local window = self.window()
        if not window then return nil end
        if user.GetCursorPos(ffi.cast('void *', point)) == 0
           or user.ScreenToClient(window, ffi.cast('void *', point)) == 0
           or user.GetClientRect(window, ffi.cast('void *', rect)) == 0 then return nil end
        return point[0], point[1], rect[2] - rect[0], rect[3] - rect[1]
    end
    function self.show_cursor(show) return user.ShowCursor(show and 1 or 0) end
    function self.get_clip()
        local r = ffi.new('int32_t[4]')
        if user.GetClipCursor(ffi.cast('void *', r)) == 0 then return nil end
        return r
    end
    function self.set_clip(r) user.ClipCursor(r and ffi.cast('const void *', r) or nil) end
    -- Windows clipboard, plain text (share codes are ASCII)
    function self.set_clipboard(text)
        if user.OpenClipboard(nil) == 0 then return false end
        local ok = false
        user.EmptyClipboard()
        local h = kernel.GlobalAlloc(0x0002, #text + 1)          -- GMEM_MOVEABLE
        if h ~= nil then
            local p = kernel.GlobalLock(h)
            if p ~= nil then
                ffi.copy(p, text)                                 -- copies the terminating 0 too
                kernel.GlobalUnlock(h)
                ok = user.SetClipboardData(1, h) ~= nil           -- CF_TEXT
            end
        end
        user.CloseClipboard()
        return ok
    end
    function self.get_clipboard()
        if user.OpenClipboard(nil) == 0 then return nil end
        local text = nil
        local h = user.GetClipboardData(1)
        if h ~= nil then
            local p = kernel.GlobalLock(h)
            if p ~= nil then
                text = ffi.string(p)
                kernel.GlobalUnlock(h)
            end
        end
        user.CloseClipboard()
        return text
    end
    return self
end

-- ---------------------------------------------------------------- state
local ui = { open = false, tab = 1, sel = nil, hover = nil, gui = nil, world = nil, signature = nil,
             regions = {}, version = 0, errors = 0, value = nil, adding = false, message = nil,
             confirm = nil, presets = false, psel = nil, naming = nil, history = {}, last_text = nil,
             swap_at = 0 }
local W, H = 1000, 990
local font = nil
local held, mouse_was_down, armed = {}, nil, nil
local keys_was = {}          -- hotkeys: pressed this frame but not last
local toast = { text = nil, sub = nil, till = 0, gui = nil, world = nil }
-- presets, share codes and units live in one table to keep the chunk's local count low
local PP = { user = nil }

local function hotkey() return (LOADOUT and LOADOUT.hotkey) or MOD.hotkey or 'F7' end
local function swap_key() return (LOADOUT and LOADOUT.swap_hotkey) or MOD.swap_hotkey or 'F9' end
local function now_s() return api.now() end

local function say(text, seconds)
    ui.message = { text = text, till = now_s() + (seconds or 3) }
    ui.version = ui.version + 1
end

local function current()
    if not LOADOUT then return nil end
    local p = LOADOUT.profiles[ui.tab]
    if not p and #LOADOUT.profiles > 0 then ui.tab = 1; p = LOADOUT.profiles[1] end
    return p
end

local function value_of(p, pid, e)
    local v = p.tweaks[pid .. '.' .. e.key]
    if v == nil then return e.def end
    return v
end

-- raw value limits (what the game gets)
local function limits(e)
    if e.type == 2 then return 0, 20 end
    if e.type == 3 then return 0, 600 end
    return -1000, 1000
end

local function fmt(v)
    if v == nil then return '?' end
    if math.abs(v - math.floor(v + 0.5)) < 1e-6 then return tostring(math.floor(v + 0.5)) end
    if math.abs(v) < 1 then return (string.format('%.3f', v):gsub('0+$', '')) end
    return (string.format('%.2f', v):gsub('0+$', ''):gsub('%.$', ''))
end

local function label_of(e)
    local s = e.key:gsub('^stat_', ''):gsub('_', ' ')
    s = s:sub(1, 1):upper() .. s:sub(2)
    if e.kind == 'stat' then s = s .. ' (weapon stat)' end
    return s
end

-- ---------------------------------------------------------------- plain-language units
-- The game stores multipliers (x0.25), additions (+1.0 armor = +50) and seconds. The
-- panel shows and edits what they mean: 75% resist, +30%, +50 armor, +2, 2 s.
function PP.unit(e)
    if e.kind == 'stat' then return 'pct' end
    if e.type == 2 then return e.key:find('_damage_taken$') and 'resist' or 'pct' end
    if e.type == 1 then return e.key == 'armor_rating' and 'armor' or 'count' end
    if e.type == 3 then return 'time' end
    return 'set'
end
function PP.to_friendly(u, v)
    if u == 'resist' then return (1 - v) * 100 end
    if u == 'pct' then return (v - 1) * 100 end
    if u == 'armor' then return v * 50 end
    return v
end
function PP.from_friendly(u, f)
    if u == 'resist' then return 1 - f / 100 end
    if u == 'pct' then return 1 + f / 100 end
    if u == 'armor' then return f / 50 end
    return f
end
function PP.steps(u)
    if u == 'time' then return 0.5, 2 end
    if u == 'set' then return 1, 1 end
    if u == 'count' then return 1, 5 end
    return 5, 25                     -- percent and armor points
end
local function round1(x) return math.floor(x * 10 + 0.5) / 10 end
-- the value as shown in the box
function PP.text(e, v)
    local u = PP.unit(e)
    local f = round1(PP.to_friendly(u, v))
    local sign = f >= 0 and '+' or ''
    if u == 'resist' then return fmt(f) .. '%' end
    if u == 'pct' then return sign .. fmt(f) .. '%' end
    if u == 'armor' or u == 'count' then return sign .. fmt(f) end
    if u == 'time' then return fmt(f) .. ' s' end
    return fmt(f)
end
-- what the number means, under the label
PP.WHAT = { resist = 'damage resist (100% = none taken)', pct = 'change from normal',
            armor = 'armor rating', count = 'extra', time = 'seconds', set = 'value (flag)' }
function PP.raw_text(e, v)
    if e.type == 2 or e.kind == 'stat' then return 'x' .. fmt(v) end
    if e.type == 1 then return (v >= 0 and '+' or '') .. fmt(v) end
    if e.type == 3 then return fmt(v) .. ' s' end
    return '= ' .. fmt(v)
end

-- ---------------------------------------------------------------- changes and undo
-- Every change goes through changed(): the loadout as it was is pushed on the undo list,
-- the game is updated, and the file is saved a moment later.
local function snapshot() return serialize(LOADOUT, nil) end

local function changed(perk, text)
    local now_text = snapshot()
    if ui.last_text and ui.last_text ~= now_text then
        ui.history[#ui.history + 1] = ui.last_text
        if #ui.history > 30 then table.remove(ui.history, 1) end
    end
    ui.last_text = now_text
    ui.version = ui.version + 1
    loadout_changed(perk and { perk } or nil)
    if text then say(text) end
end

-- Swap in a whole loadout (preset, share code, undo). The player's own keys and
-- retire setting stay unless `exact` (undo).
function PP.replace(l, text, exact)
    if not exact and LOADOUT then
        l.hotkey, l.swap_hotkey, l.retire = LOADOUT.hotkey, LOADOUT.swap_hotkey, LOADOUT.retire
    end
    l.name = l.name or (LOADOUT and LOADOUT.name) or MOD.title
    l.hotkey, l.swap_hotkey = l.hotkey or MOD.hotkey or 'F7', l.swap_hotkey or MOD.swap_hotkey or 'F9'
    if l.retire == nil then l.retire = MOD.retire end
    LOADOUT = l
    ui.tab, ui.sel, ui.value, ui.adding = 1, nil, nil, false
    changed(nil, text)
end

function PP.undo()
    local prev = table.remove(ui.history)
    if not prev then say('Nothing to undo'); return end
    local ok, l = pcall(parse_loadout, prev)
    if not ok or not l then say('Could not undo'); return end
    ui.last_text = nil                      -- an undo is not itself undoable
    PP.replace(l, 'Undone (' .. #ui.history .. ' more)', true)
end

local function set_value(p, pid, e, v)
    local lo, hi = limits(e)
    v = math.max(lo, math.min(hi, math.floor(v * 10000 + 0.5) / 10000))
    local key = pid .. '.' .. e.key
    if v == e.def then p.tweaks[key] = nil else p.tweaks[key] = v end
    changed(p.perk)
end

local function toggle(p, pid)
    if pid == p.perk then return end
    if p.enabled[pid] then p.enabled[pid] = nil else p.enabled[pid] = true end
    ui.sel = pid
    changed(p.perk)
end

local function finish_value(keep)
    local v = ui.value
    ui.value = nil
    ui.version = ui.version + 1
    if not keep or not v then return end
    local n = tonumber((v.text:gsub(',', '.'):gsub('^%+', '')))
    local p = current()
    if not n or not p then say('Not a number: ' .. v.text); return end
    local c = CAT[v.pid]
    local e = c and c.effects[v.n]
    if e then set_value(p, v.pid, e, PP.from_friendly(PP.unit(e), n)) end
end

-- ---------------------------------------------------------------- share codes
-- A code is the web builder's share link: the loadout as base64url after #ini=. It opens
-- in the web builder, and Paste code reads it (or the bare code, or plain loadout text).
PP.SITE = 'https://hung1510.github.io/Super-Earth-Armory-Forge/#ini='
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'

function PP.b64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local d = { math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64 }
        local keep = c and 4 or b and 3 or 2
        for k = 1, keep do out[#out + 1] = B64:sub(d[k] + 1, d[k] + 1) end
    end
    return table.concat(out)
end

function PP.unb64(s)
    local map = {}
    for i = 1, 64 do map[B64:byte(i)] = i - 1 end
    map[43], map[47] = 62, 63                         -- '+' '/' (standard alphabet) too
    s = s:gsub('[=%s]', '')
    local out = {}
    for i = 1, #s, 4 do
        local chunk = s:sub(i, i + 3)
        if #chunk == 1 then return nil end
        local n = 0
        for j = 1, 4 do
            local v = 0
            if j <= #chunk then
                v = map[chunk:byte(j)]
                if not v then return nil end
            end
            n = n * 64 + v
        end
        local bytes = { math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256 }
        for k = 1, #chunk - 1 do out[#out + 1] = string.char(bytes[k]) end
    end
    return table.concat(out)
end

function PP.copy_code()
    local code = PP.SITE .. PP.b64(snapshot())
    local ok = input.set_clipboard and input.set_clipboard(code)
    say(ok and 'Share code copied: paste it in the web builder, or a friend\'s panel' or 'Could not use the clipboard', 4)
    return code
end

function PP.paste_code()
    local clip = input.get_clipboard and input.get_clipboard()
    if not clip or clip == '' then say('The clipboard is empty'); return end
    local text
    if clip:find('%[[Pp]rofile') then
        text = clip
    else
        local code = clip:match('#ini=([%w%-_]+)') or clip:match('^%s*([%w%-_]+)%s*$')
        text = code and PP.unb64(code)
    end
    local ok, l = pcall(parse_loadout, text or '')
    if not text or not ok or not l or #l.profiles == 0 then
        say('No Armory Forge code on the clipboard', 4)
        return
    end
    PP.replace(l, 'Loaded the pasted code: ' .. tostring(l.name or 'loadout'))
end

-- ---------------------------------------------------------------- presets
-- Built-in presets come with the build (MOD.presets); the player's own are kept in
-- ArmoryForge\my-presets.txt as blocks of loadout text.
function PP.user_path() return forge_file('my-presets.txt') end

function PP.load_user()
    PP.user = {}
    local text = read_saved('my-presets.txt')
    if not text then return end
    local name, lines = nil, nil
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
        line = line:gsub('\r$', '')
        local n = line:match('^### preset: (.+)$')
        if n then name, lines = n, {}
        elseif line == '### end' and name then
            PP.user[#PP.user + 1] = { name = name, text = table.concat(lines, '\n') .. '\n' }
            name, lines = nil, nil
        elseif lines then lines[#lines + 1] = line end
    end
end

function PP.save_user()
    local path = PP.user_path()
    if not path then return false end
    local L = { '; Super Earth Armory Forge: your presets, saved by the in-game panel.', '' }
    for _, p in ipairs(PP.user) do
        L[#L + 1] = '### preset: ' .. p.name
        L[#L + 1] = (p.text:gsub('\r', ''):gsub('\n+$', ''))
        L[#L + 1] = '### end'
        L[#L + 1] = ''
    end
    return write_file(path, table.concat(L, '\r\n'))
end

-- the list shown in the Presets tab: { kind = 'installed' | 'builtin' | 'user', i, name }
function PP.entries()
    if not PP.user then PP.load_user() end
    -- a blank install has nothing to go back to, so no Installed build entry
    local list = MOD.blank and {} or { { kind = 'installed', i = 0, name = 'Installed build' } }
    for i, p in ipairs(MOD.presets or {}) do list[#list + 1] = { kind = 'builtin', i = i, name = p.name } end
    for i, p in ipairs(PP.user) do list[#list + 1] = { kind = 'user', i = i, name = p.name } end
    return list
end

function PP.loadout_of(entry)
    if entry.kind == 'installed' then return default_loadout() end
    local src = entry.kind == 'builtin' and (MOD.presets or {})[entry.i] or PP.user[entry.i]
    if not src then return nil end
    local ok, l = pcall(parse_loadout, src.text)
    if ok and l and #l.profiles > 0 then
        l.name = entry.kind == 'user' and src.name or l.name or src.name
        return l
    end
    return nil
end

function PP.load(entry)
    local l = PP.loadout_of(entry)
    if not l then say('That preset could not be read'); return end
    PP.replace(l, 'Loaded ' .. entry.name)
end

-- quick-swap cycles your own presets, or the built-in ones when you have none
function PP.cycle_list()
    if not PP.user then PP.load_user() end
    local list = {}
    if #PP.user > 0 then
        for i, p in ipairs(PP.user) do list[#list + 1] = { kind = 'user', i = i, name = p.name } end
    else
        for i, p in ipairs(MOD.presets or {}) do list[#list + 1] = { kind = 'builtin', i = i, name = p.name } end
    end
    return list
end

function PP.swap()
    local list = PP.cycle_list()
    if #list == 0 then return end
    ui.swap_index = (ui.swap_index or 0) % #list + 1
    local entry = list[ui.swap_index]
    PP.load(entry)
    toast.text, toast.sub = entry.name, (#PP.user > 0 and 'your preset ' or 'preset ') .. ui.swap_index .. ' of ' .. #list
    toast.till = now_s() + 2.2
    if toast.gui then pcall(sr.World.destroy_gui, toast.world, toast.gui) end
    toast.gui, toast.world = nil, nil
end

function PP.summary(l)
    local out = {}
    for _, p in ipairs(l and l.profiles or {}) do
        local names = {}
        for _, c in ipairs(CAT_LIST) do if p.enabled[c.id] and c.id ~= p.perk then names[#names + 1] = c.name end end
        local tweaks = 0
        for _ in pairs(p.tweaks) do tweaks = tweaks + 1 end
        out[#out + 1] = { armor = CAT[p.perk].name, names = names, tweaks = tweaks, policy = p.conflicts }
    end
    return out
end

function PP.clean_name(s)
    s = (s or ''):gsub('[#\r\n]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return s ~= '' and s:sub(1, 28) or nil
end

-- ---------------------------------------------------------------- font (from SHODAN v1.4.1)
local GAME_STAMP, FONT_RVA, ATLAS_RVA, MATERIAL_RVA = 0x6AB3B43F, 0x3772268, 0x3772EE8, 0x37C5478
local DEBUG_FONT = 'core/performance_hud/debug'

local function resource_hex(bytes)
    if not bytes or #bytes ~= 8 or bytes == string.rep('\0', 8) then return nil end
    return string.format('%08x%08x', u32(bytes, 4), u32(bytes, 0))
end

local function read_font_ids()
    local base = api.module_base and api.module_base('game.dll')
    if not base then return nil, 'game.dll not found' end
    local dos = api.read(base, 64)
    local pe = dos and u32(dos, 60)
    local head = pe and api.read(base + pe, 16)
    if not head or head:sub(1, 4) ~= 'PE\0\0' or u32(head, 8) ~= GAME_STAMP then return nil, 'game.dll is another build' end
    local font_id = resource_hex(api.read(base + FONT_RVA, 8))
    local atlas_id = resource_hex(api.read(base + ATLAS_RVA, 8))
    local owner = api.read(base + MATERIAL_RVA, 8)
    local owner_at = owner and (u32(owner, 0) + u32(owner, 4) * 4294967296)
    local material_id = owner_at and owner_at ~= 0 and resource_hex(api.read(owner_at + 24, 8))
    if not (font_id and atlas_id and material_id) then return nil, 'font ids not set yet' end
    return { font = font_id, material = material_id, atlas = atlas_id }
end

local function loaded(kind, name)
    local can_get = sr.Application and rawget(sr.Application, 'can_get')
    if type(can_get) ~= 'function' then return nil end
    local ok, value = pcall(function()
        return can_get(kind, name:match('^%x+$') and #name == 16 and sr.IdString64.from_hex(name) or name)
    end)
    if not ok then return nil end
    return value == true
end

local function choose_font(gui)
    local ok, ids, why = pcall(read_font_ids)
    if not ok then ids, why = nil, tostring(ids) end
    if ids then
        local f, m, t = loaded('font', ids.font), loaded('material', ids.material), loaded('texture', ids.atlas)
        if f and m and t then
            local ink = sr.Gui.material(gui, sr.IdString64.from_hex(ids.material))
            if ink then
                sr.Material.set_texture(ink, sr.IdString64.from_hex('88bac99b00000000'), sr.IdString64.from_hex(ids.atlas))
                return { font = sr.IdString64.from_hex(ids.font), material = sr.IdString64.from_hex(ids.material),
                         text = 'game UI font ' .. ids.font }
            end
            why = 'no font material instance'
        else
            why = string.format('game UI font not loaded (font %s, material %s, texture %s)', tostring(f), tostring(m), tostring(t))
        end
    end
    if loaded('font', DEBUG_FONT) and loaded('material', DEBUG_FONT) then
        return { font = DEBUG_FONT, material = DEBUG_FONT, text = 'debug font (' .. tostring(why) .. ')' }
    end
    return { text = 'no text: ' .. tostring(why) .. '; debug font not loaded either' }
end

local function clear_gui()
    if ui.gui and ui.world then
        for _, w in ipairs(sr.Application.worlds() or {}) do
            if w == ui.world then pcall(sr.World.destroy_gui, ui.world, ui.gui) break end
        end
    end
    ui.gui, ui.world, ui.signature, ui.regions = nil, nil, nil, {}
end


-- ---------------------------------------------------------------- draw
-- The same look as the web builder and the game's own Armory screen: near-black panels,
-- Helldivers yellow (#FFE710) for what is on, boxed tabs with a hatched stripe under the
-- active one, uppercase passive names, a key-prompt bar at the bottom. Buttons are sized
-- from their label's measured width, so text never runs out of them. Coordinates are
-- panel units from the top left; the gui counts pixels from the bottom left. ASCII only:
-- the game's font may not have other glyphs.
local function draw(width, height)
    local Gui, Vector3, Vector2, Color = sr.Gui, sr.Vector3, sr.Vector2, sr.Color
    local s = height / 1080 * 0.8
    local ox, oy = 30 * s, (height - H * s) / 2     -- left edge: SHODAN Stat Editor uses the right
    local gui = ui.gui
    local regions = {}
    local ink_font, ink_material = font.font, font.material
    local up = string.upper

    local function color(r, g, b, a) return Color(a or 255, r, g, b) end
    local function vx(v)
        for _, get in ipairs({ function() return Vector2.x(v) end, function() return Vector3.x(v) end,
                               function() return v[1] end }) do
            local ok, x = pcall(get)
            if ok and type(x) == 'number' then return x end
        end
        return nil
    end
    local C = {
        BG = color(11, 12, 13, 246), PANEL = color(18, 19, 21), ROW = color(26, 28, 31), ROW_HI = color(34, 36, 40),
        FIELD = color(10, 11, 12), LINE = color(44, 46, 50), LINE2 = color(62, 65, 70),
        TEXT = color(233, 230, 220), MUTED = color(143, 146, 150), DIM = color(93, 97, 102),
        YELLOW = color(255, 231, 16), YELLOW_DK = color(150, 136, 10), INK = color(18, 17, 4),
        SOFT = color(255, 231, 16, 26), BLUE = color(65, 99, 156), GOOD = color(92, 201, 170), BAD = color(255, 107, 91),
    }

    local function rect(x, y, w, h, c, z)
        Gui.rect(gui, Vector3(ox + x * s, height - oy - (y + h) * s, z or 951), Vector2(w * s, h * s), c)
    end
    -- width of a text in panel units: measured when the engine can, else a safe estimate
    local function measure(value, size)
        local ok, lo, hi = pcall(Gui.text_extents, gui, value, ink_font, size * s)
        if ok and lo and hi then
            local a, b = vx(lo), vx(hi)
            if a and b and b > a then return (b - a) / s end
        end
        -- estimate per character, on the wide side (a wide font like DejaVu Sans)
        local w = 0
        for ch in value:gmatch('.') do
            w = w + (ch:find('[%%@MWmw]') and 0.98 or ch:find('[%u+=<>#&]') and 0.8 or ch:find('%d') and 0.66
                     or ch:find('[%s%.,:;!|il\'%-%(%)%[%]]') and 0.36 or 0.62)
        end
        return w * size
    end
    -- limit: shrink to fit that width; align: 'right' or 'center' around x
    local function text(value, x, y, size, c, limit, align)
        if value == nil or value == '' or not ink_font then return 0 end
        local w = measure(value, size)
        if limit and w > limit then size = size * limit / w; w = limit end
        local px = x
        if align == 'right' then px = x - w elseif align == 'center' then px = x - w / 2 end
        local sz = size * s
        Gui.text(gui, value, ink_font, sz, ink_material, Vector3(ox + px * s, height - oy - y * s - sz * 0.8, 954), c or C.TEXT)
        return w
    end
    local function border(x, y, w, h, c, z)
        rect(x, y, w, 1, c, z or 952); rect(x, y + h - 1, w, 1, c, z or 952)
        rect(x, y, 1, h, c, z or 952); rect(x + w - 1, y, 1, h, c, z or 952)
    end
    local function region(key, x, y, w, h, enabled)
        regions[#regions + 1] = { key = key, x = ox + x * s, y = height - oy - (y + h) * s, w = w * s, h = h * s,
                                  enabled = enabled ~= false }
    end
    local function label(value, x, y, c, limit) return text(up(value), x, y, 11, c or C.YELLOW, limit) end
    -- a button; w = nil sizes it to its label. Returns its width.
    local function button(key, caption, x, y, w, h, enabled, filled, ink)
        caption = up(caption)
        local size = 13
        w = w or (measure(caption, size) + 28)
        local hovered = ui.hover == key and enabled ~= false
        if filled then
            rect(x, y, w, h, enabled == false and C.YELLOW_DK or C.YELLOW, 951)
            if hovered then border(x, y, w, h, C.TEXT, 953) end
        else
            rect(x, y, w, h, hovered and C.ROW_HI or C.PANEL, 951)
            border(x, y, w, h, enabled == false and C.LINE or hovered and C.TEXT or C.LINE2)
        end
        local c = enabled == false and C.DIM or filled and C.INK or ink or C.TEXT
        text(caption, x + w / 2, y + (h - size) / 2, size, c, w - 14, 'center')
        region(key, x, y, w, h, enabled)
        return w
    end
    local function keycap(k, x, y)
        local w = math.max(26, measure(k, 12) + 14)
        border(x, y, w, 22, C.TEXT, 953)
        text(k, x + w / 2, y + 5, 12, C.TEXT, w - 6, 'center')
        return w
    end
    local function checkbox(key, x, y, on, enabled)
        local hovered = ui.hover == key
        border(x, y, 16, 16, on and C.YELLOW or hovered and C.YELLOW or C.MUTED, 952)
        if on then rect(x + 4, y + 4, 8, 8, C.YELLOW, 953) end
        region(key, x - 5, y - 4, 26, 24, enabled)
    end
    -- the game's hatched stripe, as short diagonal steps
    local function hatch(x, y, w, c)
        local k = 0
        while k * 7 + 6 <= w do
            for j = 0, 2 do rect(x + k * 7 + j * 1.5, y + 4 - j * 2, 2.5, 2, c, 953) end
            k = k + 1
        end
    end
    local function tab(key, caption, x, active, ink, n)
        caption = up(caption)
        local w = math.min(230, measure(caption, 15) + (n and 44 or 30))
        rect(x, 0 + 108, w, 40, active and C.PANEL or C.BG, 951)
        border(x, 108, w, 40, active and C.TEXT or (ui.hover == key and C.MUTED or C.LINE2), 952)
        text(caption, x + 12, 116, 15, active and C.TEXT or (ui.hover == key and C.TEXT or ink or C.MUTED), w - (n and 36 or 20))
        if n then text(tostring(n), x + w - 8, 134, 11, C.DIM, nil, 'right') end
        if active then hatch(x + 10, 136, w - (n and 34 or 20), C.TEXT) end
        region(key, x, 108, w, 40)
        return w
    end

    -- frame, top strip, title
    rect(0, 0, W, H, C.BG, 950)
    border(0, 0, W, H, C.LINE, 955)
    rect(0, 0, W, 3, C.YELLOW, 952)
    region('panel', 0, 0, W, H, false)
    local mx = text('MINISTRY OF DEFENSE', 22, 12, 11, C.MUTED)
    text('SUPER EARTH ARMORY FORGE', 22 + mx + 12, 12, 11, C.TEXT)
    text('V' .. tostring(MOD.version), W - 22, 12, 11, C.DIM, nil, 'right')
    rect(0, 32, W, 1, C.LINE, 951)
    -- emblem box: the shield from the mod icon
    border(22, 44, 50, 50, C.TEXT, 952)
    rect(33, 54, 28, 20, C.YELLOW, 952); rect(36, 74, 22, 4, C.YELLOW, 952)
    rect(40, 78, 14, 4, C.YELLOW, 952); rect(44, 82, 6, 3, C.YELLOW, 952)
    rect(38, 59, 18, 4, C.INK, 953); rect(42, 63, 10, 4, C.INK, 953)
    local tw = text('ARMORY', 86, 50, 34, C.TEXT)
    text('FORGE', 86 + tw + 12, 50, 34, C.YELLOW)
    text('Tick passives, change values: it all applies at once.', 88, 84, 12, C.MUTED, 420)

    local by0 = H - 40                           -- key-prompt bar
    local function prompts()
        rect(0, by0, W, 40, color(6, 7, 8, 250), 951)
        rect(0, by0, W, 1, C.LINE, 952)
        local x = 22
        for _, p in ipairs({ { hotkey(), 'Close' }, swap_key() ~= 'OFF' and { swap_key(), 'Swap loadout' } or false,
                             { 'CTRL+Z', 'Undo' } }) do
            if p then
                x = x + keycap(p[1], x, by0 + 9) + 8
                x = x + text(up(p[2]), x, by0 + 13, 12, C.TEXT) + 22
            end
        end
        if ui.message then
            local mw = math.min(W - x - 30, measure(ui.message.text, 13) + 26)
            rect(W - 16 - mw, by0 + 7, mw, 26, C.SOFT, 952)
            rect(W - 16 - mw, by0 + 7, 3, 26, C.YELLOW, 953)
            text(ui.message.text, W - 16 - mw + 13, by0 + 13, 13, C.YELLOW, mw - 20)
        else
            text('SOLO / PRIVATE LOBBIES ONLY', W - 22, by0 + 14, 11, C.DIM, nil, 'right')
        end
    end

    if state.phase ~= 'ready' then
        label('Scanning armory records', 22, 124)
        text('Reading the game\'s armor passives... (' .. perks_found .. ' of ' .. #CAT_LIST .. ' found)', 22, 146, 18, C.TEXT, W - 44)
        text('Load into your ship or a mission if this does not finish.', 22, 176, 14, C.MUTED, W - 44)
        prompts()
        return regions
    end

    -- tabs: one per armor stack, + Armor, Presets
    local p = current()
    local x = 22
    for n, prof in ipairs(LOADOUT.profiles) do
        x = x + tab('tab:' .. n, CAT[prof.perk].name, x, n == ui.tab and not ui.adding and not ui.presets, nil, n) + 6
        if x > W - 420 then break end
    end
    x = x + tab('add', '+ Armor', x, ui.adding, C.YELLOW) + 6
    tab('presets', 'Presets', x, ui.presets, C.YELLOW)
    if p and not ui.adding and not ui.presets then
        local sure = ui.confirm and ui.confirm.kind == 'remove'
        local cap = sure and 'CLICK AGAIN TO REMOVE' or 'REMOVE THIS STACK'
        local rw = measure(cap, 11)
        text(cap, W - 22, 126, 11, (sure or ui.hover == 'remove') and C.BAD or C.DIM, nil, 'right')
        region('remove', W - 22 - rw - 6, 114, rw + 12, 28)
    end

    -- two panels
    local LX, LW, TOP = 22, 330, 158
    local X0 = LX + LW + 14
    local RW = W - 22 - X0
    local BOT = by0 - 10
    rect(LX, TOP, LW, BOT - TOP, C.PANEL, 950); border(LX, TOP, LW, BOT - TOP, C.LINE, 951)
    rect(X0, TOP, RW, BOT - TOP, C.PANEL, 950); border(X0, TOP, RW, BOT - TOP, C.LINE, 951)
    local IX, IW = LX + 14, LW - 28                  -- left inner
    local RX, RIW = X0 + 16, RW - 32                 -- right inner
    local RH = 23

    local function head(x, y, lab, title, limit)
        label(lab, x, y)
        text(up(title), x, y + 16, 21, C.TEXT, limit)
    end
    local function list_row(key, y, name, chosen, name_c)
        if chosen then rect(LX + 1, y, LW - 2, RH - 1, C.ROW_HI, 951); rect(LX + 1, y, 3, RH - 1, C.YELLOW, 952)
        elseif ui.hover == key then rect(LX + 1, y, LW - 2, RH - 1, C.ROW, 951) end
        text(name, IX + 4, y + 5, 14, name_c or (chosen and C.TEXT or C.MUTED), IW - 12)
        region(key, LX + 1, y, LW - 2, RH - 1)
    end

    -- ============================================================ Presets tab
    if ui.presets then
        local list = PP.entries()
        head(IX, TOP + 14, 'Loadouts', 'Presets', IW)
        local y = TOP + 64
        label('Standard issue', IX, y); y = y + 18
        for _, e in ipairs(list) do
            if e.kind ~= 'user' then
                list_row('pre:' .. e.kind .. ':' .. e.i, y, e.name, ui.psel and ui.psel.kind == e.kind and ui.psel.i == e.i)
                y = y + RH
            end
        end
        y = y + 12
        label('Your loadouts', IX, y)
        text(#PP.user .. ' SAVED', IX + IW, y, 11, #PP.user > 0 and C.YELLOW or C.DIM, nil, 'right')
        y = y + 18
        for _, e in ipairs(list) do
            if e.kind == 'user' then
                local key = 'pre:user:' .. e.i
                local chosen = ui.psel and ui.psel.kind == 'user' and ui.psel.i == e.i
                if ui.naming and ui.naming.i == e.i then
                    list_row(key, y, ui.naming.text .. '_', chosen, ui.naming.fresh and C.MUTED or C.YELLOW)
                else
                    list_row(key, y, e.name, chosen)
                end
                y = y + RH
            end
        end
        if #PP.user == 0 then text('None yet. Save the current stack.', IX + 4, y + 4, 13, C.DIM, IW - 8); y = y + 26 end
        button('psave', '+ Save current stack', IX, y + 10, IW, 32, true, true)

        local entry = nil
        for _, e in ipairs(list) do if ui.psel and e.kind == ui.psel.kind and e.i == ui.psel.i then entry = e end end
        if not entry then
            head(RX, TOP + 14, 'Loadouts', 'Choose a preset', RIW)
            text('Pick one on the left to see what it stacks, then load it.', RX, TOP + 70, 14, C.MUTED, RIW)
            text('Save your own with "+ Save current stack".', RX, TOP + 92, 14, C.MUTED, RIW)
            if swap_key() ~= 'OFF' then
                text(swap_key() .. ' in game cycles your loadouts (or the standard ones).', RX, TOP + 114, 14, C.MUTED, RIW)
            end
        else
            local l = PP.loadout_of(entry)
            head(RX, TOP + 14, entry.kind == 'installed' and 'Installed build' or entry.kind == 'builtin' and 'Standard issue' or 'Your loadout',
                 entry.name, RIW)
            local y2 = TOP + 66
            for _, sm in ipairs(PP.summary(l)) do
                rect(RX, y2, RIW, 1, C.LINE, 951)
                text(up(sm.armor .. ' armor'), RX, y2 + 10, 14, C.YELLOW, RIW)
                text(#sm.names .. ' passive(s), ' .. sm.tweaks .. ' value(s) changed, ' ..
                     (sm.policy == 'strongest' and 'strongest only' or 'stack all'), RX, y2 + 30, 13, C.MUTED, RIW)
                y2 = y2 + 52
                local line = ''
                for i, nm in ipairs(sm.names) do
                    local add = (line == '' and '' or ', ') .. nm
                    if measure(line .. add, 13) > RIW - 10 then
                        text(line .. ',', RX + 8, y2, 13, C.DIM, RIW - 10); y2 = y2 + 18; line = nm
                    else line = line .. add end
                    if i == #sm.names then text(line, RX + 8, y2, 13, C.DIM, RIW - 10); y2 = y2 + 18 end
                end
                y2 = y2 + 12
                if y2 > BOT - 150 then break end
            end
            local by = BOT - 96
            rect(RX, by - 12, RIW, 1, C.LINE, 951)
            local bx = RX
            bx = bx + button('pload', 'Load this preset', bx, by, nil, 34, l ~= nil, true) + 8
            if entry.kind == 'user' then
                local sure = ui.confirm and ui.confirm.kind
                bx = bx + button('pover', sure == 'pover' and 'Click again' or 'Save current here', bx, by, nil, 34, true) + 8
                bx = bx + button('pren', 'Rename', bx, by, nil, 34, true) + 8
                button('pdel', sure == 'pdel' and 'Click again' or 'Delete', bx, by, nil, 34, true, false, sure == 'pdel' and C.BAD or nil)
            end
            if ui.naming then text('Type a name, Enter to keep it, Esc to cancel.', RX, by + 46, 13, C.YELLOW, RIW)
            else text('Loading replaces your current stacks (Undo brings them back).', RX, by + 46, 12, C.DIM, RIW) end
        end

    -- ============================================================ + Armor
    elseif ui.adding then
        head(IX, TOP + 14, 'New stack', 'Choose armor passive', IW)
        local used = {}
        for _, prof in ipairs(LOADOUT.profiles) do used[prof.perk] = true end
        local y = TOP + 64
        for _, c in ipairs(CAT_LIST) do
            if not used[c.id] and y + RH < BOT - 50 then
                list_row('addpick:' .. c.id, y, up(c.name), ui.hover == 'addpick:' .. c.id)
                y = y + RH
            end
        end
        button('addcancel', 'Cancel', IX, BOT - 44, nil, 32, true)
        head(RX, TOP + 14, 'New stack', 'A second stack', RIW)
        text('Each armor passive can carry its own stack. Pick one on the left,', RX, TOP + 70, 14, C.MUTED, RIW)
        text('then wear any armor that has that passive to get the stack.', RX, TOP + 92, 14, C.MUTED, RIW)
        text('Example: Med-Kit armor for a tank build, Siege-Ready armor for a gunner build.', RX, TOP + 122, 13, C.DIM, RIW)

    elseif not p then
        head(IX, TOP + 14, 'No armor forged yet', 'Empty', IW)
        text('Nothing is stacked.', IX, TOP + 70, 14, C.MUTED, IW)
        head(RX, TOP + 14, 'How it works', 'Forge your armor', RIW)
        text('Pick the armor passive you wear (for example Med-Kit),', RX, TOP + 72, 15, C.TEXT, RIW)
        text('then tick any of the 31 passives to stack onto it and', RX, TOP + 94, 15, C.TEXT, RIW)
        text('change their values. Everything applies at once.', RX, TOP + 116, 15, C.TEXT, RIW)
        local bx = RX
        bx = bx + button('add', '+ Armor', bx, TOP + 152, nil, 36, true, true) + 8
        button('presets', 'Presets', bx, TOP + 152, nil, 36, true)

    -- ============================================================ an armor stack
    else
        local n_on = 0
        for _ in pairs(p.enabled) do n_on = n_on + 1 end
        head(IX, TOP + 14, 'Armor stack ' .. ui.tab .. ' / ' .. #LOADOUT.profiles, 'Choose passives', IW - 70)
        text(n_on .. ' ON', IX + IW, TOP + 14, 11, n_on > 0 and C.YELLOW or C.DIM, nil, 'right')
        local y = TOP + 60
        local base_key = 'sel:' .. p.perk
        if ui.sel == p.perk then rect(LX + 1, y, LW - 2, RH, C.ROW_HI, 951); rect(LX + 1, y, 3, RH, C.YELLOW, 952)
        elseif ui.hover == base_key then rect(LX + 1, y, LW - 2, RH, C.ROW, 951) end
        local bw = measure('BASE', 10) + 10
        rect(IX + 2, y + 5, bw, 14, C.YELLOW, 952)
        text('BASE', IX + 2 + bw / 2, y + 7, 10, C.INK, nil, 'center')
        text(up(CAT[p.perk].name), IX + bw + 12, y + 5, 14, C.TEXT, IW - bw - 16)
        region(base_key, LX + 1, y, LW - 2, RH)
        y = y + RH + 4
        for _, c in ipairs(CAT_LIST) do
            if c.id ~= p.perk then
                local on = p.enabled[c.id] == true
                local key = 'sel:' .. c.id
                if ui.sel == c.id then rect(LX + 1, y, LW - 2, RH - 1, C.ROW_HI, 951); rect(LX + 1, y, 3, RH - 1, C.YELLOW, 952)
                elseif ui.hover == key then rect(LX + 1, y, LW - 2, RH - 1, C.ROW, 951) end
                region(key, IX + 26, y, LW - 2 - (IX + 26 - LX), RH - 1)
                checkbox('tick:' .. c.id, IX + 2, y + 3, on)
                local tweaked = false
                for tk in pairs(p.tweaks) do if tk:match('^' .. c.id .. '%.') then tweaked = true break end end
                text(up(c.name), IX + 28, y + 5, 13, on and C.YELLOW or C.MUTED, IW - 44)
                if tweaked and on then rect(IX + IW - 6, y + 9, 6, 6, C.TEXT, 952) end
                y = y + RH
            end
        end

        if not ui.sel then ui.sel = p.perk end
        local sel = CAT[ui.sel]
        if sel then
            local is_base = sel.id == p.perk
            local on = is_base or p.enabled[sel.id] == true
            local cap = on and (is_base and 'Remove from stack' or 'Remove from stack') or 'Add to stack'
            local btn_w = measure(up(cap), 13) + 28
            head(RX, TOP + 14, 'Specifications', sel.name, RIW - (is_base and 0 or btn_w + 12))
            if not is_base then button('tick:' .. sel.id, cap, RX + RIW - btn_w, TOP + 18, btn_w, 32, true, not on) end
            local st = is_base and 'BASE PERK' or on and 'STACKED' or 'NOT STACKED'
            local sw = measure(st, 11) + 16
            border(RX, TOP + 50, sw, 18, is_base and C.YELLOW or on and C.GOOD or C.DIM, 952)
            text(st, RX + sw / 2, TOP + 54, 11, is_base and C.YELLOW or on and C.GOOD or C.DIM, nil, 'center')
            text(is_base and 'Your armor\'s own passive. Values here replace its own.'
                 or on and ('On ' .. CAT[p.perk].name .. ' armor.') or 'Values you set are kept for when you add it.',
                 RX + sw + 10, TOP + 53, 12, C.MUTED, RIW - sw - 12)
            -- value cards: label | value field | -- - + ++ | R
            local fw, bw2, gap, rw = 104, 36, 4, 26
            local controls = fw + 10 + 4 * bw2 + 3 * gap + 6 + rw
            local y2 = TOP + 82
            for n, e in ipairs(sel.effects) do
                local v = value_of(p, sel.id, e)
                local tweaked = v ~= e.def
                local u = PP.unit(e)
                rect(RX, y2, RIW, 60, C.ROW, 950)
                rect(RX, y2, 3, 60, tweaked and C.YELLOW or C.LINE2, 951)
                local lw = RIW - controls - 26
                text(label_of(e) .. (e.hint:find('%?') and ' ?' or ''), RX + 14, y2 + 10, 15, C.TEXT, lw)
                text(PP.WHAT[u] .. (e.hint:find('%?') and ' (name is a guess)' or ''), RX + 14, y2 + 32, 12, C.DIM, lw)
                local bx = RX + RIW - 10 - controls
                local typing = ui.value and ui.value.pid == sel.id and ui.value.n == n
                local vkey = 'value:' .. n
                rect(bx, y2 + 10, fw, 30, C.FIELD, 951)
                border(bx, y2 + 10, fw, 30, (typing or ui.hover == vkey) and C.YELLOW or tweaked and C.YELLOW_DK or C.LINE2)
                if typing then
                    text(ui.value.text .. '_', bx + 8, y2 + 17, 16, ui.value.fresh and C.MUTED or C.TEXT, fw - 16)
                else
                    text(PP.text(e, v), bx + fw - 8, y2 + 17, 16, tweaked and C.YELLOW or C.TEXT, fw - 16, 'right')
                end
                region(vkey, bx, y2 + 10, fw, 30)
                local ax = bx + fw + 10
                for _, b in ipairs({ { 'dec_big', '--' }, { 'dec', '-' }, { 'inc', '+' }, { 'inc_big', '++' } }) do
                    local key = b[1] .. ':' .. n
                    local hovered = ui.hover == key
                    rect(ax, y2 + 10, bw2, 30, hovered and C.YELLOW or C.PANEL, 951)
                    border(ax, y2 + 10, bw2, 30, hovered and C.YELLOW or C.LINE2)
                    text(b[2], ax + bw2 / 2, y2 + 17, 15, hovered and C.INK or C.TEXT, bw2 - 8, 'center')
                    region(key, ax, y2 + 10, bw2, 30)
                    ax = ax + bw2 + gap
                end
                ax = ax + 6 - gap
                local rkey = 'reset:' .. n
                text('R', ax + rw / 2, y2 + 17, 15, tweaked and ((ui.hover == rkey) and C.YELLOW or C.MUTED) or C.LINE2, nil, 'center')
                region(rkey, ax, y2 + 10, rw, 30, tweaked)
                text('GAME VALUE ' .. PP.raw_text(e, v) .. (tweaked and ('   WAS ' .. PP.text(e, e.def)) or ''),
                     bx, y2 + 45, 10, tweaked and C.YELLOW or C.DIM, controls)
                y2 = y2 + 66
            end
            local rp = 'reset_passive'
            local rcap = up('Reset ' .. sel.name)
            local rpw = math.min(RIW, measure(rcap, 11))
            text(rcap, RX, y2 + 8, 11, ui.hover == rp and C.YELLOW or C.DIM, RIW)
            region(rp, RX - 4, y2 + 2, rpw + 8, 22)
        end

        -- overlap rule, status, actions
        local by = BOT - 172
        rect(RX, by - 12, RIW, 1, C.LINE, 951)
        label('When two passives change the same thing', RX, by, nil, RIW)
        local strongest = p.conflicts == 'strongest'
        local bx = RX
        for _, opt in ipairs({ { 'policy:stack', 'Stack all', not strongest }, { 'policy:strongest', 'Strongest only', strongest } }) do
            bx = bx + button(opt[1], opt[2], bx, by + 18, 150, 30, true, opt[3], (not opt[3]) and C.MUTED or nil)
        end
        local last = last_result[p.perk]
        local res = last and last.res
        if not sites_by_perk[p.perk] then
            text('This armor passive was not found in the game\'s data yet.', RX, by + 62, 13, C.BAD, RIW)
        elseif sites_by_perk[p.perk][1].foreign then
            text('Another mod already changed this passive\'s data; Armory Forge leaves it alone.', RX, by + 62, 13, C.BAD, RIW)
        else
            local added = 0
            for _, site in ipairs(sites_by_perk[p.perk]) do added = math.max(added, site.added or 0) end
            local n_stacked = res and #res.enabled or 0
            rect(RX, by + 65, 7, 7, C.GOOD, 952)
            text(n_stacked .. ' passive(s) stacked, +' .. added .. ' row(s) in the game\'s data' ..
                 (res and res.conflicts > 0 and (' - ' .. res.conflicts .. ' overlap(s)') or ''), RX + 14, by + 62, 13, C.TEXT, RIW - 14)
            if last.error then text(last.error, RX, by + 80, 12, C.BAD, RIW) end
        end
        local sure = ui.confirm and ui.confirm.kind
        local ay = BOT - 50
        local ax = RX
        local each = (RIW - 3 * 8) / 4
        ax = ax + button('undo', #ui.history > 0 and ('Undo (' .. #ui.history .. ')') or 'Undo', ax, ay, each, 34, #ui.history > 0) + 8
        ax = ax + button('copy', 'Copy code', ax, ay, each, 34, true) + 8
        ax = ax + button('paste', 'Paste code', ax, ay, each, 34, true) + 8
        button('clear', sure == 'clear' and 'Click again' or 'Turn all off', ax, ay, each, 34, true, false, sure == 'clear' and C.BAD or nil)
    end

    prompts()
    return regions
end

-- ---------------------------------------------------------------- clicks
local function hit(x, y, enabled_only)
    for k = #ui.regions, 1, -1 do
        local r = ui.regions[k]
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
            if enabled_only and not r.enabled then return nil end
            return r.key
        end
    end
    return nil
end

local function confirm(kind)
    if ui.confirm and ui.confirm.kind == kind and now_s() < ui.confirm.till then
        ui.confirm = nil
        return true
    end
    ui.confirm = { kind = kind, till = now_s() + 4 }
    ui.version = ui.version + 1
    return false
end

local function finish_naming(keep)
    local nm = ui.naming
    ui.naming = nil
    ui.version = ui.version + 1
    if not nm or not keep then return end
    local name = PP.clean_name(nm.text)
    local entry = PP.user[nm.i]
    if name and entry then
        entry.name = name
        PP.save_user()
        say('Saved as "' .. name .. '"')
    end
end

local function click(key)
    if not key then return end
    local kind, arg = key:match('^([%w_]+):?(.*)$')
    if ui.value and (kind ~= 'value' or tonumber(arg) ~= ui.value.n or ui.sel ~= ui.value.pid) then finish_value(true) end
    if ui.naming and kind ~= 'pre' then finish_naming(true) end
    if ui.confirm and kind ~= ui.confirm.kind then ui.confirm = nil end
    local p = current()
    local n = tonumber(arg)
    if kind == 'tab' and n then ui.tab, ui.sel, ui.adding, ui.presets = n, nil, false, false
    elseif kind == 'add' then ui.adding, ui.presets = not ui.adding, false
    elseif kind == 'addcancel' then ui.adding = false
    elseif kind == 'presets' then ui.presets, ui.adding = not ui.presets, false; PP.load_user()
    elseif kind == 'addpick' and n then
        LOADOUT.profiles[#LOADOUT.profiles + 1] = { perk = n, conflicts = 'stack', enabled = {}, tweaks = {}, raw = {}, raw_stats = {} }
        ui.tab, ui.sel, ui.adding = #LOADOUT.profiles, nil, false
        changed(n, 'Added a stack for ' .. CAT[n].name .. ' armor')
    elseif kind == 'remove' and p then
        if confirm('remove') then
            table.remove(LOADOUT.profiles, ui.tab)
            ui.tab, ui.sel = math.max(1, ui.tab - 1), nil
            changed(p.perk, 'Removed the ' .. CAT[p.perk].name .. ' stack (the game\'s own values are back)')
        end
    elseif kind == 'sel' and n then ui.sel = n; ui.value = nil
    elseif kind == 'tick' and n and p then toggle(p, n)
    elseif kind == 'policy' and p then p.conflicts = arg; changed(p.perk)
    elseif kind == 'clear' and p then
        if confirm('clear') then p.enabled, p.tweaks = {}, {}; changed(p.perk, 'Turned everything off on this armor') end
    elseif kind == 'undo' then PP.undo()
    elseif kind == 'copy' then PP.copy_code()
    elseif kind == 'paste' then PP.paste_code()
    -- presets
    elseif kind == 'pre' then
        local k, i = arg:match('^(%a+):(%d+)$')
        ui.psel = { kind = k, i = tonumber(i) }
        if ui.naming and not (k == 'user' and ui.naming.i == tonumber(i)) then finish_naming(true) end
    elseif kind == 'pload' and ui.psel then
        for _, e in ipairs(PP.entries()) do
            if e.kind == ui.psel.kind and e.i == ui.psel.i then PP.load(e); ui.presets = false; break end
        end
    elseif kind == 'psave' then
        local base, k = 'My preset', #PP.user + 1
        local taken = {}
        for _, u in ipairs(PP.user) do taken[u.name] = true end
        while taken[base .. ' ' .. k] do k = k + 1 end
        PP.user[#PP.user + 1] = { name = base .. ' ' .. k, text = snapshot() }
        PP.save_user()
        ui.psel = { kind = 'user', i = #PP.user }
        ui.naming = { i = #PP.user, text = base .. ' ' .. k, fresh = true }
        say('Saved. Type a name for it, or press Enter to keep "' .. base .. ' ' .. k .. '".', 5)
    elseif kind == 'pover' and ui.psel and ui.psel.kind == 'user' then
        if confirm('pover') then
            PP.user[ui.psel.i].text = snapshot()
            PP.save_user()
            say('Saved your current stacks into "' .. PP.user[ui.psel.i].name .. '"')
        end
    elseif kind == 'pren' and ui.psel and ui.psel.kind == 'user' then
        ui.naming = { i = ui.psel.i, text = PP.user[ui.psel.i].name, fresh = true }
    elseif kind == 'pdel' and ui.psel and ui.psel.kind == 'user' then
        if confirm('pdel') then
            local gone = table.remove(PP.user, ui.psel.i)
            PP.save_user()
            ui.psel, ui.naming = nil, nil
            say('Deleted "' .. (gone and gone.name or '?') .. '"')
        end
    -- values
    elseif kind == 'reset_passive' and p and ui.sel then
        for k in pairs(p.tweaks) do if k:match('^' .. ui.sel .. '%.') then p.tweaks[k] = nil end end
        changed(p.perk)
    elseif p and ui.sel and n and CAT[ui.sel] and CAT[ui.sel].effects[n] then
        local e = CAT[ui.sel].effects[n]
        local u = PP.unit(e)
        local small, big = PP.steps(u)
        local f = PP.to_friendly(u, value_of(p, ui.sel, e))
        local step = (kind == 'dec' and -small) or (kind == 'dec_big' and -big) or (kind == 'inc' and small)
                     or (kind == 'inc_big' and big) or nil
        if step then
            set_value(p, ui.sel, e, PP.from_friendly(u, round1(f + step)))
        elseif kind == 'reset' then set_value(p, ui.sel, e, e.def)
        elseif kind == 'value' and not ui.value then
            ui.value = { pid = ui.sel, n = n, text = fmt(round1(f)), fresh = true }
        end
    end
    ui.version = ui.version + 1
end

-- Keyboard: presses, and repeats while held (after 0.4 s, every 0.08 s).
local function pressed(name, vk, now)
    local down = input.key_down(vk)
    local h = held[name]
    if not down then held[name] = nil; return false end
    if not h then held[name] = { next = now + 0.4 }; return true end
    if now >= h.next then h.next = now + 0.08; return true end
    return false
end

local function keyboard(now)
    local nm = ui.naming
    if nm then
        if pressed('Escape', VK.Escape, now) then finish_naming(false); return end
        if pressed('Enter', VK.Enter, now) then finish_naming(true); return end
        if pressed('Backspace', VK.Backspace, now) then
            nm.text = nm.fresh and '' or nm.text:sub(1, -2)
            nm.fresh = false
            ui.version = ui.version + 1
        end
        local shift = input.key_down(VK.Shift)
        for _, k in ipairs(NAME_KEYS) do
            if pressed('N' .. k[1], k[1], now) then
                if nm.fresh then nm.text, nm.fresh = '', false end
                if #nm.text < 28 then nm.text = nm.text .. (shift and k[3] or k[2]) end
                ui.version = ui.version + 1
            end
        end
        return
    end
    local v = ui.value
    if v then
        if pressed('Escape', VK.Escape, now) then finish_value(false); return end
        if pressed('Enter', VK.Enter, now) then finish_value(true); return end
        if pressed('Backspace', VK.Backspace, now) then
            v.text = v.fresh and '' or v.text:sub(1, -2)
            v.fresh = false
            ui.version = ui.version + 1
        end
        for _, k in ipairs(DIGIT_KEYS) do
            if pressed('D' .. k[1], k[1], now) then
                if v.fresh then v.text, v.fresh = '', false end
                if #v.text < 12 then v.text = v.text .. k[2] end
                ui.version = ui.version + 1
            end
        end
        return
    end
    if input.key_down(VK.Ctrl) and pressed('Z', 0x5A, now) then PP.undo() end
end

local function mouse()
    local x, y, cw, ch = input.cursor()
    if not x or cw <= 0 or ch <= 0 or x < 0 or y < 0 or x >= cw or y >= ch then return end
    local width, height = sr.Gui.resolution()
    ui.hover = hit(x * width / cw, (ch - y) * height / ch, true)
    local value = sr.Mouse.button(sr.Mouse.button_id('left'))
    local down = value == true or (type(value) == 'number' and value > 0)
    if mouse_was_down ~= nil then
        if down and not mouse_was_down then armed = ui.hover end
        if not down and mouse_was_down then
            if armed and armed == ui.hover then click(armed) end
            armed = nil
        end
    end
    mouse_was_down = down
end

-- ---------------------------------------------------------------- cursor (from SHODAN v1.4.1)
local cursor = { taken = false }

local function window_fn(name)
    local f = sr.Window and rawget(sr.Window, name)
    return type(f) == 'function' and f or nil
end

local function engine_cursor_shown()
    local f = window_fn('show_cursor')
    if not f then return nil end
    local ok, shown = pcall(f)
    if ok and type(shown) == 'boolean' then return shown end
    return nil
end

local function take_cursor()
    if cursor.taken then return end
    cursor.taken = true
    local set_show, set_clip = window_fn('set_show_cursor'), window_fn('set_clip_cursor')
    cursor.was_shown = engine_cursor_shown()
    cursor.engine = set_show ~= nil
    if cursor.engine then
        pcall(set_show, true)
        if set_clip then pcall(set_clip, false) end
    end
    cursor.shows = 0
    while input.show_cursor(true) < 0 and cursor.shows < 20 do cursor.shows = cursor.shows + 1 end
    cursor.shows = cursor.shows + 1
    cursor.clip = input.get_clip()
    input.set_clip(nil)
end

local function keep_cursor()
    if not cursor.taken then return end
    if engine_cursor_shown() == false then
        local set_show, set_clip = window_fn('set_show_cursor'), window_fn('set_clip_cursor')
        if set_show then pcall(set_show, true) end
        if set_clip then pcall(set_clip, false) end
    end
end

local function release_cursor()
    if not cursor.taken then return end
    cursor.taken = false
    if cursor.engine and cursor.was_shown == false then
        local set_show, set_clip = window_fn('set_show_cursor'), window_fn('set_clip_cursor')
        pcall(set_show, false)
        if set_clip then pcall(set_clip, true) end
    end
    for _ = 1, cursor.shows or 0 do input.show_cursor(false) end
    if cursor.clip then input.set_clip(cursor.clip) end
end


-- ---------------------------------------------------------------- per frame (from SHODAN v1.4.1)
local SETTLE_SECONDS = 1.5

local function same_worlds(a, b)
    if not a or not b or #a ~= #b then return false end
    for k = 1, #a do if a[k] ~= b[k] then return false end end
    return true
end

local function overlay_world()
    local main = sr.Application.main_world()
    for _, w in ipairs(sr.Application.worlds() or {}) do if w ~= main then return w end end
    return nil
end

local function panel_frame(now)
    pcall(keep_cursor)
    local main = sr.Application.main_world()
    local worlds = sr.Application.worlds() or {}
    if not same_worlds(worlds, ui.worlds) or main ~= ui.main then
        clear_gui()
        ui.worlds, ui.main, ui.settled_at = worlds, main, now + SETTLE_SECONDS
        return
    end
    if now < ui.settled_at then return end
    local world = overlay_world()
    if not world then clear_gui(); return end
    if ui.world ~= world then
        clear_gui()
        ui.world = world
    end

    ui.hover = nil
    if input.focused() and not ui.mouse_broken then
        local ok, why = pcall(mouse)
        if not ok then
            ui.mouse_broken = true
            log('panel: mouse input off for this session: ' .. tostring(why))
        end
    end
    if not ui.hover then mouse_was_down, armed = nil, nil end
    if input.focused() then keyboard(now) end

    local width, height = sr.Gui.resolution()
    if ui.message and now >= ui.message.till then ui.message = nil end
    if ui.confirm and now >= ui.confirm.till then ui.confirm = nil; ui.version = ui.version + 1 end
    local signature = table.concat({ width, height, state.phase, perks_found, ui.tab, tostring(ui.sel),
                                     tostring(ui.hover), ui.version, tostring(ui.adding), tostring(ui.presets),
                                     ui.message and ui.message.text or '',
                                     ui.value and (ui.value.n .. '=' .. ui.value.text) or '-',
                                     ui.naming and ui.naming.text or '-' }, '|')
    if signature ~= ui.signature then
        if ui.gui then pcall(sr.World.destroy_gui, ui.world, ui.gui) end
        ui.gui = sr.World.create_screen_gui(ui.world, 'scale', 1, 1)
        if not ui.gui then
            log('panel: the overlay world refused a gui')
            clear_gui()
            return
        end
        local ok, chosen = pcall(choose_font, ui.gui)
        font = ok and chosen or { text = 'no text: ' .. tostring(chosen) }
        if font.text ~= ui.font_said then
            ui.font_said = font.text
            log('panel font: ' .. font.text)
        end
        ui.signature = signature
        ui.regions = draw(width, height)
    end
end

-- ---------------------------------------------------------------- quick-swap toast
-- A small card at the top of the screen for ~2 s after the quick-swap key, drawn once
-- into its own gui (the panel stays closed).
local function clear_toast()
    if toast.gui and toast.world then
        for _, w in ipairs(sr.Application.worlds() or {}) do
            if w == toast.world then pcall(sr.World.destroy_gui, toast.world, toast.gui) break end
        end
    end
    toast.gui, toast.world = nil, nil
end

local function toast_frame(now)
    if not toast.text then return end
    if now >= toast.till then clear_toast(); toast.text = nil; return end
    if toast.gui then return end
    local world = overlay_world()
    if not world then return end
    local gui = sr.World.create_screen_gui(world, 'scale', 1, 1)
    if not gui then return end
    toast.gui, toast.world = gui, world
    local ok, f = pcall(choose_font, gui)
    f = ok and f or {}
    local Gui, Vector3, Vector2, Color = sr.Gui, sr.Vector3, sr.Vector2, sr.Color
    local width, height = sr.Gui.resolution()
    local s = height / 1080
    local w, h = 480 * s, 72 * s
    local x, y = (width - w) / 2, height - 140 * s - h
    local yellow = Color(255, 255, 231, 16)
    local function r(px, py, pw, ph, c, z)      -- panel units from the card's top left
        Gui.rect(gui, Vector3(x + px * s, y + h - (py + ph) * s, z or 961), Vector2(pw * s, ph * s), c)
    end
    r(0, 0, 480, 72, Color(246, 11, 12, 13), 960)
    r(0, 0, 4, 72, yellow)
    r(4, 0, 476, 1, Color(255, 62, 65, 70)); r(4, 71, 476, 1, Color(255, 62, 65, 70)); r(479, 0, 1, 72, Color(255, 62, 65, 70))
    if f.font then
        local function t(value, px, py, size, c)
            Gui.text(gui, value, f.font, size * s, f.material, Vector3(x + px * s, y + h - py * s - size * s * 0.8, 962), c)
        end
        t('ARMORY FORGE  -  ' .. string.upper(tostring(toast.sub or '')), 20, 13, 11, yellow)
        t(tostring(toast.text), 20, 34, 22, Color(255, 233, 230, 220))
    end
end

local function open_panel(open)
    ui.open = open
    if open then
        ui.worlds = nil
        clear_toast(); toast.text = nil
        if not ui.last_text and LOADOUT then ui.last_text = snapshot() end
        PP.load_user()
        log('panel opened')
        local ok, why = pcall(take_cursor)
        if not ok then log('cursor: could not free it: ' .. tostring(why)) end
    else
        if ui.value then finish_value(true) end
        if ui.naming then finish_naming(true) end
        pcall(release_cursor)
        clear_gui()
        ui.worlds = nil
        held, mouse_was_down, armed = {}, nil, nil
        ui.confirm, ui.adding = nil, false
        if save_at then pcall(save_now) end
    end
end

-- true once per press of a hotkey (window focused)
local function hotkey_pressed(name)
    local vk = VK[name]
    if not vk then return false end
    local down = input.key_down(vk)
    local was = keys_was[name]
    keys_was[name] = down
    return down and not was and input.focused()
end

panel_tick = function(now)
    if not input or not sr then return end
    if hotkey_pressed(hotkey()) then open_panel(not ui.open) end
    if not ui.hinted and state.phase == 'ready' then
        -- nothing stacked yet (fresh install): say where the panel is, once
        ui.hinted = true
        if LOADOUT and #LOADOUT.profiles == 0 and not ui.open then
            toast.text, toast.sub, toast.till = 'Press ' .. hotkey() .. ' to forge your armor', 'ready', now + 6
        end
    end
    local sk = swap_key()
    if sk ~= 'OFF' and sk ~= hotkey() and hotkey_pressed(sk) and not ui.value and not ui.naming
       and state.phase == 'ready' and now >= (ui.swap_at or 0) then
        ui.swap_at = now + 0.25
        if not ui.last_text and LOADOUT then ui.last_text = snapshot() end
        local ok, why = pcall(PP.swap)
        if not ok then log('quick-swap: ' .. tostring(why)) end
    end
    if ui.open then
        local ok, why = pcall(panel_frame, now)
        if ok then
            ui.errors = 0
        else
            ui.errors = ui.errors + 1
            log('panel error: ' .. tostring(why))
            pcall(clear_gui)
            if ui.errors >= 5 then
                open_panel(false)
                log('panel closed after 5 errors in a row')
            end
        end
    else
        local ok, why = pcall(toast_frame, now)
        if not ok then log('toast: ' .. tostring(why)); pcall(clear_toast); toast.text = nil end
    end
end

setup_panel = function()
    sr = rawget(_G, 'stingray')
    if type(sr) ~= 'table' then log('panel: the engine (stingray) is unavailable; panel off'); return end
    local ok, built = pcall(function() return rawget(_G, 'PP_TEST_INPUT') or build_input() end)
    if not ok then log('panel: input unavailable: ' .. tostring(built)); return end
    input = built
    state.ui = ui
    state.pp = PP
    log('panel ready: press ' .. hotkey() .. ' in game' ..
        (swap_key() ~= 'OFF' and ('; ' .. swap_key() .. ' swaps presets') or ''))
end

end
build_panel()
