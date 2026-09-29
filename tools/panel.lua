-- ================================================================ in-game panel
-- The panel's drawing, input, cursor and font handling come from SHODAN Stat Editor
-- v1.4.1 by SHODAN (public domain / Unlicense, https://github.com/SHODAN-HORAI/SHODAN-Stat-Editor),
-- adapted for armor passives. Hotkey F7 by default (loadout.ini: [settings] hotkey = F7).
--
-- Layout: armor tabs across the top (one per stack); on the left every passive with a
-- tick box (ticked = stacked onto this armor); on the right the chosen passive's values
-- with -- - + ++ and reset, or click a value to type it. Every change applies at once
-- and is saved to PassivePicker\loadout.ini.

local sr, input = nil, nil
local VK = { Up = 0x26, Down = 0x28, Left = 0x25, Right = 0x27, PageUp = 0x21, PageDown = 0x22,
             Delete = 0x2E, Shift = 0x10, Enter = 0x0D, Backspace = 0x08, Escape = 0x1B, Ctrl = 0x11 }
for n = 1, 12 do VK['F' .. n] = 0x6F + n end
local DIGIT_KEYS = {}
for n = 0, 9 do DIGIT_KEYS[#DIGIT_KEYS + 1] = { 0x30 + n, tostring(n) }; DIGIT_KEYS[#DIGIT_KEYS + 1] = { 0x60 + n, tostring(n) } end
for _, k in ipairs({ { 0xBE, '.' }, { 0x6E, '.' }, { 0xBC, '.' }, { 0xBD, '-' }, { 0x6D, '-' } }) do DIGIT_KEYS[#DIGIT_KEYS + 1] = k end

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
    }) do pcall(ffi.cdef, declaration) end
    local user = ffi.load('user32')
    local own_pid = ffi.load('kernel32').GetCurrentProcessId()
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
    return self
end

-- ---------------------------------------------------------------- state
local ui = { open = false, tab = 1, sel = nil, hover = nil, gui = nil, world = nil, signature = nil,
             regions = {}, version = 0, errors = 0, value = nil, adding = false, message = nil,
             confirm = nil }
local W, H = 1000, 940
local font = nil
local held, mouse_was_down, armed = {}, nil, nil
local hotkey_was_down = false

local function hotkey() return (LOADOUT and LOADOUT.hotkey) or MOD.hotkey or 'F7' end
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

local function steps(e)
    if e.type == 0 then return 1, 1 end
    if e.type == 3 then return 0.5, 2 end
    if e.type == 1 then
        if math.abs(e.def) >= 10 then return 5, 20 end
        if e.key == 'armor_rating' then return 0.1, 0.5 end
        return 1, 2
    end
    return 0.05, 0.25
end

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

local function meaning(e, v)
    if e.type == 2 then
        if v == 0 then return 'x0 (removes it)' end
        local pct = math.floor((v - 1) * 1000 + 0.5) / 10
        return 'x' .. fmt(v) .. ' (' .. (pct >= 0 and '+' or '') .. fmt(pct) .. '%)'
    end
    if e.type == 1 then
        if e.key == 'armor_rating' then return '+' .. fmt(v) .. ' (about +' .. fmt(math.floor(v * 50 + 0.5)) .. ' armor)' end
        return (v >= 0 and '+' or '') .. fmt(v)
    end
    if e.type == 3 then return fmt(v) .. ' s' end
    return 'set to ' .. fmt(v)
end

local function label_of(e)
    local s = e.key:gsub('^stat_', ''):gsub('_', ' ')
    s = s:sub(1, 1):upper() .. s:sub(2)
    if e.kind == 'stat' then s = s .. ' (weapon stat)' end
    return s
end

-- ---------------------------------------------------------------- changes
local function changed(perk, text)
    ui.version = ui.version + 1
    loadout_changed(perk and { perk } or nil)
    if text then say(text) end
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
    local n = tonumber((v.text:gsub(',', '.')))
    local p = current()
    if not n or not p then say('Not a number: ' .. v.text); return end
    local c = CAT[v.pid]
    local e = c and c.effects[v.n]
    if e then set_value(p, v.pid, e, n) end
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
local function draw(width, height)
    local Gui, Vector3, Vector2, Color = sr.Gui, sr.Vector3, sr.Vector2, sr.Color
    local s = height / 1080 * 0.8
    local ox, oy = 30 * s, (height - H * s) / 2     -- left edge: SHODAN Stat Editor uses the right
    local gui = ui.gui
    local regions = {}
    local ink_font, ink_material = font.font, font.material

    local function color(r, g, b, a) return Color(a or 255, r, g, b) end
    local function vx(v)
        for _, get in ipairs({ function() return Vector2.x(v) end, function() return Vector3.x(v) end,
                               function() return v[1] end }) do
            local ok, x = pcall(get)
            if ok and type(x) == 'number' then return x end
        end
        return nil
    end
    local GOLD, WHITE, MUTED, DIM = color(255, 213, 0), color(238, 242, 246), color(153, 171, 184), color(95, 108, 120)
    local WARN, GOOD, LINE = color(255, 150, 60), color(120, 220, 140), color(70, 82, 94)

    local function rect(x, y, w, h, c, z)
        Gui.rect(gui, Vector3(ox + x * s, height - oy - (y + h) * s, z or 951), Vector2(w * s, h * s), c)
    end
    local function text(value, x, y, size, c, limit, align_right)
        if value == nil or value == '' or not ink_font then return end
        size = size * s
        local px = ox + x * s
        if limit or align_right then
            local ok, lo, hi = pcall(Gui.text_extents, gui, value, ink_font, size)
            local measure = nil
            if ok and lo and hi then
                local a, b = vx(lo), vx(hi)
                if a and b and b > a then measure = b - a end
            end
            measure = measure or #value * size * 0.5
            if limit and measure > limit * s then size = size * limit * s / measure; measure = limit * s end
            if align_right then px = px - measure end
        end
        Gui.text(gui, value, ink_font, size, ink_material, Vector3(px, height - oy - y * s - size * 0.8, 953), c or WHITE)
    end
    local function outline(x, y, w, h, c)
        rect(x, y, w, 2, c, 952); rect(x, y + h - 2, w, 2, c, 952)
        rect(x, y, 2, h, c, 952); rect(x + w - 2, y, 2, h, c, 952)
    end
    local function region(key, x, y, w, h, enabled)
        regions[#regions + 1] = { key = key, x = ox + x * s, y = height - oy - (y + h) * s, w = w * s, h = h * s,
                                  enabled = enabled ~= false }
    end
    local function button(key, label, x, y, w, h, enabled, active, ink)
        local hovered = ui.hover == key and enabled ~= false
        local fill = active and color(90, 74, 8) or hovered and color(52, 66, 80) or color(28, 34, 42)
        rect(x, y, w, h, fill, 951)
        outline(x, y, w, h, enabled == false and DIM or (active or hovered) and GOLD or LINE)
        text(label, x + 8, y + (h - 16) / 2, 16, enabled == false and DIM or ink or WHITE, w - 12)
        region(key, x, y, w, h, enabled)
    end
    local function tickbox(key, x, y, on, enabled)
        local hovered = ui.hover == key
        rect(x, y, 20, 20, color(20, 26, 34), 951)
        outline(x, y, 20, 20, (on or hovered) and GOLD or LINE)
        if on then rect(x + 5, y + 5, 10, 10, GOLD, 952) end
        region(key, x - 4, y - 3, 28, 26, enabled)
    end

    -- frame
    rect(0, 0, W, H, color(8, 11, 15, 232), 950)
    outline(0, 0, W, H, GOLD)
    region('panel', 0, 0, W, H, false)
    text('PASSIVE PICKER', 18, 12, 24, GOLD)
    text('armor passive stacker', 214, 18, 15, MUTED)
    text(hotkey() .. ' to close', W - 18, 16, 15, MUTED, nil, true)

    if state.phase ~= 'ready' then
        text('Reading the game\'s armor passives... (' .. perks_found .. ' of ' .. #CAT_LIST .. ' found)', 18, 70, 18, WHITE)
        text('Load into your ship or a mission if this does not finish.', 18, 98, 15, MUTED)
        return regions
    end

    -- armor tabs
    local p = current()
    local x = 16
    for n, prof in ipairs(LOADOUT.profiles) do
        local label = CAT[prof.perk].name .. ' armor'
        button('tab:' .. n, label, x, 52, 168, 32, true, n == ui.tab and not ui.adding)
        x = x + 174
        if x > W - 330 then break end
    end
    button('add', '+ Armor', x, 52, 100, 32, true, ui.adding)
    if p and not ui.adding then
        local sure = ui.confirm and ui.confirm.kind == 'remove'
        button('remove', sure and 'Sure? Click again' or 'Remove this armor', W - 16 - 190, 52, 190, 32, true, sure)
    end
    rect(16, 90, W - 32, 2, LINE, 951)

    -- left list
    local LX, LW, LY, RH = 16, 322, 100, 25
    if ui.adding then
        text('Pick the armor passive for the new stack:', LX + 4, LY, 16, GOLD, LW)
        local used = {}
        for _, prof in ipairs(LOADOUT.profiles) do used[prof.perk] = true end
        local y = LY + 28
        for _, c in ipairs(CAT_LIST) do
            if not used[c.id] then
                local key = 'addpick:' .. c.id
                if ui.hover == key then rect(LX, y, LW, RH - 1, color(40, 52, 64), 951) end
                text(c.name, LX + 10, y + 4, 16, WHITE, LW - 20)
                region(key, LX, y, LW, RH - 1)
                y = y + RH
            end
        end
        button('addcancel', 'Cancel', LX, H - 50, 120, 32, true)
    elseif not p then
        text('No stack yet.', LX + 4, LY + 4, 18, WHITE)
        text('Click "+ Armor" and pick the armor passive', LX + 4, LY + 34, 15, MUTED, LW)
        text('your armor has (e.g. Med-Kit).', LX + 4, LY + 54, 15, MUTED, LW)
    else
        local res = last_result[p.perk] and last_result[p.perk].res
        text('Tick passives to stack onto', LX + 4, LY, 14, MUTED, LW)
        local y = LY + 22
        -- the armor's own passive first
        local base_key = 'sel:' .. p.perk
        if ui.sel == p.perk then rect(LX, y, LW, RH - 1, color(90, 74, 8), 951)
        elseif ui.hover == base_key then rect(LX, y, LW, RH - 1, color(40, 52, 64), 951) end
        text('* ' .. CAT[p.perk].name .. ' (base)', LX + 10, y + 4, 16, GOLD, LW - 20)
        region(base_key, LX, y, LW, RH - 1)
        y = y + RH + 4
        for _, c in ipairs(CAT_LIST) do
            if c.id ~= p.perk then
                local on = p.enabled[c.id] == true
                local key = 'sel:' .. c.id
                if ui.sel == c.id then rect(LX, y, LW, RH - 1, color(90, 74, 8), 951)
                elseif ui.hover == key then rect(LX, y, LW, RH - 1, color(40, 52, 64), 951) end
                region(key, LX + 34, y, LW - 34, RH - 1)
                tickbox('tick:' .. c.id, LX + 8, y + 2, on)
                local tweaked = false
                for k in pairs(p.tweaks) do if k:match('^' .. c.id .. '%.') then tweaked = true break end end
                text(c.name .. (tweaked and on and ' *' or ''), LX + 38, y + 4, 16, on and WHITE or MUTED, LW - 48)
                y = y + RH
            end
        end
    end
    rect(LX + LW + 8, 100, 2, H - 116, LINE, 951)

    -- right side: the chosen passive
    local X0, RW = LX + LW + 20, W - (LX + LW + 20) - 16
    if p and not ui.adding then
        if not ui.sel then ui.sel = p.perk end
        local sel = ui.sel and CAT[ui.sel] or nil
        if not sel then
            text(CAT[p.perk].name .. ' armor', X0, 100, 22, GOLD, RW)
            text('Wear any armor with the ' .. CAT[p.perk].name .. ' passive (Armor Transmog', X0, 136, 16, WHITE, RW)
            text('lets you pick its look). Tick passives on the left to add them.', X0, 158, 16, WHITE, RW)
            text('Click a passive\'s name to change its values.', X0, 190, 16, MUTED, RW)
        else
            local is_base = sel.id == p.perk
            text(sel.name .. (is_base and ' (base perk)' or ''), X0, 100, 22, GOLD, RW - 150)
            if is_base then
                text('The armor\'s own passive. Values here REPLACE its own.', X0, 128, 15, MUTED, RW)
                text('Tick passives on the left to stack them; click a name to edit it.', X0, 146, 14, DIM, RW)
            else
                local on = p.enabled[sel.id] == true
                button('tick:' .. sel.id, on and 'ON: stacked' or 'OFF: click to add', W - 16 - 170, 96, 170, 32, true, on)
                text(on and ('Stacked onto ' .. CAT[p.perk].name .. ' armor.') or 'Not stacked. Values you set are kept for when you turn it on.',
                     X0, 132, 15, on and GOOD or MUTED, RW)
            end
            local y = 166
            for n, e in ipairs(sel.effects) do
                local v = value_of(p, sel.id, e)
                local tweaked = v ~= e.def
                rect(X0, y - 4, RW, 58, color(16, 20, 26), 950)
                text(label_of(e) .. (e.hint:find('%?') and ' ?' or ''), X0 + 8, y, 17, WHITE, 300)
                text(e.hint, X0 + 8, y + 22, 13, MUTED, 300)
                local bx = X0 + 318
                local typing = ui.value and ui.value.pid == sel.id and ui.value.n == n
                local vkey = 'value:' .. n
                rect(bx, y, 92, 30, typing and color(20, 26, 34) or color(24, 30, 38), 951)
                outline(bx, y, 92, 30, (typing or ui.hover == vkey) and GOLD or LINE)
                if typing then
                    text(ui.value.text .. '_', bx + 8, y + 6, 17, ui.value.fresh and MUTED or WHITE, 78)
                else
                    text(fmt(v), bx + 84, y + 6, 17, tweaked and GOLD or WHITE, 78, true)
                end
                region(vkey, bx, y, 92, 30)
                local ax = bx + 98
                for _, b in ipairs({ { 'dec_big', '--' }, { 'dec', '-' }, { 'inc', '+' }, { 'inc_big', '++' } }) do
                    button(b[1] .. ':' .. n, b[2], ax, y, 36, 30, true)
                    ax = ax + 40
                end
                button('reset:' .. n, 'R', ax, y, 30, 30, tweaked)
                text(meaning(e, v) .. (tweaked and ('   default ' .. fmt(e.def)) or ''), bx, y + 34, 13, tweaked and GOLD or DIM, 300)
                y = y + 64
            end
            button('reset_passive', 'Reset ' .. sel.name, X0, y + 4, 260, 30, true)
        end

        -- overlap rule, summary, actions
        local by = H - 250
        rect(X0, by - 10, RW, 2, LINE, 951)
        text('When two passives change the same thing:', X0, by, 14, MUTED, RW)
        button('policy:stack', 'Stack all', X0, by + 20, 130, 30, true, p.conflicts ~= 'strongest')
        button('policy:strongest', 'Strongest only', X0 + 136, by + 20, 160, 30, true, p.conflicts == 'strongest')
        local last = last_result[p.perk]
        local res = last and last.res
        if not sites_by_perk[p.perk] then
            text('This armor passive was not found in the game\'s data yet.', X0, by + 60, 15, WARN, RW)
        elseif sites_by_perk[p.perk][1].foreign then
            text('Another mod already changed this passive\'s data; Passive Picker leaves it alone.', X0, by + 60, 15, WARN, RW)
        else
            local added = 0
            for _, site in ipairs(sites_by_perk[p.perk]) do added = math.max(added, site.added or 0) end
            local n_on = res and #res.enabled or 0
            text(n_on .. ' passive(s) stacked, +' .. added .. ' row(s) in the game\'s data' ..
                 (res and res.conflicts > 0 and ('; ' .. res.conflicts .. ' overlap(s)') or ''), X0, by + 60, 15, GOOD, RW)
            if last.error then text(last.error, X0, by + 80, 14, WARN, RW) end
        end
        local sure = ui.confirm and ui.confirm.kind
        button('clear', sure == 'clear' and 'Sure? Click again' or 'Untick all', X0, H - 150, 190, 32, true, sure == 'clear')
        button('revert', sure == 'revert' and 'Sure? Click again' or 'Back to installed build', X0 + 200, H - 150, 250, 32, true, sure == 'revert')
    end

    -- footer
    local path = save_path()
    text(path and 'Saved automatically to PassivePicker\\loadout.ini' or 'Cannot save (no LOCALAPPDATA)', X0, H - 100, 14, DIM, RW)
    text('Changes apply at once. Re-equip the armor if you do not see them.', X0, H - 80, 14, DIM, RW)
    text('Single-player / private lobbies only.', X0, H - 60, 14, DIM, RW)
    if ui.message then text(ui.message.text, X0, H - 36, 15, GOLD, RW) end
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

local function click(key)
    if not key then return end
    local kind, arg = key:match('^([%w_]+):?(.*)$')
    if ui.value and (kind ~= 'value' or tonumber(arg) ~= ui.value.n or ui.sel ~= ui.value.pid) then finish_value(true) end
    if ui.confirm and kind ~= ui.confirm.kind and not (kind == 'remove' and ui.confirm.kind == 'remove') then ui.confirm = nil end
    local p = current()
    local n = tonumber(arg)
    if kind == 'tab' and n then ui.tab, ui.sel, ui.adding = n, nil, false
    elseif kind == 'add' then ui.adding = not ui.adding
    elseif kind == 'addcancel' then ui.adding = false
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
        if confirm('clear') then p.enabled, p.tweaks = {}, {}; changed(p.perk, 'Unticked everything on this armor') end
    elseif kind == 'revert' then
        if confirm('revert') then
            LOADOUT = default_loadout()
            ui.tab, ui.sel = 1, nil
            changed(nil, 'Back to the loadout this build was installed with')
        end
    elseif kind == 'reset_passive' and p and ui.sel then
        for k in pairs(p.tweaks) do if k:match('^' .. ui.sel .. '%.') then p.tweaks[k] = nil end end
        changed(p.perk)
    elseif p and ui.sel and n and CAT[ui.sel] and CAT[ui.sel].effects[n] then
        local e = CAT[ui.sel].effects[n]
        local small, big = steps(e)
        local v = value_of(p, ui.sel, e)
        if kind == 'dec' then set_value(p, ui.sel, e, v - small)
        elseif kind == 'dec_big' then set_value(p, ui.sel, e, v - big)
        elseif kind == 'inc' then set_value(p, ui.sel, e, v + small)
        elseif kind == 'inc_big' then set_value(p, ui.sel, e, v + big)
        elseif kind == 'reset' then set_value(p, ui.sel, e, e.def)
        elseif kind == 'value' and not ui.value then ui.value = { pid = ui.sel, n = n, text = fmt(v), fresh = true } end
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
    local v = ui.value
    if not v then return end
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
    local world = nil
    for _, w in ipairs(worlds) do if w ~= main then world = w break end end
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
                                     tostring(ui.hover), ui.version, tostring(ui.adding),
                                     ui.message and ui.message.text or '',
                                     ui.value and (ui.value.n .. '=' .. ui.value.text) or '-' }, '|')
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

local function open_panel(open)
    ui.open = open
    if open then
        ui.worlds = nil
        log('panel opened')
        local ok, why = pcall(take_cursor)
        if not ok then log('cursor: could not free it: ' .. tostring(why)) end
    else
        if ui.value then finish_value(true) end
        pcall(release_cursor)
        clear_gui()
        ui.worlds = nil
        held, mouse_was_down, armed = {}, nil, nil
        ui.confirm, ui.adding = nil, false
        if save_at then pcall(save_now) end
    end
end

panel_tick = function(now)
    if not input or not sr then return end
    local vk = VK[hotkey()] or VK.F7
    local down = input.key_down(vk)
    if down and not hotkey_was_down and input.focused() then open_panel(not ui.open) end
    hotkey_was_down = down
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
    end
end

local function setup_panel()
    sr = rawget(_G, 'stingray')
    if type(sr) ~= 'table' then log('panel: the engine (stingray) is unavailable; panel off'); return end
    local ok, built = pcall(function() return rawget(_G, 'PP_TEST_INPUT') or build_input() end)
    if not ok then log('panel: input unavailable: ' .. tostring(built)); return end
    input = built
    state.ui = ui
    log('panel ready: press ' .. hotkey() .. ' in game')
end
