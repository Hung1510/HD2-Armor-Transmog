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
    -- Xbox-style controller (XInput). Declared with void* so another mod's own XInput
    -- declaration can't clash; the state is read from a raw 16-byte buffer.
    pcall(ffi.cdef, 'uint32_t XInputGetState(uint32_t index, void *state);')
    local xinput = nil
    for _, name in ipairs({ 'xinput1_4', 'xinput1_3', 'xinput9_1_0' }) do
        local ok, lib = pcall(ffi.load, name)
        if ok and lib then xinput = lib break end
    end
    local pad_buf, pad_slot, pad_probe, pad_frames = ffi.new('uint8_t[16]'), nil, 0, 0
    -- buttons, left stick x/y, right stick x/y of the first connected controller, or nil.
    -- Asking an empty slot is slow, so without a controller one slot is tried every 60 frames.
    function self.pad()
        if not xinput then return nil end
        if not pad_slot then
            pad_frames = pad_frames + 1
            if pad_frames % 60 ~= 1 then return nil end
            local ok, r = pcall(xinput.XInputGetState, pad_probe, ffi.cast('void *', pad_buf))
            if ok and r == 0 then pad_slot = pad_probe else pad_probe = (pad_probe + 1) % 4; return nil end
        end
        local ok, r = pcall(xinput.XInputGetState, pad_slot, ffi.cast('void *', pad_buf))
        if not ok or r ~= 0 then pad_slot = nil; return nil end
        local s16 = ffi.cast('int16_t *', pad_buf + 8)
        return ffi.cast('uint16_t *', pad_buf + 4)[0], s16[0], s16[1], s16[2], s16[3]
    end
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
             swap_at = 0, scroll = {}, scrolling = nil, pos = nil, drag = nil,
             settings = false, search = '', search_on = false,
             pad_mode = false, focus = nil, nav_retry = nil }
local W, H = 1000, 990
local font = nil
local held, mouse_was_down, armed = {}, nil, nil
local keys_was = {}          -- hotkeys: pressed this frame but not last
local toast = { text = nil, sub = nil, till = 0, gui = nil, world = nil }
-- presets, share codes and units live in one table to keep the chunk's local count low
local PP = { user = nil }

-- The panel key and the quick-swap key: F1..F12 (quick-swap also OFF). A bad value in a
-- hand-edited loadout.ini falls back to F7 / F9, so the panel can always be opened.
function PP.fkey(k) return type(k) == 'string' and k:match('^F%d%d?$') and VK[k] and k or nil end
local function hotkey() return PP.fkey(LOADOUT and LOADOUT.hotkey) or PP.fkey(MOD.hotkey) or 'F7' end
local function swap_key()
    local k = (LOADOUT and LOADOUT.swap_hotkey) or MOD.swap_hotkey or 'F9'
    if k == 'OFF' then return 'OFF' end
    k = PP.fkey(k) or 'F9'
    return k ~= hotkey() and k or 'OFF'
end
-- panel size the player chose (0.8 .. 1.5), Ctrl +/- in the panel
local function ui_scale()
    local v = tonumber((LOADOUT and LOADOUT.panel_scale) or MOD.panel_scale) or 1
    return math.max(0.8, math.min(1.5, v))
end
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
        l.panel_scale = LOADOUT.panel_scale
    end
    l.name = l.name or (LOADOUT and LOADOUT.name) or MOD.title
    l.hotkey, l.swap_hotkey = l.hotkey or MOD.hotkey or 'F7', l.swap_hotkey or MOD.swap_hotkey or 'F9'
    if l.retire == nil then l.retire = MOD.retire end
    l.panel_scale = l.panel_scale or MOD.panel_scale or 1
    LOADOUT = l
    -- undo (exact) stays where you are when that tab still exists
    local keep = exact and ui.tab <= #l.profiles
    ui.tab, ui.sel, ui.value, ui.adding = keep and ui.tab or 1, keep and ui.sel or nil, nil, false
    changed(nil, text)
end

function PP.undo()
    local prev = table.remove(ui.history)
    if not prev then say('Nothing to undo'); return end
    local ok, l = pcall(parse_loadout, prev)
    if not ok or not l then say('Could not undo'); return end
    ui.last_text = nil                      -- an undo is not itself undoable
    if LOADOUT then                         -- keys and panel size are settings, not undo steps
        l.hotkey, l.swap_hotkey, l.panel_scale = LOADOUT.hotkey, LOADOUT.swap_hotkey, LOADOUT.panel_scale
    end
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

