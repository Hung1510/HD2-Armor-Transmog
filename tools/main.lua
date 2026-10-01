-- ================================================================ tick and startup
local BUS = nil
local next_round, next_enforce = 0, 0

local function tick()
    state.frame = state.frame + 1
    if state.phase == 'gave_up' or state.frame < START_FRAME then return end
    local now = api.now()
    local wall = os.time()

    if state.phase == 'starting' then
        begin_round()
        state.phase = 'searching'
    elseif state.phase == 'searching' then
        local ok, finished = pcall(scan_step)
        if not ok then
            set_status('gave_up', 'scan error: ' .. tostring(finished))
            return
        end
        if finished then
            pcall(write_dump)          -- after every pass; only rewrites when something new was found
            if research then pcall(research.finish) end
            if good_enough() or state.rounds >= MAX_ROUNDS then
                set_status('ready', (complete() and 'all ' .. #CAT_LIST .. ' armor passives found'
                                     or ('found ' .. perks_found .. ' of ' .. #CAT_LIST .. ' armor passives'))
                                    .. '; ' .. summary())
                next_enforce = wall + ENFORCE_SECONDS
            else
                set_status('waiting', 'round ' .. state.rounds .. ': ' .. perks_found .. ' of ' .. #CAT_LIST .. ' armor passives found')
                next_round = wall + ROUND_DELAY_SECONDS
            end
        end
    elseif state.phase == 'waiting' then
        if wall >= next_round then
            begin_round()
            state.phase = 'searching'
        end
    elseif state.phase == 'ready' then
        if LOADOUT and not LOADOUT.retire and wall >= next_enforce then
            next_enforce = wall + ENFORCE_SECONDS
            local ok, gone = pcall(enforce)
            if ok and gone then
                state.rounds = 0
                begin_round()
                state.phase = 'searching'
            end
        end
    end

    if save_at and now >= save_at then pcall(save_now) end
    if research and research.tick and state.phase == 'ready' then pcall(research.tick, now) end
    if not MOD.no_panel then
        local ok, why = pcall(panel_tick, now)
        if not ok then log('panel: ' .. tostring(why)) end
    end
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
    ensure_read_into()
    LOADOUT, state.loadout_source = load_loadout()
    self_addresses = { api.address_of(NEEDLE) }
    skip_low = (self_addresses[1] or LUA_HEAP_LIMIT) < LUA_HEAP_LIMIT
    if MOD.no_panel then
        log('panel: off in this build (panel = off); edit the loadout in the web builder')
    else
        setup_panel()
    end
end)

if not ok then
    state.phase, state.status = 'gave_up', tostring(failure)
    print('[' .. MOD.global .. '] ' .. tostring(failure))
    if api then pcall(flush_log) end
    return
end

-- for tests and other mods: read-only views of the live loadout
state.loadout = function() return LOADOUT end
state.resolve = resolve_profile
state.serialize = function() return serialize(LOADOUT, DEFAULT_KEY) end
state.changed = loadout_changed

set_status('starting', 'waiting for the game to settle; ' .. state.loadout_source .. ' loadout')

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