-- The loadout in as few bytes as the loadout reader accepts: passives by number, only
-- the ones that are on, only changed values, no keys or panel settings (those stay the
-- reader's own). Every reader since 5.2 (panel, web builder, picker.py) loads it as is.
-- tests/test_share_codes.py keeps it in step with core.js compactIni / picker.compact_ini.
function PP.compact(l)
    local L = { '[settings]', 'name=' .. (tostring(l.name or MOD.title):gsub('[;#\r\n=]', ' ')) }
    for _, p in ipairs(l.profiles) do
        L[#L + 1] = '[profile: ' .. p.perk .. ']'
        if p.conflicts == 'strongest' then L[#L + 1] = 'conflicts=strongest' end
        if WEIGHTS[p.weight] then L[#L + 1] = 'weight=' .. WEIGHTS[p.weight] end
        for _, pid in ipairs(sorted_enabled(p)) do L[#L + 1] = pid .. '=on' end
        local keys = {}
        for k, v in pairs(p.tweaks) do
            local pid, key = k:match('^(%d+)%.(.+)$')
            pid = tonumber(pid)
            local e = pid and CAT[pid] and CAT[pid].by_key[key]
            if e and v ~= e.def and (pid == p.perk or p.enabled[pid]) then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do L[#L + 1] = k .. '=' .. fmt_num(p.tweaks[k]) end
        local raw = {}
        for _, r in ipairs(p.raw or {}) do raw[#raw + 1] = string.format('0x%08X %d %s', r[1], r[2], fmt_num(r[3])) end
        if #raw > 0 then L[#L + 1] = 'raw=' .. table.concat(raw, ', ') end
        raw = {}
        for _, r in ipairs(p.raw_stats or {}) do raw[#raw + 1] = string.format('%d %s %s', r[1], fmt_num(r[2]), fmt_num(r[3])) end
        if #raw > 0 then L[#L + 1] = 'raw_stats=' .. table.concat(raw, ', ') end
    end
    return table.concat(L, '\n') .. '\n'
end

function PP.copy_code()
    local code = PP.SITE .. PP.b64(PP.compact(LOADOUT))
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
function PP.user_file() return MOD.swap_only and 'my-swaps.txt' or 'my-presets.txt' end
function PP.user_path() return forge_file(PP.user_file()) end

function PP.load_user()
    PP.user = {}
    local text = read_saved(PP.user_file())
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

-- panel size: +1 / -1 steps of 10 %, 0 resets. Saved with the loadout, not undoable.
-- search: a passive matches when its name or one of its effects contains the text
function PP.match(c)
    local q = norm(ui.search or '')
    if q == '' then return true end
    if norm(c.name):find(q, 1, true) then return true end
    for _, e in ipairs(c.effects) do
        if norm(label_of(e)):find(q, 1, true) then return true end
    end
    return false
end
-- passive info (tools/passives.json + TESTING.md, generated into PASSIVE_INFO)
function PP.info(pid)
    local c = CAT[pid]
    return c and PASSIVE_INFO and PASSIVE_INFO.by_name[c.name] or nil
end
-- how far an effect is confirmed in game: tag text and its colour name
function PP.test_tag(e)
    local t = PASSIVE_INFO and PASSIVE_INFO.tested[e.key]
    if t == 'ok' then return 'CONFIRMED IN GAME', 'GOOD' end
    if t == 'odd' then return 'WORKS, NAME UNSURE', 'YELLOW' end
    if t == 'no' then return 'NO EFFECT SEEN', 'BAD' end
    return 'UNTESTED', 'DIM'
end
-- The stack's combined effect, one line per effect: the armor's own rows (with your
-- values) plus every stacked passive's. Additive values add up, multipliers multiply.
-- An estimate: how the game combines stacked rows is not confirmed in game.
function PP.summary_rows(p)
    if not PP.by_ident then
        PP.by_ident = {}
        for _, c in ipairs(CAT_LIST) do
            for _, e in ipairs(c.effects) do
                if e.kind == 'row' and not PP.by_ident[e.a .. '|' .. e.b] then PP.by_ident[e.a .. '|' .. e.b] = e end
            end
        end
    end
    local rows, seen = {}, {}
    local base = CAT[p.perk]
    for _, e in ipairs(base and base.effects or {}) do
        if e.kind == 'row' then
            local v = p.tweaks[p.perk .. '.' .. e.key]
            if v == nil then v = e.def end
            rows[#rows + 1] = { e.a, e.b, v }
            seen[e.a .. '|' .. e.b .. '|' .. v] = true
        end
    end
    local ok, res = pcall(resolve_profile, p)
    for _, r in ipairs(ok and res and res.rows or {}) do
        if not seen[r[1] .. '|' .. r[2] .. '|' .. r[3]] then rows[#rows + 1] = r end
    end
    local groups, order = {}, {}
    for _, r in ipairs(rows) do
        local e = PP.by_ident[r[1] .. '|' .. r[2]]
        if e then
            local g = groups[e.key]
            if not g then
                g = { e = e, n = 0 }
                groups[e.key] = g
                order[#order + 1] = g
            end
            local v = r[3]
            if g.n == 0 then g.v = v
            elseif e.type == 2 then g.v = g.v * v
            elseif e.type == 1 or e.type == 3 then g.v = g.v + v
            else g.v = math.max(g.v, v) end
            g.n = g.n + 1
        end
    end
    table.sort(order, function(a, b) return label_of(a.e) < label_of(b.e) end)
    return order
end
function PP.set_search(text, on)
    if text ~= ui.search then ui.scroll = {} end         -- a new search starts at the top
    ui.search, ui.search_on = text, on
    ui.version = ui.version + 1
end

-- change the panel key or the quick-swap key from the Keys tab (saved, not an undo step)
function PP.set_key(which, k)
    if not LOADOUT then return end
    LOADOUT.hotkey, LOADOUT.swap_hotkey = hotkey(), swap_key()     -- what actually works now
    if which == 'hotkey' then
        if not PP.fkey(k) or k == hotkey() then return end
        if k == swap_key() then LOADOUT.swap_hotkey = 'OFF' end
        LOADOUT.hotkey = k
        say('The panel now opens with ' .. k, 3)
    elseif which == 'swap_hotkey' then
        if k ~= 'OFF' and (not PP.fkey(k) or k == hotkey()) then return end
        LOADOUT.swap_hotkey = k
        say(k == 'OFF' and 'Quick-swap key turned off' or ('Quick-swap is now ' .. k), 3)
    else return end
    ui.last_text = snapshot()          -- a key change is not an undo step
    loadout_changed({})
end

function PP.zoom(step)
    if not LOADOUT then return end
    local v = step == 0 and 1 or math.floor((ui_scale() + step * 0.1) * 10 + 0.5) / 10
    v = math.max(0.8, math.min(1.5, v))
    if step == 0 and ui.pos then                 -- Ctrl 0 also puts the panel back in place
        ui.pos = nil
        PP.save_pos()
        ui.version = ui.version + 1
        if v == LOADOUT.panel_scale then say('Panel back in place', 1.5); return end
    end
    if v == LOADOUT.panel_scale then return end
    LOADOUT.panel_scale = v
    ui.last_text = snapshot()          -- a size change is not an undo step
    loadout_changed({})
    say(string.format('Panel size %d%%', v * 100 + 0.5), 1.5)
end

-- scroll the list that is too long for its box (wheel, PageUp/PageDown, its bar)
function PP.scroll(rows)
    local sc = ui.scrolling
    if not sc then return end
    local v = math.max(0, math.min(sc.max, (ui.scroll[sc.id] or 0) + rows))
    if v ~= ui.scroll[sc.id] then ui.scroll[sc.id] = v; ui.version = ui.version + 1 end
end

-- where the panel sits: dragged by its top strip, kept in ArmoryForge\panel-position.txt
-- as a fraction of the screen (so it survives a resolution change)
function PP.load_pos()
    local t = read_file(forge_file('panel-position.txt'))
    local x, y = tostring(t or ''):match('x%s*=%s*([%d%.]+)'), tostring(t or ''):match('y%s*=%s*([%d%.]+)')
    ui.pos = (tonumber(x) and tonumber(y)) and { fx = tonumber(x), fy = tonumber(y) } or nil
end
function PP.save_pos()
    local path = forge_file('panel-position.txt')
    if not path then return end
    if ui.pos then
        write_file(path, string.format('x = %.4f\ny = %.4f\n', ui.pos.fx, ui.pos.fy))
    else
        write_file(path, '')
    end
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
        out[#out + 1] = { armor = CAT[p.perk].name, names = names, tweaks = tweaks, policy = p.conflicts,
                          swap = MOD.swap_only and CAT[p.swap] and p.swap ~= p.perk and CAT[p.swap].name or nil }
    end
    return out
end

-- the game's numbers per weight class (armory screen), for the weight view
PP.WEIGHT_STATS = { { 'Light', '50', '550', '125' }, { 'Medium', '100', '500', '100' }, { 'Heavy', '150', '450', '50' } }

function PP.clean_name(s)
    s = (s or ''):gsub('[#\r\n]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return s ~= '' and s:sub(1, 28) or nil
end

-- ---------------------------------------------------------------- problem report
-- What the panel saw, for "the key does nothing" and crash reports. It goes into the
-- STATUS file (Logs\ArmoryForge-STATUS.txt, rewritten at most every 5 s when something
-- changes) and "Copy problem report" on the Keys tab puts it on the clipboard.
PP.diag = { presses = 0, unfocused = 0, opened = 0, drawn = 0, no_world = 0, resettle = 0, refused = 0 }

function PP.note(what, err)
    local d = PP.diag
    d[what] = (d[what] or 0) + 1
    if err then d.last_error = tostring(err):sub(1, 200) end
    -- counters that tick every frame only mark the report once
    if (what ~= 'no_world' and what ~= 'drawn') or d[what] == 1 then PP.diag_dirty = true end
end

function PP.names_of(t, limit)
    local list = {}
    if type(t) ~= 'table' then return '-' end
    for k in pairs(t) do if type(k) == 'string' then list[#list + 1] = k end end
    table.sort(list)
    local more = #list - limit
    while #list > limit do list[#list] = nil end
    if #list == 0 then return '-' end
    return table.concat(list, ', ') .. (more > 0 and (' +' .. more .. ' more') or '')
end

function PP.report()
    local d = PP.diag
    local w, h = 0, 0
    if sr then pcall(function() w, h = sr.Gui.resolution() end) end
    local focused = input and input.focused and select(2, pcall(input.focused))
    local added = {}
    for k in pairs(_G) do if type(k) == 'string' and PP.globals0 and not PP.globals0[k] then added[k] = true end end
    local loader = rawget(_G, 'CowboyBingusModLoader')
    local bus = rawget(_G, 'OCLAW_UPDATE_BUS')
    return {
        '--- panel ---',
        'edition=' .. (MOD.swap_only and 'Passive Swap' or 'full') .. (MOD.blank and ' (release)' or ' (web builder build)') ..
            ' panel key=' .. hotkey() .. ' quick-swap=' .. swap_key(),
        'panel key presses seen=' .. d.presses .. ' (while the game was not the active window: ' .. d.unfocused .. ')',
        'panel opened=' .. d.opened .. ' drawn=' .. d.drawn .. ' no UI world=' .. d.no_world ..
            ' world changes=' .. d.resettle .. ' gui refused=' .. d.refused,
        'game window active=' .. tostring(focused) .. ' screen=' .. tostring(w) .. 'x' .. tostring(h) ..
            ' panel size=' .. math.floor(ui_scale() * 100 + 0.5) .. '%',
        'font=' .. tostring(ui.font_said or '(not drawn yet)'),
        'controller=' .. (PP.has_pad and 'connected' or 'not seen') .. ' mouse=' .. (ui.mouse_broken and 'off after an error' or 'ok'),
        'last panel error=' .. tostring(d.last_error or '-'),
        '--- other mods ---',
        'loader api=' .. tostring(type(loader) == 'table' and loader.api) .. ' fields: ' .. PP.names_of(loader, 12),
        'update bus jobs: ' .. PP.names_of(type(bus) == 'table' and bus.jobs, 20),
        'globals added after Armory Forge started: ' .. PP.names_of(added, 30),
    }
end

function PP.copy_report()
    local lines = { MOD.title .. ' v' .. MOD.version .. ' problem report',
                    'status: ' .. tostring(state.phase) .. ' - ' .. tostring(state.status),
                    'armor passives found=' .. perks_found .. ' of ' .. #CAT_LIST }
    for _, l in ipairs(PP.report()) do lines[#lines + 1] = l end
    lines[#lines + 1] = '--- log (last 20) ---'
    for i = math.max(1, #log_lines - 19), #log_lines do lines[#lines + 1] = log_lines[i] end
    local ok = input.set_clipboard and input.set_clipboard(table.concat(lines, '\r\n') .. '\r\n')
    say(ok and 'Problem report copied: paste it in your bug report' or 'Could not use the clipboard', 4)
    pcall(write_status)
    return ok
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
    -- panel units -> screen pixels at the screen's own resolution, never bigger than
    -- the screen; every edge and font size is rounded to a whole pixel so text and
    -- lines stay sharp at 1440p / 4K (fractional positions are what made them soft)
    local s = math.min(height / 1080 * 0.8 * ui_scale(), height * 0.96 / H, (width - 60) / W)
    local function px(v) return math.floor(v + 0.5) end
    local ox, oy = px(30 * s), px((height - H * s) / 2)     -- left edge: SHODAN Stat Editor uses the right
    if ui.pos then                                           -- dragged somewhere else; always on screen
        ox = px(math.max(0, math.min(width - W * s, ui.pos.fx * width)))
        oy = px(math.max(0, math.min(height - H * s, ui.pos.fy * height)))
    end
    ui.origin = { x = ox, y = oy, w = width, h = height }
    ui.scrolling = nil
    local gui = ui.gui
    local regions = {}
    ui.tab_order = {}                        -- tab keys left to right (LB / RB), drawn or not
    for n = 1, #(LOADOUT and LOADOUT.profiles or {}) do ui.tab_order[n] = 'tab:' .. n end
    for _, k in ipairs({ 'add', 'presets', 'settings' }) do ui.tab_order[#ui.tab_order + 1] = k end
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
        local x0, x1 = px(ox + x * s), px(ox + (x + w) * s)
        local y0, y1 = px(oy + y * s), px(oy + (y + h) * s)
        if x1 <= x0 then x1 = x0 + 1 end
        if y1 <= y0 then y1 = y0 + 1 end
        Gui.rect(gui, Vector3(x0, height - y1, z or 951), Vector2(x1 - x0, y1 - y0), c)
    end
    local function font_px(size) return math.max(7, px(size * s)) end
    -- width in screen pixels of a text at a whole-pixel font size: measured when the
    -- engine can, else a safe per-character estimate (on the wide side)
    local function measure_px(value, sz)
        local ok, lo, hi = pcall(Gui.text_extents, gui, value, ink_font, sz)
        if ok and lo and hi then
            local a, b = vx(lo), vx(hi)
            if a and b and b > a then return b - a end
        end
        local w = 0
        for ch in value:gmatch('.') do
            w = w + (ch:find('[%%@MWmw]') and 0.98 or ch:find('[%u+=<>#&]') and 0.8 or ch:find('%d') and 0.66
                     or ch:find('[%s%.,:;!|il\'%-%(%)%[%]]') and 0.36 or 0.62)
        end
        return w * sz
    end
    -- width in panel units
    local function measure(value, size) return measure_px(value, font_px(size)) / s end
    -- limit: shrink (in whole pixels) to fit that width; align: 'right' or 'center' around x
    local function text(value, x, y, size, c, limit, align)
        if value == nil or value == '' or not ink_font then return 0 end
        local sz = font_px(size)
        local w = measure_px(value, sz) / s
        while limit and w > limit and sz > 6 do
            sz = math.max(6, math.min(sz - 1, math.floor(sz * limit / w)))
            w = measure_px(value, sz) / s
        end
        local tx = x
        if align == 'right' then tx = x - w elseif align == 'center' then tx = x - w / 2 end
        -- keep the text's cap-height box where a size-`size` text would sit
        local top = y + (size - sz / s) * 0.5
        Gui.text(gui, value, ink_font, sz, ink_material,
                 Vector3(px(ox + tx * s), px(height - oy - top * s - sz * 0.8), 954), c or C.TEXT)
        return w
    end
    local function border(x, y, w, h, c, z)
        rect(x, y, w, 1, c, z or 952); rect(x, y + h - 1, w, 1, c, z or 952)
        rect(x, y, 1, h, c, z or 952); rect(x + w - 1, y, 1, h, c, z or 952)
    end
    local function region(key, x, y, w, h, enabled)
        regions[#regions + 1] = { key = key, x = px(ox + x * s), y = px(height - oy - (y + h) * s), w = px(w * s), h = px(h * s),
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
    local function tab(key, caption, x, active, ink, n, maxw)
        caption = up(caption)
        local w = math.min(maxw or 230, measure(caption, 15) + (n and 44 or 30))
        local lim = w - (n and 36 or 20)
        if measure(caption, 11) > lim then         -- too long even at 11: cut it, "CONCUSSIVE PADD.."
            while #caption > 3 and measure(caption .. '..', 11) > lim do caption = caption:sub(1, -2) end
            caption = caption:gsub('[%s,]+$', '') .. '..'
        end
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
    -- the top strip is the handle: drag it to move the panel (Ctrl 0 puts it back)
    local grab = ui.hover == 'drag' or ui.drag ~= nil
    if grab then rect(1, 3, W - 2, 29, C.ROW, 951) end
    region('drag', 0, 0, W, 32)
    local mx = text('MINISTRY OF DEFENSE', 22, 12, 11, C.MUTED)
    text('SUPER EARTH ARMORY FORGE', 22 + mx + 12, 12, 11, C.TEXT)
    -- size control: [-] 100% [+]   (Ctrl +/- does the same)
    local vw = text('V' .. tostring(MOD.version), W - 22, 12, 11, C.DIM, nil, 'right')
    local zx = W - 22 - vw - 26
    local pct = string.format('%d%%', ui_scale() * 100 + 0.5)
    for _, z in ipairs({ { 'zoom:+', '+' }, { 'zoom:-', '-' } }) do
        local on = ui.hover == z[1]
        zx = zx - 20
        border(zx, 7, 20, 18, on and C.YELLOW or C.LINE2, 952)
        text(z[2], zx + 10, 10, 12, on and C.YELLOW or C.MUTED, nil, 'center')
        region(z[1], zx, 7, 20, 18)
        if z[2] == '+' then
            zx = zx - 6 - measure(pct, 11)
            text(pct, zx, 12, 11, C.MUTED)
            zx = zx - 6
        end
    end
    local sx = zx - 8 - text('SIZE', zx - 8, 12, 11, C.DIM, nil, 'right')
    -- grip: two rows of dots, and "drag to move" while the mouse is on the strip
    local gx = sx - 30
    for k = 0, 3 do for j = 0, 1 do rect(gx + k * 5, 12 + j * 5, 2, 2, grab and C.YELLOW or C.DIM, 952) end end
    if grab then text('DRAG TO MOVE', gx - 10, 12, 11, C.YELLOW, nil, 'right') end
    rect(0, 32, W, 1, C.LINE, 951)
    -- emblem box: the shield from the mod icon
    border(22, 44, 50, 50, C.TEXT, 952)
    rect(33, 54, 28, 20, C.YELLOW, 952); rect(36, 74, 22, 4, C.YELLOW, 952)
    rect(40, 78, 14, 4, C.YELLOW, 952); rect(44, 82, 6, 3, C.YELLOW, 952)
    rect(38, 59, 18, 4, C.INK, 953); rect(42, 63, 10, 4, C.INK, 953)
    local tw = text('ARMORY', 86, 50, 34, C.TEXT)
    text('FORGE', 86 + tw + 12, 50, 34, C.YELLOW)
    text(MOD.swap_only and 'Passive Swap: give any armor another passive, at the game\'s values.'
         or 'Tick passives to stack them. Click a name to edit its values.', 88, 84, 12, C.MUTED, 420)

    local by0 = H - 40                           -- key-prompt bar
    local function prompts()
        rect(0, by0, W, 40, color(6, 7, 8, 250), 951)
        rect(0, by0, W, 1, C.LINE, 952)
        local x = 22
        local hints = ui.pad_mode and { { 'A', 'Select' }, { 'B', 'Back' }, { 'LB/RB', 'Tabs' }, { 'X', 'Undo' },
                                        not ui.adding and not ui.presets and not ui.settings and { 'Y', 'Tick' } or false }
                      or { { hotkey(), 'Close' }, swap_key() ~= 'OFF' and { swap_key(), 'Swap loadout' } or false,
                           { 'CTRL+Z', 'Undo' } }
        for _, p in ipairs(hints) do
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
    -- armor tabs share what the other tabs and "Remove this stack" leave; long names are cut
    local fixed = 0
    for _, c in ipairs({ '+ Armor', 'Presets', 'Keys' }) do fixed = fixed + math.min(230, measure(up(c), 15) + 30) + 6 end
    local room = W - 22 - (measure('CLICK AGAIN TO REMOVE', 13) + 28 + 12) - 22 - fixed
    local count = #LOADOUT.profiles
    local each_tab = math.max(60, math.min(230, room / math.max(1, count) - 6))
    -- more stacks than fit: < > arrows scroll the row (the active tab is always shown)
    local shown, first = count, 0
    if count * (each_tab + 6) - 6 > room + 1 then
        shown = math.max(1, math.floor((room - 2 * 30) / (each_tab + 6)))
        first = ui.tab_first or 0
        if ui.tab ~= ui.tab_seen then             -- the tab changed: bring it into view
            ui.tab_seen = ui.tab
            if ui.tab <= first then first = ui.tab - 1 elseif ui.tab > first + shown then first = ui.tab - shown end
        end
        first = math.max(0, math.min(count - shown, first))
        ui.tab_first = first
        local function arrow(key, dir, on)
            local hv = on and ui.hover == key
            rect(x, 108, 24, 40, hv and C.ROW_HI or C.BG, 951)
            border(x, 108, 24, 40, on and (hv and C.TEXT or C.LINE2) or C.LINE, 952)
            text(dir, x + 12, 118, 16, on and (hv and C.YELLOW or C.TEXT) or C.LINE2, nil, 'center')
            region(key, x, 108, 24, 40, on)
            x = x + 30
        end
        arrow('tabs:prev', '<', first > 0)
        for n = first + 1, first + shown do
            x = x + tab('tab:' .. n, CAT[LOADOUT.profiles[n].perk].name, x, n == ui.tab and not ui.adding and not ui.presets and not ui.settings, nil, n, each_tab) + 6
        end
        arrow('tabs:next', '>', first + shown < count)
    else
        ui.tab_first = 0
        for n, prof in ipairs(LOADOUT.profiles) do
            x = x + tab('tab:' .. n, CAT[prof.perk].name, x, n == ui.tab and not ui.adding and not ui.presets and not ui.settings, nil, n, each_tab) + 6
        end
    end
    x = x + tab('add', '+ Armor', x, ui.adding, C.YELLOW) + 6
    x = x + tab('presets', 'Presets', x, ui.presets, C.YELLOW) + 6
    tab('settings', 'Keys', x, ui.settings, C.MUTED)
    if p and not ui.adding and not ui.presets and not ui.settings then
        -- a real button (players missed the old small text): click, then click again to confirm
        local sure = ui.confirm and ui.confirm.kind == 'remove'
        local cap = sure and 'Click again to remove' or 'Remove armor'
        local rbw = measure(up(cap), 13) + 28
        button('remove', cap, W - 22 - rbw, 112, rbw, 32, true, false, C.BAD)
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
    local bar = { w = 0 }            -- width the scroll bar takes from the list's rows
    local function list_row(key, y, name, chosen, name_c)
        if chosen then rect(LX + 1, y, LW - 2 - bar.w, RH - 1, C.ROW_HI, 951); rect(LX + 1, y, 3, RH - 1, C.YELLOW, 952)
        elseif ui.hover == key then rect(LX + 1, y, LW - 2 - bar.w, RH - 1, C.ROW, 951) end
        text(name, IX + 4, y + 5, 14, name_c or (chosen and C.TEXT or C.MUTED), IW - 12 - bar.w)
        region(key, LX + 1, y, LW - 2 - bar.w, RH - 1)
    end
    -- A list longer than its box (y0..y1) scrolls: mouse wheel over the left column,
    -- PageUp / PageDown, or the bar on its right (arrows, and the track pages).
    -- Returns the first row to draw (0-based) and how many rows fit.
    local function scroller(id, y0, y1, count)
        local fit = math.max(1, math.floor((y1 - y0) / RH))
        local most = math.max(0, count - fit)
        local off = math.max(0, math.min(most, ui.scroll[id] or 0))
        ui.scroll[id] = off
        bar.w = 0
        if most == 0 then return 0, count end
        bar.w = 16
        ui.scrolling = { id = id, max = most, page = math.max(1, fit - 1),
                         x = px(ox + LX * s), y = px(height - oy - y1 * s), w = px(LW * s), h = px((y1 - y0) * s) }
        local bx, bw, h = LX + LW - 15, 12, fit * RH
        rect(bx, y0, bw, h, C.FIELD, 951)
        -- arrows: small stepped triangles
        for _, a in ipairs({ { 'scroll:up', y0, 1 }, { 'scroll:down', y0 + h - 14, -1 } }) do
            local on = ui.hover == a[1]
            local cy = a[2] + (a[3] > 0 and 4 or 9)
            for r = 0, 2 do rect(bx + 5 - r, cy + r * 2 * a[3], 2 + r * 2, 2, on and C.YELLOW or C.MUTED, 953) end
            region(a[1], bx - 2, a[2], bw + 3, 14)
        end
        local ty, th = y0 + 16, h - 32
        local tsz = math.max(24, th * fit / count)
        local tpos = ty + (th - tsz) * off / most
        if tpos > ty then region('scroll:pgup', bx - 2, ty, bw + 3, tpos - ty) end
        if tpos + tsz < ty + th then region('scroll:pgdn', bx - 2, tpos + tsz, bw + 3, ty + th - tpos - tsz) end
        rect(bx + 2, tpos, bw - 4, tsz, ui.hover and ui.hover:find('^scroll:') and C.YELLOW or C.LINE2, 952)
        return off, fit
    end
    -- the search field above a passive list (click it or Ctrl+F, then type; Esc clears)
    local function search_box(y)
        local on, q = ui.search_on, ui.search or ''
        rect(IX, y, IW, 26, C.FIELD, 951)
        border(IX, y, IW, 26, on and C.YELLOW or (ui.hover == 'search' and C.TEXT or C.LINE2), 952)
        local cw = q ~= '' and (measure('CLEAR', 10) + 16) or 0
        text(q ~= '' and (up(q) .. (on and '_' or '')) or (on and '_' or 'SEARCH PASSIVES OR EFFECTS  (CTRL+F)'),
             IX + 10, y + 7, 12, q ~= '' and C.TEXT or C.DIM, IW - 20 - cw)
        region('search', IX, y, IW - cw, 26)
        if q ~= '' then
            text('CLEAR', IX + IW - 8, y + 8, 10, ui.hover == 'search:clear' and C.YELLOW or C.MUTED, nil, 'right')
            region('search:clear', IX + IW - cw, y, cw, 26)
        end
        return y + 32
    end
    -- text over up to `lines` lines of `width`, cut with '..' if it doesn't fit; returns the next y
    local function wrap(value, x, y, size, c, width, lines)
        local line, n = '', 0
        local words = {}
        for w in value:gmatch('%S+') do words[#words + 1] = w end
        local i = 1
        while i <= #words do
            local try = line == '' and words[i] or (line .. ' ' .. words[i])
            if line ~= '' and measure(try, size) > width then
                n = n + 1
                if n == lines then text(line .. ' ..', x, y, size, c, width); return y + size + 6 end
                text(line, x, y, size, c, width)
                y, line = y + size + 6, ''
            else
                line, i = try, i + 1
            end
        end
        if line ~= '' then text(line, x, y, size, c, width); y = y + size + 6 end
        return y
    end
    local function no_match(y, n)
        if n == 0 then text('Nothing matches "' .. ui.search .. '".', IX + 4, y + 4, 13, C.DIM, IW - 8) end
    end

    -- ============================================================ Presets tab
    if ui.presets then
        local list = PP.entries()
        head(IX, TOP + 14, 'Loadouts', 'Presets', IW)
        local y = TOP + 64
        if not MOD.swap_only then label('Standard issue', IX, y); y = y + 18 end
        for _, e in ipairs(list) do
            if e.kind ~= 'user' then
                list_row('pre:' .. e.kind .. ':' .. e.i, y, e.name, ui.psel and ui.psel.kind == e.kind and ui.psel.i == e.i)
                y = y + RH
            end
        end
        if not MOD.swap_only then y = y + 12 end
        label('Your loadouts', IX, y)
        text(#PP.user .. ' SAVED', IX + IW, y, 11, #PP.user > 0 and C.YELLOW or C.DIM, nil, 'right')
        y = y + 18
        local mine = {}
        for _, e in ipairs(list) do if e.kind == 'user' then mine[#mine + 1] = e end end
        local first, fit = scroller('user', y, BOT - 54, #mine)
        for k = first + 1, math.min(#mine, first + fit) do
            local e = mine[k]
            local key = 'pre:user:' .. e.i
            local chosen = ui.psel and ui.psel.kind == 'user' and ui.psel.i == e.i
            if ui.naming and ui.naming.i == e.i then
                list_row(key, y, ui.naming.text .. '_', chosen, ui.naming.fresh and C.MUTED or C.YELLOW)
            else
                list_row(key, y, e.name, chosen)
            end
            y = y + RH
        end
        bar.w = 0
        if #PP.user == 0 then text(MOD.swap_only and 'None yet. Save your current swaps.' or 'None yet. Save the current stack.', IX + 4, y + 4, 13, C.DIM, IW - 8); y = y + 26 end
        button('psave', MOD.swap_only and '+ Save current swaps' or '+ Save current stack', IX, math.min(y + 10, BOT - 44), IW, 32, true, true)

        local entry = nil
        for _, e in ipairs(list) do if ui.psel and e.kind == ui.psel.kind and e.i == ui.psel.i then entry = e end end
        if not entry then
            head(RX, TOP + 14, 'Loadouts', 'Choose a preset', RIW)
            text('Pick one on the left to see what it stacks, then load it.', RX, TOP + 70, 14, C.MUTED, RIW)
            text(MOD.swap_only and 'Save your own with "+ Save current swaps".' or 'Save your own with "+ Save current stack".', RX, TOP + 92, 14, C.MUTED, RIW)
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
                text(MOD.swap_only and (sm.swap and ('has ' .. sm.swap) or 'its own passive') or
                     (#sm.names .. ' passive(s), ' .. sm.tweaks .. ' value(s) changed, ' ..
                      (sm.policy == 'strongest' and 'strongest only' or 'stack all')), RX, y2 + 30, 13, C.MUTED, RIW)
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
            else text(MOD.swap_only and 'Loading replaces your current swaps (Undo brings them back).'
                      or 'Loading replaces your current stacks (Undo brings them back).', RX, by + 46, 12, C.DIM, RIW) end
        end

    -- ============================================================ Keys (settings)
    elseif ui.settings then
        head(IX, TOP + 14, 'Settings', 'Keys', IW)
        local each, gap = (IW - 3 * 8) / 4, 8
        local function key_grid(which, current, other, y, with_off)
            local keys = {}
            for k = 1, 12 do keys[#keys + 1] = 'F' .. k end
            if with_off then keys[#keys + 1] = 'OFF' end
            for i, k in ipairs(keys) do
                local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
                local on = k == current
                -- the other key's F-key can't be taken (the panel key wins over quick-swap)
                local free = on or k ~= other
                button('key:' .. which .. ':' .. k, k, IX + col * (each + gap), y + row * 38, each, 30, free, on)
            end
            return y + math.ceil(#keys / 4) * 38
        end
        local y = TOP + 64
        label('Open / close this panel', IX, y, nil, IW)
        y = key_grid('hotkey', hotkey(), nil, y + 20, false) + 14
        label('Quick-swap loadouts', IX, y, nil, IW)
        y = key_grid('swap_hotkey', swap_key(), hotkey(), y + 20, true) + 6
        text('Picking the quick-swap key as the panel key turns quick-swap off.', IX, y, 12, C.DIM, IW)

        head(RX, TOP + 14, 'Settings', 'Panel', RIW)
        local ry = TOP + 70
        text('Size: ' .. string.format('%d%%', ui_scale() * 100 + 0.5) .. '  (Ctrl + / Ctrl -, or [-] [+] at the top)', RX, ry, 14, C.TEXT, RIW)
        local bx = RX + button('zoom:-', '- Smaller', RX, ry + 26, nil, 32, ui_scale() > 0.8) + 8
        bx = bx + button('zoom:+', '+ Bigger', bx, ry + 26, nil, 32, ui_scale() < 1.5) + 8
        button('zoom:0', 'Reset size and position', bx, ry + 26, nil, 32, ui_scale() ~= 1 or ui.pos ~= nil)
        ry = ry + 84
        text('Move the panel: drag its top strip.', RX, ry, 14, C.TEXT, RIW)
        ry = ry + 40
        rect(RX, ry, RIW, 1, C.LINE, 951)
        label('Fixed keys', RX, ry + 14, nil, RIW)
        local fixed = { { 'CTRL+Z', 'Undo' }, { 'CTRL+F', 'Search passives' }, { 'CTRL +/-', 'Panel size' },
                        { 'CTRL+0', 'Reset size and position' }, { 'PGUP/PGDN', 'Scroll a long list' } }
        ry = ry + 38
        for _, f in ipairs(fixed) do
            local kw = keycap(f[1], RX, ry)
            text(up(f[2]), RX + kw + 12, ry + 4, 12, C.TEXT, RIW - kw - 12)
            ry = ry + 32
        end
        ry = ry + 10
        text('SHODAN Stat Editor uses F8 by default: pick another key here if you run both.', RX, ry, 12, C.DIM, RIW)
        text('Keys are saved with your loadout (hotkey / swap_hotkey in loadout.ini).', RX, ry + 18, 12, C.DIM, RIW)
        rect(RX, BOT - 100, RIW, 1, C.LINE, 951)
        label('Something wrong?', RX, BOT - 88, nil, RIW)
        text('Copy a report and paste it in your bug report on the mod page.', RX, BOT - 68, 12, C.DIM, RIW)
        button('report', 'Copy problem report', RX, BOT - 44, nil, 32, true)

    -- ============================================================ + Armor
    elseif ui.adding then
        head(IX, TOP + 14, MOD.swap_only and 'New swap' or 'New stack', 'Choose armor passive', IW)
        local used = {}
        for _, prof in ipairs(LOADOUT.profiles) do used[prof.perk] = true end
        local y = search_box(TOP + 58)
        local free = {}
        for _, c in ipairs(CAT_LIST) do if not used[c.id] and PP.match(c) then free[#free + 1] = c end end
        no_match(y, #free)
        local first, fit = scroller('add', y, BOT - 54, #free)
        for k = first + 1, math.min(#free, first + fit) do
            local c = free[k]
            list_row('addpick:' .. c.id, y, up(c.name), ui.hover == 'addpick:' .. c.id)
            y = y + RH
        end
        bar.w = 0
        button('addcancel', 'Cancel', IX, BOT - 44, nil, 32, true)
        local hov = ui.hover and tonumber(ui.hover:match('^addpick:(%d+)$'))
        local hinf = hov and PP.info(hov)
        if hinf then
            head(RX, TOP + 14, MOD.swap_only and 'New swap' or 'New stack', CAT[hov].name, RIW)
            local hy = wrap(hinf.desc, RX, TOP + 70, 14, C.TEXT, RIW, 3) + 10
            label('Armors with this passive', RX, hy, nil, RIW)
            hy = hy + 20
            for i, a in ipairs(hinf.armors) do
                if hy > BOT - 90 then text('+' .. (#hinf.armors - i + 1) .. ' more', RX, hy, 12, C.DIM, RIW); break end
                text(a, RX + 8, hy, 13, C.MUTED, RIW - 8)
                hy = hy + 20
            end
            text(MOD.swap_only and 'Pick it, then choose the passive these armors should have.'
                 or 'Pick it, then wear any of these armors to get the stack.', RX, BOT - 60, 12, C.DIM, RIW)
        elseif MOD.swap_only then
            head(RX, TOP + 14, 'New swap', 'Pick your armor', RIW)
            text('Pick the passive of the armor you wear on the left,', RX, TOP + 70, 14, C.MUTED, RIW)
            text('then choose which passive it should have instead.', RX, TOP + 92, 14, C.MUTED, RIW)
            text('Example: Med-Kit armor with Siege-Ready.', RX, TOP + 122, 13, C.DIM, RIW)
        else
        head(RX, TOP + 14, 'New stack', 'A second stack', RIW)
        text('Each armor passive can carry its own stack. Pick one on the left,', RX, TOP + 70, 14, C.MUTED, RIW)
        text('then wear any armor that has that passive to get the stack.', RX, TOP + 92, 14, C.MUTED, RIW)
        text('Example: Med-Kit armor for a tank build, Siege-Ready armor for a gunner build.', RX, TOP + 122, 13, C.DIM, RIW)
        end
        if not hinf then
            text('Point at a passive to see what it does and which armors have it.', RX, TOP + 160, 13, C.DIM, RIW)
            text('Picked the wrong one? Open its tab and press REMOVE ARMOR.', RX, TOP + 184, 13, C.DIM, RIW)
        end

    elseif not p then
        head(IX, TOP + 14, 'No armor forged yet', 'Empty', IW)
        text(MOD.swap_only and 'Nothing is swapped.' or 'Nothing is stacked.', IX, TOP + 70, 14, C.MUTED, IW)
        head(RX, TOP + 14, 'How it works', 'Forge your armor', RIW)
        text('Pick the armor passive you wear (for example Med-Kit),', RX, TOP + 72, 15, C.TEXT, RIW)
        if MOD.swap_only then
            text('then choose which of the game\'s passives it should', RX, TOP + 94, 15, C.TEXT, RIW)
            text('have instead. The values are the game\'s own.', RX, TOP + 116, 15, C.TEXT, RIW)
        else
        text('then tick any of the 31 passives to stack onto it and', RX, TOP + 94, 15, C.TEXT, RIW)
        text('change their values. Everything applies at once.', RX, TOP + 116, 15, C.TEXT, RIW)
        end
        local bx = RX
        bx = bx + button('add', '+ Armor', bx, TOP + 152, nil, 36, true, true) + 8
        button('presets', 'Presets', bx, TOP + 152, nil, 36, true)

    -- ============================================================ Passive Swap edition
    -- One passive per armor, chosen from the game's own; its values are the game's.
    elseif MOD.swap_only then
        local cur = (p.swap and p.swap ~= p.perk and CAT[p.swap]) and p.swap or nil
        head(IX, TOP + 14, 'Armor ' .. ui.tab .. ' / ' .. #LOADOUT.profiles, 'Swap passive', IW)
        local y = search_box(TOP + 58)
        local opts = { { id = 0, name = 'Original: ' .. CAT[p.perk].name } }
        for _, c in ipairs(CAT_LIST) do if c.id ~= p.perk and PP.match(c) then opts[#opts + 1] = { id = c.id, name = c.name } end end
        local first, fit = scroller('swap', y, BOT - 6, #opts)
        local rw = LW - 2 - bar.w
        for k = first + 1, math.min(#opts, first + fit) do
            local o = opts[k]
            local on = (o.id == 0 and not cur) or o.id == cur
            local key = 'swap:' .. o.id
            if on then rect(LX + 1, y, rw, RH - 1, C.ROW_HI, 951); rect(LX + 1, y, 3, RH - 1, C.YELLOW, 952)
            elseif ui.hover == key then rect(LX + 1, y, rw, RH - 1, C.ROW, 951) end
            border(IX + 2, y + 3, 16, 16, (on or ui.hover == key) and C.YELLOW or C.MUTED, 952)
            if on then rect(IX + 6, y + 7, 8, 8, C.YELLOW, 953) end
            text(up(o.name), IX + 28, y + 5, 13, on and C.YELLOW or C.MUTED, IW - 34 - bar.w)
            region(key, LX + 1, y, rw, RH - 1)
            y = y + RH
        end
        bar.w = 0
        -- right: the passive this armor has now, at the game's values
        local shown = CAT[cur or p.perk]
        head(RX, TOP + 14, cur and 'Swapped in' or 'Original passive', shown.name, RIW)
        text(cur and ('Every ' .. CAT[p.perk].name .. ' armor has ' .. shown.name .. ' instead of its own passive.')
             or 'This armor keeps its own passive. Pick another on the left to swap it.', RX, TOP + 52, 13, C.MUTED, RIW)
        local y2 = TOP + 76
        local sinf = PP.info(shown.id)
        if sinf then y2 = wrap(sinf.desc, RX, y2, 13, C.TEXT, RIW, 2) end
        local binf = PP.info(p.perk)
        if binf and #binf.armors > 0 then
            y2 = wrap('APPLIES TO: ' .. table.concat(binf.armors, ', '), RX, y2, 11, C.MUTED, RIW, 2)
        end
        y2 = y2 + 6
        for _, e in ipairs(shown.effects) do
            if y2 > BOT - 190 then break end
            rect(RX, y2, RIW, 48, C.ROW, 950)
            rect(RX, y2, 3, 48, C.LINE2, 951)
            text(label_of(e), RX + 14, y2 + 8, 15, C.TEXT, RIW - 170)
            text(PP.WHAT[PP.unit(e)], RX + 14, y2 + 28, 12, C.DIM, RIW - 170)
            text(PP.text(e, e.def), RX + RIW - 16, y2 + 15, 16, C.TEXT, 140, 'right')
            y2 = y2 + 54
        end
        local by = BOT - 130
        rect(RX, by - 12, RIW, 1, C.LINE, 951)
        label('Game values', RX, by, nil, RIW)
        text('The passive is copied from the game\'s own data. One passive per armor, no stacking.', RX, by + 18, 13, C.MUTED, RIW)
        if not sites_by_perk[p.perk] then
            text('This armor passive was not found in the game\'s data yet.', RX, by + 42, 13, C.BAD, RIW)
        elseif sites_by_perk[p.perk][1].foreign then
            text('Another mod already changed this passive\'s data; Armory Forge leaves it alone.', RX, by + 42, 13, C.BAD, RIW)
        elseif cur and not sites_by_perk[cur] then
            text('Waiting for ' .. CAT[cur].name .. ' in the game\'s data...', RX, by + 42, 13, C.YELLOW, RIW)
        else
            rect(RX, by + 45, 7, 7, C.GOOD, 952)
            text(cur and ('Active: ' .. CAT[p.perk].name .. ' armor has ' .. CAT[cur].name) or 'Active: the game\'s own passive',
                 RX + 14, by + 42, 13, C.TEXT, RIW - 14)
        end
        local ay, each = BOT - 50, (RIW - 8) / 2
        local ax = RX + button('undo', #ui.history > 0 and ('Undo (' .. #ui.history .. ')') or 'Undo', RX, ay, each, 34, #ui.history > 0) + 8
        button('clear', 'Back to original', ax, ay, each, 34, cur ~= nil)

    -- ============================================================ an armor stack
    else
        local n_on = 0
        for _ in pairs(p.enabled) do n_on = n_on + 1 end
        head(IX, TOP + 14, 'Armor stack ' .. ui.tab .. ' / ' .. #LOADOUT.profiles, 'Choose passives', IW - 70)
        text(n_on .. ' ON', IX + IW, TOP + 14, 11, n_on > 0 and C.YELLOW or C.DIM, nil, 'right')
        local y = search_box(TOP + 58)
        -- the stack's combined effect
        local sum_key = 'sel:summary'
        if ui.sel == 'summary' then rect(LX + 1, y, LW - 2, RH, C.ROW_HI, 951); rect(LX + 1, y, 3, RH, C.YELLOW, 952)
        elseif ui.hover == sum_key then rect(LX + 1, y, LW - 2, RH, C.ROW, 951) end
        local sw0 = measure('SUM', 10) + 10
        border(IX + 2, y + 5, sw0, 14, C.YELLOW, 952)
        text('SUM', IX + 2 + sw0 / 2, y + 7, 10, C.YELLOW, nil, 'center')
        text('STACK SUMMARY', IX + sw0 + 12, y + 5, 14, ui.sel == 'summary' and C.TEXT or C.MUTED, IW - sw0 - 16)
        region(sum_key, LX + 1, y, LW - 2, RH)
        y = y + RH
        -- armor weight (speed, stamina, armor rating)
        local wkey = 'sel:weight'
        if ui.sel == 'weight' then rect(LX + 1, y, LW - 2, RH, C.ROW_HI, 951); rect(LX + 1, y, 3, RH, C.YELLOW, 952)
        elseif ui.hover == wkey then rect(LX + 1, y, LW - 2, RH, C.ROW, 951) end
        border(IX + 2, y + 5, sw0, 14, p.weight and C.YELLOW or C.MUTED, 952)
        text('WGT', IX + 2 + sw0 / 2, y + 7, 10, p.weight and C.YELLOW or C.MUTED, nil, 'center')
        text('ARMOR WEIGHT: ' .. (p.weight and up(WEIGHTS[p.weight]) or 'GAME'), IX + sw0 + 12, y + 5, 14,
             ui.sel == 'weight' and C.TEXT or p.weight and C.YELLOW or C.MUTED, IW - sw0 - 16)
        region(wkey, LX + 1, y, LW - 2, RH)
        y = y + RH
        local base_key = 'sel:' .. p.perk
        if ui.sel == p.perk then rect(LX + 1, y, LW - 2, RH, C.ROW_HI, 951); rect(LX + 1, y, 3, RH, C.YELLOW, 952)
        elseif ui.hover == base_key then rect(LX + 1, y, LW - 2, RH, C.ROW, 951) end
        local bw = measure('BASE', 10) + 10
        rect(IX + 2, y + 5, bw, 14, C.YELLOW, 952)
        text('BASE', IX + 2 + bw / 2, y + 7, 10, C.INK, nil, 'center')
        text(up(CAT[p.perk].name), IX + bw + 12, y + 5, 14, C.TEXT, IW - bw - 16)
        region(base_key, LX + 1, y, LW - 2, RH)
        y = y + RH + 4
        local rest = {}
        for _, c in ipairs(CAT_LIST) do if c.id ~= p.perk and PP.match(c) then rest[#rest + 1] = c end end
        no_match(y, #rest)
        local first, fit = scroller('stack', y, BOT - 6, #rest)
        local rw = LW - 2 - bar.w
        for k = first + 1, math.min(#rest, first + fit) do
            local c = rest[k]
            local on = p.enabled[c.id] == true
            local key = 'sel:' .. c.id
            if ui.sel == c.id then rect(LX + 1, y, rw, RH - 1, C.ROW_HI, 951); rect(LX + 1, y, 3, RH - 1, C.YELLOW, 952)
            elseif ui.hover == key then rect(LX + 1, y, rw, RH - 1, C.ROW, 951) end
            region(key, IX + 26, y, rw - (IX + 26 - LX), RH - 1)
            checkbox('tick:' .. c.id, IX + 2, y + 3, on)
            local tweaked = false
            for tk in pairs(p.tweaks) do if tk:match('^' .. c.id .. '%.') then tweaked = true break end end
            text(up(c.name), IX + 28, y + 5, 13, on and C.YELLOW or C.MUTED, IW - 44 - bar.w)
            if tweaked and on then rect(IX + IW - 6 - bar.w, y + 9, 6, 6, C.TEXT, 952) end
            y = y + RH
        end
        bar.w = 0

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
            local y2 = TOP + 80
            local inf = PP.info(sel.id)
            if inf then y2 = wrap(inf.desc, RX, y2, 13, C.TEXT, RIW, 2) end
            if is_base and inf and #inf.armors > 0 then
                y2 = wrap('WEAR ANY OF: ' .. table.concat(inf.armors, ', '), RX, y2, 11, C.MUTED, RIW, 2)
            end
            y2 = y2 + 6
            for n, e in ipairs(sel.effects) do
                local v = value_of(p, sel.id, e)
                local tweaked = v ~= e.def
                local u = PP.unit(e)
                rect(RX, y2, RIW, 60, C.ROW, 950)
                rect(RX, y2, 3, 60, tweaked and C.YELLOW or C.LINE2, 951)
                local lw = RIW - controls - 26
                text(label_of(e) .. (e.hint:find('%?') and ' ?' or ''), RX + 14, y2 + 10, 15, C.TEXT, lw)
                text(PP.WHAT[u] .. (e.hint:find('%?') and ' (name is a guess)' or ''), RX + 14, y2 + 30, 12, C.DIM, lw)
                local tag, tcol = PP.test_tag(e)
                text(tag, RX + 14, y2 + 46, 9, C[tcol], lw)
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
        elseif ui.sel == 'weight' then
            head(RX, TOP + 14, 'Armor weight', CAT[p.perk].name .. ' armor', RIW)
            local y2 = wrap('An armor\'s weight class sets its speed, stamina regen and base armor rating. Pick one and the armor keeps its look.',
                            RX, TOP + 58, 13, C.MUTED, RIW, 2) + 6
            local each = (RIW - 3 * 8) / 4
            local bx = RX
            for _, w in ipairs({ { 'game', 'Game' }, { 'light', 'Light' }, { 'medium', 'Medium' }, { 'heavy', 'Heavy' } }) do
                local on = (p.weight == WEIGHTS[w[1]]) or (w[1] == 'game' and p.weight == nil)
                bx = bx + button('weight:' .. w[1], w[2], bx, y2, each, 34, true, on) + 8
            end
            y2 = y2 + 50
            label('What each weight gives (game values)', RX, y2, nil, RIW)
            y2 = y2 + 20
            for _, r in ipairs(PP.WEIGHT_STATS) do
                local on = p.weight == WEIGHTS[r[1]:lower()]
                rect(RX, y2, RIW, 26, on and C.ROW_HI or C.ROW, 950)
                text(up(r[1]), RX + 10, y2 + 6, 13, on and C.YELLOW or C.TEXT, 90)
                text('ARMOR ' .. r[2] .. '    SPEED ' .. r[3] .. '    STAMINA REGEN ' .. r[4], RX + 110, y2 + 6, 13,
                     on and C.YELLOW or C.MUTED, RIW - 120)
                y2 = y2 + 30
            end
            y2 = y2 + 8
            local found = KITS.count(p.perk)
            if found == 0 then
                y2 = wrap('The armor records for ' .. CAT[p.perk].name .. ' were not found yet, so the weight can\'t apply. Load into your ship or a mission.',
                          RX, y2, 13, C.BAD, RIW, 2)
            else
                y2 = wrap('Applies to all ' .. found .. ' armor(s) with ' .. CAT[p.perk].name .. '. Passives on the armor add to it (e.g. Extra Padding +50 armor).',
                          RX, y2, 13, C.TEXT, RIW, 2)
            end
            local inf = PP.info(p.perk)
            if inf and #inf.armors > 0 then
                y2 = wrap('WEAR ANY OF: ' .. table.concat(inf.armors, ', '), RX, y2 + 4, 11, C.MUTED, RIW, 2)
            end
        elseif ui.sel == 'summary' then
            local list = PP.summary_rows(p)
            head(RX, TOP + 14, 'Stack summary', CAT[p.perk].name .. ' armor', RIW)
            local y2 = wrap('Everything on this armor together: its own passive plus ' .. n_on .. ' stacked. An estimate: how the game combines stacked values is not confirmed yet.',
                            RX, TOP + 54, 12, C.MUTED, RIW, 2)
            local inf = PP.info(p.perk)
            if inf and #inf.armors > 0 then
                y2 = wrap('WEAR ANY OF: ' .. table.concat(inf.armors, ', '), RX, y2, 11, C.MUTED, RIW, 2)
            end
            y2 = y2 + 8
            local colw, lh = (RIW - 16) / 2, 24
            local rows_fit = math.max(1, math.floor((BOT - 190 - y2) / lh))
            local shown = math.min(#list, rows_fit * 2)
            if #list > shown then shown = shown - 1 end
            for k = 1, shown do
                local g = list[k]
                local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
                local cx, cy = RX + col * (colw + 16), y2 + row * lh
                rect(cx, cy, colw, lh - 3, C.ROW, 950)
                local vt = PP.text(g.e, g.v)
                local vw = measure(vt, 13)
                text(vt, cx + colw - 8, cy + 5, 13, C.YELLOW, 90, 'right')
                text(label_of(g.e) .. (g.n > 1 and ('  x' .. g.n) or ''), cx + 8, cy + 5, 12, C.TEXT, colw - math.min(90, vw) - 24)
            end
            if #list > shown then
                local k = shown + 1
                local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
                text('+' .. (#list - shown) .. ' MORE', RX + col * (colw + 16) + 8, y2 + row * lh + 6, 11, C.DIM, colw - 16)
            end
            if #list == 0 then text('Nothing stacked yet: tick passives on the left.', RX, y2, 13, C.DIM, RIW) end
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
    -- controller focus: a yellow box around the focused button
    if ui.pad_mode and ui.focus then
        for _, r in ipairs(regions) do
            if r.key == ui.focus then
                local t = math.max(2, px(2 * s))
                for _, e in ipairs({ { r.x - t, r.y - t, r.w + 2 * t, t }, { r.x - t, r.y + r.h, r.w + 2 * t, t },
                                     { r.x - t, r.y, t, r.h }, { r.x + r.w, r.y, t, r.h } }) do
                    Gui.rect(gui, Vector3(e[1], e[2], 957), Vector2(e[3], e[4]), C.YELLOW)
                end
                break
            end
        end
    end
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
    if ui.search_on and kind ~= 'search' then ui.search_on = false end
    local p = current()
    local n = tonumber(arg)
    if kind == 'tab' and n then ui.tab, ui.sel, ui.adding, ui.presets, ui.settings = n, nil, false, false, false
    elseif kind == 'add' then ui.adding, ui.presets, ui.settings = not ui.adding, false, false
    elseif kind == 'addcancel' then ui.adding = false
    elseif kind == 'presets' then ui.presets, ui.adding, ui.settings = not ui.presets, false, false; PP.load_user()
    elseif kind == 'search' then
        if arg == 'clear' then PP.set_search('', false) else PP.set_search(ui.search, true) end
    elseif kind == 'settings' then ui.settings, ui.adding, ui.presets = not ui.settings, false, false
    elseif kind == 'key' then
        local which, k = arg:match('^([%w_]+):(%w+)$')
        PP.set_key(which, k)
    elseif kind == 'addpick' and n then
        LOADOUT.profiles[#LOADOUT.profiles + 1] = { perk = n, conflicts = 'stack', enabled = {}, tweaks = {}, raw = {}, raw_stats = {} }
        ui.tab, ui.sel, ui.adding = #LOADOUT.profiles, nil, false
        changed(n, (MOD.swap_only and 'Added ' or 'Added a stack for ') .. CAT[n].name .. ' armor')
    elseif kind == 'remove' and p then
        if confirm('remove') then
            table.remove(LOADOUT.profiles, ui.tab)
            ui.tab, ui.sel = math.max(1, ui.tab - 1), nil
            changed(p.perk, 'Removed the ' .. CAT[p.perk].name .. ' stack (the game\'s own values are back)')
        end
    elseif kind == 'sel' and (arg == 'summary' or arg == 'weight') then ui.sel = arg; ui.value = nil
    elseif kind == 'sel' and n then ui.sel = n; ui.value = nil
    elseif kind == 'tick' and n and p then toggle(p, n)
    elseif kind == 'policy' and p then p.conflicts = arg; changed(p.perk)
    elseif kind == 'swap' and n and p and MOD.swap_only then
        local pick = (n ~= 0 and n ~= p.perk and CAT[n]) and n or nil
        if pick ~= p.swap then
            p.swap = pick
            changed(p.perk, pick and (CAT[p.perk].name .. ' armor now has ' .. CAT[pick].name) or (CAT[p.perk].name .. ' armor has its own passive again'))
        end
    elseif kind == 'clear' and p and MOD.swap_only then
        if p.swap then p.swap = nil; changed(p.perk, CAT[p.perk].name .. ' armor has its own passive again') end
    elseif kind == 'clear' and p then
        if confirm('clear') then p.enabled, p.tweaks = {}, {}; changed(p.perk, 'Turned everything off on this armor') end
    elseif kind == 'zoom' then PP.zoom((arg == '+' and 1) or (arg == '0' and 0) or -1)
    elseif kind == 'scroll' then
        local page = ui.scrolling and ui.scrolling.page or 1
        PP.scroll((arg == 'up' and -1) or (arg == 'down' and 1) or (arg == 'pgup' and -page) or page)
    elseif kind == 'drag' then return             -- a click on the handle without moving
    elseif kind == 'undo' then PP.undo()
    elseif kind == 'report' then PP.copy_report()
    elseif kind == 'tabs' then ui.tab_first = (ui.tab_first or 0) + (arg == 'prev' and -1 or 1)
    elseif kind == 'weight' and p and not MOD.swap_only then
        local w = WEIGHTS[arg]
        if p.weight ~= w then
            p.weight = w
            changed(p.perk, CAT[p.perk].name .. ' armors: ' .. (w and (arg .. ' weight') or 'their own weight'))
        end
    elseif kind == 'copy' and not MOD.swap_only then PP.copy_code()
    elseif kind == 'paste' and not MOD.swap_only then PP.paste_code()
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
    if ui.search_on then
        if pressed('Escape', VK.Escape, now) then PP.set_search('', false); return end
        if pressed('Enter', VK.Enter, now) then PP.set_search(ui.search, false); return end
        if pressed('Backspace', VK.Backspace, now) then PP.set_search(ui.search:sub(1, -2), true) end
        if not input.key_down(VK.Ctrl) then          -- with Ctrl held, the shortcuts below run instead
            for _, k in ipairs(NAME_KEYS) do
                if pressed('N' .. k[1], k[1], now) and #ui.search < 24 then PP.set_search(ui.search .. k[2], true) end
            end
            return
        end
        for _, k in ipairs(NAME_KEYS) do         -- keys pressed with Ctrl aren't typed when Ctrl goes first
            if input.key_down(k[1]) then held['N' .. k[1]] = { next = math.huge } end
        end
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
    if input.key_down(VK.Ctrl) and pressed('F', 0x46, now) and not ui.presets and not ui.settings
       and (ui.adding or current()) and not ui.search_on then
        PP.set_search(ui.search, true)
        held['N' .. 0x46] = { next = math.huge }       -- the F of Ctrl+F is not typed into the field
    end
    if ui.scrolling then
        if pressed('PgUp', VK.PageUp, now) then PP.scroll(-ui.scrolling.page) end
        if pressed('PgDn', VK.PageDown, now) then PP.scroll(ui.scrolling.page) end
    end
    if input.key_down(VK.Ctrl) then
        -- Ctrl + / Ctrl - / Ctrl 0: panel size (main keyboard or numpad)
        if pressed('ZP', 0xBB, now) or pressed('ZA', 0x6B, now) then PP.zoom(1) end
        if pressed('ZM', 0xBD, now) or pressed('ZS', 0x6D, now) then PP.zoom(-1) end
        if pressed('Z0', 0x30, now) or pressed('Z0n', 0x60, now) then PP.zoom(0) end
    end
end

-- mouse wheel movement this frame (+ = away from you), 0 if the engine won't say
local function wheel()
    local M = sr.Mouse
    local id = nil
    for _, name in ipairs({ 'axis_id', 'axis_index' }) do
        local f = rawget(M, name)
        if type(f) == 'function' then
            local ok, v = pcall(f, 'wheel')
            if ok and v ~= nil then id = v break end
        end
    end
    if id == nil or type(rawget(M, 'axis')) ~= 'function' then return 0 end
    local ok, v = pcall(M.axis, id)
    if not ok or v == nil then return 0 end
    local got, dy = pcall(sr.Vector3.y, v)
    if not got or type(dy) ~= 'number' then dy = type(v) == 'table' and v[2] or 0 end
    return tonumber(dy) or 0
end

local function mouse()
    local x, y, cw, ch = input.cursor()
    if not x or cw <= 0 or ch <= 0 then return end
    local width, height = sr.Gui.resolution()
    local sx, sy = x * width / cw, y * height / ch          -- screen pixels from the top left
    if PP.last_cur and (math.abs(PP.last_cur[1] - x) > 2 or math.abs(PP.last_cur[2] - y) > 2) and ui.pad_mode then
        ui.pad_mode = false                                  -- the mouse moved: it's in charge again
        ui.version = ui.version + 1
    end
    PP.last_cur = { x, y }
    local value = sr.Mouse.button(sr.Mouse.button_id('left'))
    local down = value == true or (type(value) == 'number' and value > 0)
    -- dragging the panel by its top strip: follows the cursor until the button is let go
    local d = ui.drag
    if d then
        ui.hover = 'drag'
        if down then
            local fx = math.max(0, d.x + sx - d.cx) / width
            local fy = math.max(0, d.y + sy - d.cy) / height
            if not ui.pos or math.abs(fx - ui.pos.fx) > 1e-6 or math.abs(fy - ui.pos.fy) > 1e-6 then
                ui.pos = { fx = fx, fy = fy }
                ui.version = ui.version + 1
            end
        else
            ui.drag, armed = nil, nil
            if ui.pos and ui.origin then       -- keep where it was drawn (on screen)
                ui.pos = { fx = ui.origin.x / width, fy = ui.origin.y / height }
            end
            PP.save_pos()
            ui.version = ui.version + 1
        end
        mouse_was_down = down
        return
    end
    if x < 0 or y < 0 or x >= cw or y >= ch then return end
    ui.hover = hit(sx, height - sy, true)
    local sc = ui.scrolling
    if sc and sx >= sc.x and sx < sc.x + sc.w and height - sy >= sc.y and height - sy < sc.y + sc.h then
        local dy = wheel()
        if dy ~= 0 then PP.scroll(dy > 0 and -3 or 3) end
    end
    if mouse_was_down ~= nil then
        if down and not mouse_was_down and ui.hover == 'drag' and ui.origin then
            ui.drag = { cx = sx, cy = sy, x = ui.origin.x, y = ui.origin.y }
            mouse_was_down = down
            return
        end
        if down and not mouse_was_down then armed = ui.hover end
        if not down and mouse_was_down then
            if armed and armed == ui.hover then click(armed) end
            armed = nil
        end
    end
    mouse_was_down = down
end

-- ---------------------------------------------------------------- controller
-- Back + Start opens and closes the panel. In the panel: D-pad or left stick moves a focus
-- box to the nearest button in that direction (lists scroll when you go past the end),
-- A presses it, B goes back, LB / RB switch tabs, X undoes, Y ticks the chosen passive,
-- the right stick scrolls. Using the mouse again hides the focus box.
PP.PAD = { UP = 0x0001, DOWN = 0x0002, LEFT = 0x0004, RIGHT = 0x0008, START = 0x0010, BACK = 0x0020,
           LB = 0x0100, RB = 0x0200, A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000,
           R_UP = 0x10000, R_DOWN = 0x20000 }                -- right stick, as virtual buttons
PP.pad_now, PP.pad_was, PP.pad_held = 0, 0, {}
PP.bit = rawget(_G, 'bit')
if not PP.bit then
    local ok, b = pcall(require, 'bit')
    PP.bit = ok and b or nil
end
PP.LIST_ROW = { sel = true, tick = true, addpick = true, swap = true, pre = true }

-- read the controller once per frame; sticks become D-pad / virtual buttons
function PP.pad_read()
    PP.pad_was = PP.pad_now
    local b, lx, ly, ry = nil, 0, 0, 0
    if input.pad then
        local rx
        b, lx, ly, rx, ry = input.pad()
    end
    if not b or not PP.bit then PP.pad_now = 0; return false end
    local bit, dead, P = PP.bit, 16000, PP.PAD
    if ly > dead then b = bit.bor(b, P.UP) elseif ly < -dead then b = bit.bor(b, P.DOWN) end
    if lx > dead then b = bit.bor(b, P.RIGHT) elseif lx < -dead then b = bit.bor(b, P.LEFT) end
    if ry > dead then b = bit.bor(b, P.R_UP) elseif ry < -dead then b = bit.bor(b, P.R_DOWN) end
    PP.pad_now = b
    return true
end
function PP.pad_down(mask) return PP.bit ~= nil and PP.bit.band(PP.pad_now, mask) == mask end
-- pressed this frame (not held from the last one)
function PP.pad_edge(mask) return PP.pad_down(mask) and PP.bit.band(PP.pad_was, mask) ~= mask end
-- pressed, then repeating while held (after 0.35 s, every 0.09 s)
function PP.pad_repeat(mask, now)
    if not PP.pad_down(mask) then PP.pad_held[mask] = nil; return false end
    local h = PP.pad_held[mask]
    if not h then PP.pad_held[mask] = now + 0.35; return true end
    if now >= h then PP.pad_held[mask] = now + 0.09; return true end
    return false
end

function PP.focusable(r)
    local kind = r.key:match('^([%w_]+)')
    return r.enabled and kind ~= 'panel' and kind ~= 'drag' and kind ~= 'scroll' and kind ~= 'search'
end
function PP.find_region(key)
    for _, r in ipairs(ui.regions) do if r.key == key then return r end end
    return nil
end
-- a sensible first focus for the view on screen
function PP.focus_default()
    local want = { ui.sel and ('sel:' .. tostring(ui.sel)) or false }
    for _, r in ipairs(ui.regions) do
        local kind = r.key:match('^([%w_]+)')
        if PP.focusable(r) and PP.LIST_ROW[kind] and kind ~= 'tick' then want[#want + 1] = r.key break end
    end
    want[#want + 1] = 'tab:1'
    want[#want + 1] = 'add'
    for _, k in ipairs(want) do
        local r = k and PP.find_region(k)
        if r and PP.focusable(r) then ui.focus = k; ui.version = ui.version + 1; return end
    end
end
-- move the focus to the nearest button in a direction (screen y grows upwards here)
function PP.nav(dir)
    local cur = ui.focus and PP.find_region(ui.focus)
    if not cur then PP.focus_default(); return end
    local cx, cy = cur.x + cur.w / 2, cur.y + cur.h / 2
    local best, bestd = nil, nil
    for _, r in ipairs(ui.regions) do
        if r ~= cur and r.key ~= cur.key and PP.focusable(r) then
            local dx, dy = r.x + r.w / 2 - cx, r.y + r.h / 2 - cy
            local main, side
            if dir == 'up' then main, side = dy, dx
            elseif dir == 'down' then main, side = -dy, dx
            elseif dir == 'right' then main, side = dx, dy
            else main, side = -dx, dy end
            if main > 2 then
                local d = main + 2 * math.abs(side)
                if not bestd or d < bestd then best, bestd = r, d end
            end
        end
    end
    -- at the end of a long list: scroll it instead of jumping out of the list
    local sc = ui.scrolling
    local function inside(r)                  -- in the scrolling list's box?
        local x, y = r.x + r.w / 2, r.y + r.h / 2
        return sc and x >= sc.x and x < sc.x + sc.w and y >= sc.y and y < sc.y + sc.h
    end
    local in_list = PP.LIST_ROW[cur.key:match('^([%w_]+)')] and inside(cur)
    local best_in_list = best and PP.LIST_ROW[best.key:match('^([%w_]+)')] and inside(best)
    if in_list and sc and (dir == 'up' or dir == 'down') and not best_in_list then
        local off = ui.scroll[sc.id] or 0
        if (dir == 'down' and off < sc.max) or (dir == 'up' and off > 0) then
            PP.scroll(dir == 'down' and 1 or -1)
            ui.nav_retry = dir
            return
        end
    end
    if best then ui.focus = best.key; ui.version = ui.version + 1 end
end
-- LB / RB: the tabs in order (armor tabs, + Armor, Presets, Keys)
function PP.tab_step(step)
    local tabs = ui.tab_order or {}
    if #tabs == 0 then return end
    local active = ui.settings and 'settings' or ui.presets and 'presets' or ui.adding and 'add' or ('tab:' .. ui.tab)
    local at = 1
    for i, k in ipairs(tabs) do if k == active then at = i end end
    local k = tabs[(at - 1 + step) % #tabs + 1]
    if k ~= active then click(k) end
    ui.focus = nil
end

-- per frame while the panel is open
local function pad_panel(now)
    if not PP.has_pad then return end
    local P = PP.PAD
    if PP.pad_now ~= 0 and PP.pad_now ~= PP.pad_was and not ui.pad_mode then
        ui.pad_mode = true
        ui.version = ui.version + 1
    end
    if not ui.pad_mode or PP.pad_down(P.BACK) then return end   -- Back + Start is the open / close combo
    if ui.focus and not PP.find_region(ui.focus) then ui.focus = nil end
    for _, d in ipairs({ { P.UP, 'up' }, { P.DOWN, 'down' }, { P.LEFT, 'left' }, { P.RIGHT, 'right' } }) do
        if PP.pad_repeat(d[1], now) then PP.nav(d[2]) end
    end
    if PP.pad_repeat(P.R_UP, now) then PP.scroll(-1) end
    if PP.pad_repeat(P.R_DOWN, now) then PP.scroll(1) end
    if PP.pad_edge(P.A) then
        if not ui.focus then PP.focus_default() end
        local r = ui.focus and PP.find_region(ui.focus)
        if r and r.enabled then click(r.key) end
    elseif PP.pad_edge(P.B) then
        if ui.search_on or (ui.search or '') ~= '' then PP.set_search('', false)
        elseif ui.value then finish_value(false)
        elseif ui.naming then finish_naming(false)
        elseif ui.adding or ui.presets or ui.settings then
            ui.adding, ui.presets, ui.settings, ui.focus = false, false, false, nil
            ui.version = ui.version + 1
        else PP.open_panel(false) end
    elseif PP.pad_edge(P.LB) then PP.tab_step(-1)
    elseif PP.pad_edge(P.RB) then PP.tab_step(1)
    elseif PP.pad_edge(P.X) then PP.undo()
    elseif PP.pad_edge(P.Y) then
        local r = type(ui.sel) == 'number' and PP.find_region('tick:' .. ui.sel)
        if r and r.enabled then click(r.key) end
    end
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
        if ui.worlds then PP.note('resettle') end
        clear_gui()
        ui.worlds, ui.main, ui.settled_at = worlds, main, now + SETTLE_SECONDS
        return
    end
    if now < ui.settled_at then return end
    local world = overlay_world()
    if not world then PP.note('no_world'); clear_gui(); return end
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
    if not ui.hover and not ui.drag then mouse_was_down, armed = nil, nil end
    if input.focused() then keyboard(now) end
    if input.focused() then
        local ok, why = pcall(pad_panel, now)
        if not ok then log('panel: controller: ' .. tostring(why)) end
        if not ui.open then return end         -- B closed the panel: draw nothing more this frame
    end
    if ui.pad_mode then ui.hover = ui.focus end

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
            PP.note('refused')
            log('panel: the overlay world refused a gui')
            clear_gui()
            return
        end
        local ok, chosen = pcall(choose_font, ui.gui)
        font = ok and chosen or { text = 'no text: ' .. tostring(chosen) }
        local said = font.text .. ' @ ' .. width .. 'x' .. height .. ', panel size ' .. math.floor(ui_scale() * 100 + 0.5) .. '%'
        if said ~= ui.font_said then
            ui.font_said = said
            log('panel font: ' .. said)
        end
        ui.signature = signature
        ui.regions = draw(width, height)
        PP.note('drawn')
        if ui.nav_retry then                  -- a list scrolled under the focus: move again
            local d = ui.nav_retry
            ui.nav_retry = nil
            PP.nav(d)
        end
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
    local s = height / 1080 * ui_scale()
    local function px(v) return math.floor(v + 0.5) end
    local w, h = px(480 * s), px(72 * s)
    local x, y = px((width - w) / 2), px(height - 140 * s - h)
    local yellow = Color(255, 255, 231, 16)
    local function r(tx, py, pw, ph, c, z)      -- panel units from the card's top left
        local x0, x1 = px(x + tx * s), px(x + (tx + pw) * s)
        local y0, y1 = px(y + h - (py + ph) * s), px(y + h - py * s)
        Gui.rect(gui, Vector3(x0, y0, z or 961), Vector2(math.max(1, x1 - x0), math.max(1, y1 - y0)), c)
    end
    r(0, 0, 480, 72, Color(246, 11, 12, 13), 960)
    r(0, 0, 4, 72, yellow)
    r(4, 0, 476, 1, Color(255, 62, 65, 70)); r(4, 71, 476, 1, Color(255, 62, 65, 70)); r(479, 0, 1, 72, Color(255, 62, 65, 70))
    if f.font then
        local function t(value, tx, py, size, c)
            local sz = math.max(9, px(size * s))
            Gui.text(gui, value, f.font, sz, f.material, Vector3(px(x + tx * s), px(y + h - py * s - sz * 0.8), 962), c)
        end
        t('ARMORY FORGE  -  ' .. string.upper(tostring(toast.sub or '')), 20, 13, 11, yellow)
        t(tostring(toast.text), 20, 34, 22, Color(255, 233, 230, 220))
    end
end

local function open_panel(open)
    ui.open = open
    PP.last_cur = nil                         -- a cursor moved while closed is not "the mouse took over"
    if open then
        ui.worlds = nil
        clear_toast(); toast.text = nil
        if not ui.last_text and LOADOUT then ui.last_text = snapshot() end
        PP.load_user()
        pcall(PP.load_pos)
        PP.note('opened')
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
        if ui.drag then ui.drag = nil; pcall(PP.save_pos) end
        ui.search_on = false
        ui.confirm, ui.adding, ui.settings = nil, false, false
        if save_at then pcall(save_now) end
    end
end

PP.open_panel = open_panel

-- true once per press of a hotkey (window focused)
local function hotkey_pressed(name)
    local vk = VK[name]
    if not vk then return false end
    local down = input.key_down(vk)
    local was = keys_was[name]
    keys_was[name] = down
    local focused = input.focused()
    if down and not was and name == hotkey() then PP.note(focused and 'presses' or 'unfocused') end
    return down and not was and focused
end

panel_tick = function(now)
    if not input or not sr then return end
    if hotkey_pressed(hotkey()) then open_panel(not ui.open) end
    local okp, has = pcall(PP.pad_read)
    PP.has_pad = okp and has
    if PP.has_pad and input.focused() and PP.pad_edge(PP.PAD.BACK + PP.PAD.START) then
        open_panel(not ui.open)
        if ui.open then ui.pad_mode, ui.focus = true, nil end
    end
    if state.research_note then                -- research builds only: show what the test just did
        clear_toast()
        toast.text, toast.sub, toast.till = state.research_note, 'research', now + 5
        state.research_note = nil
    end
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
            PP.note('errors', why)
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
    if PP.diag_dirty and now >= (PP.diag_at or 0) then
        PP.diag_dirty, PP.diag_at = false, now + 5
        pcall(write_status)
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
    state.report = PP.report
    PP.globals0 = {}
    for k in pairs(_G) do PP.globals0[k] = true end
    log('panel ready: press ' .. hotkey() .. ' in game' ..
        (swap_key() ~= 'OFF' and ('; ' .. swap_key() .. ' swaps presets') or ''))
end

end
build_panel()
