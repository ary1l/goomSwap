-- Inventory-aware item fetching for /packer (Ashita + Bellhop).
-- Bellhop queues every item move the moment /bh get runs and keeps no record of it, so the
-- reservations live here and in a per-character file: no reload, /addon reload included, asks twice.
-- Pure helpers (Outstanding, Deficit, Plan, Leftovers, Encode, Decode) take no game APIs.
local gcpacker = {}

gcpacker.SEND_GRACE = 20 -- s: no move for an item sent by then = Bellhop refused it (none found, full)
gcpacker.ANSWER_GRACE = 10 -- s after the last sent move: the server has answered; nothing more is coming

-- { path, job, keep = {[id] = n}, pending = {[id] = {count, before, at, sent, last}} }; global so it
-- outlives /lac reload, saved to disk so it outlives /addon reload.
if type(GcPacker) ~= 'table' then GcPacker = { keep = {}, pending = {} } end
local ledger = GcPacker

-- How much of a request is still on the way, and why. Inventory rising from `before` counts as arrived.
-- 'queued': not sent yet; 'moving': sent, not answered; 'done' / 'refused' / 'settled': nothing more coming.
function gcpacker.Outstanding(entry, have, now)
    if type(entry) ~= 'table' then return 0, 'done' end
    local count = math.max(0, tonumber(entry.count) or 0)
    local arrived = math.max(0, (tonumber(have) or 0) - (tonumber(entry.before) or have or 0))
    local left = math.max(0, count - arrived)
    if left == 0 then return 0, 'done' end
    now = tonumber(now) or 0
    if (tonumber(entry.sent) or 0) == 0 then
        if now - (tonumber(entry.at) or now) > gcpacker.SEND_GRACE then return 0, 'refused' end
        return left, 'queued'
    end
    if now - (tonumber(entry.last) or now) > gcpacker.ANSWER_GRACE then return 0, 'settled' end
    return left, 'moving'
end

function gcpacker.Deficit(target, have, outstanding)
    return math.max(0, (tonumber(target) or 0) - (tonumber(have) or 0) - (tonumber(outstanding) or 0))
end

-- rows: { name, n, stack, have, reach, outstanding }; free: empty inventory slots.
-- Returns what to ask Bellhop for ({row, get}) and why anything short was not asked for.
-- Each move fills a new slot (Bellhop's own count), so a request costs ceil(get / stack) slots.
function gcpacker.Plan(rows, free)
    local asks, notes = {}, {}
    free = math.max(0, tonumber(free) or 0)
    for _, row in ipairs(rows) do
        local need = gcpacker.Deficit(row.n, row.have, row.outstanding)
        local reach = math.max(0, tonumber(row.reach) or 0)
        local stack = math.max(1, tonumber(row.stack) or 1)
        if need > 0 then
            local get = math.min(need, reach)
            if reach == 0 then
                notes[#notes + 1] = row.name .. ' (none in reach)'
            elseif free == 0 then
                notes[#notes + 1] = row.name .. ' (inventory full)'
                get = 0
            else
                get = math.min(get, free * stack)
                free = free - math.ceil(get / stack)
                if get < need then notes[#notes + 1] = row.name .. ' ' .. (row.have + get) .. '/' .. row.n end
            end
            if get > 0 then asks[#asks + 1] = { row = row, get = get } end
        end
    end
    return asks, notes
end

-- After a job change: what the previous job's list kept that this one does not ({id, n}).
-- Only up to the old target is put back; extra copies you carried yourself stay.
function gcpacker.Leftovers(previous, current, haveOf)
    local out = {}
    for id, n in pairs(previous or {}) do
        if (current[id] == nil) then
            local put = math.min(tonumber(n) or 0, haveOf(id))
            if put > 0 then out[#out + 1] = { id = id, n = put } end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function gcpacker.Encode(state)
    local lines = { 'goomswap-packer 1' }
    if state.job then lines[#lines + 1] = 'job ' .. state.job end
    for id, n in pairs(state.keep or {}) do lines[#lines + 1] = ('keep %d %d'):format(id, n) end
    for id, e in pairs(state.pending or {}) do
        lines[#lines + 1] = ('pend %d %d %d %d %d %d'):format(id, e.count, e.before, e.at, e.sent or 0, e.last or 0)
    end
    return table.concat(lines, '\n') .. '\n'
end

function gcpacker.Decode(text)
    local state = { keep = {}, pending = {} }
    if (type(text) ~= 'string') or (text:sub(1, 16) ~= 'goomswap-packer ') then return state end
    for line in text:gmatch('[^\r\n]+') do
        local job = line:match('^job (%u+)$')
        if job then state.job = job end
        local id, n = line:match('^keep (%d+) (%d+)$')
        if id then state.keep[tonumber(id)] = tonumber(n) end
        local p = { line:match('^pend (%d+) (%d+) (%d+) (%d+) (%d+) (%d+)$') }
        if #p == 6 then
            state.pending[tonumber(p[1])] = { count = tonumber(p[2]), before = tonumber(p[3]), at = tonumber(p[4]),
                sent = tonumber(p[5]), last = tonumber(p[6]) }
        end
    end
    return state
end

-- Game side ------------------------------------------------------------------------------------

local function ledger_path()
    if (gState == nil) or (gState.PlayerName == nil) or (gState.PlayerId == nil) then return nil end
    return ('%sconfig\\addons\\luashitacast\\%s_%u\\goomswap-packer.txt'):format(AshitaCore:GetInstallPath(),
        gState.PlayerName, gState.PlayerId)
end

local function load_ledger()
    local path = ledger_path()
    if (path == nil) or (ledger.path == path) then return end
    local f, text = io.open(path, 'r'), nil
    if f then text = f:read('*a'); f:close() end
    local state = gcpacker.Decode(text)
    ledger.path, ledger.job, ledger.keep, ledger.pending = path, state.job, state.keep, state.pending
end

local function save_ledger()
    if ledger.path == nil then return end
    local f = io.open(ledger.path, 'w')
    if f then f:write(gcpacker.Encode(ledger)); f:close() end
end

local inc = nil -- gcinclude (CountItem, FreeSlots), from Start/Run

-- Counts of one item: in Inventory, and in the bags Bellhop can reach from here (LuAshitacast's rules).
local function counts(id)
    local reach = {}
    for c = 1, 16 do
        if (c ~= 3) and gData.GetContainerAvailable(c) then reach[#reach + 1] = c end
    end
    return (inc.CountItem(id, { 0 })), (inc.CountItem(id, reach))
end

local function bellhop_loaded()
    local manager = AshitaCore:GetPluginManager()
    return (manager ~= nil) and ((manager:Get('Bellhop') ~= nil) or (manager:Get('bellhop') ~= nil))
end

local function item_name(id)
    local r = AshitaCore:GetResourceManager():GetItemById(id)
    return (r ~= nil) and r.Name[1] or tostring(id)
end

-- Outgoing 0x029 (XiPackets GP_CLI_ITEM_MOVE: ItemNum @4, Category1 @8, Category2 @9, ItemIndex1 @10)
-- into Inventory, for an item we asked for: Bellhop sent it. Injected packets from plugins pass here too.
function gcpacker.OnPacketOut(e)
    if (e.id ~= 0x029) or (next(ledger.pending) == nil) then return end
    local qty = struct.unpack('I', e.data, 0x04 + 1)
    local from, to, index = struct.unpack('BBB', e.data, 0x08 + 1)
    if (to ~= 0) or (from == 0) then return end
    local it = AshitaCore:GetMemoryManager():GetInventory():GetContainerItem(from, index)
    local entry = (it ~= nil) and ledger.pending[it.Id] or nil
    if entry ~= nil then
        entry.sent, entry.last = (entry.sent or 0) + qty, os.time()
        save_ledger()
    end
end

function gcpacker.Start(include)
    inc = include
    load_ledger()
    ashita.events.register('packet_out', 'gcpacker_moves', gcpacker.OnPacketOut)
end

function gcpacker.Stop()
    ashita.events.unregister('packet_out', 'gcpacker_moves')
end

-- Use only after Bellhop has finished or been stopped.
function gcpacker.Reset(include)
    inc = include
    load_ledger()
    ledger.pending = {}
    save_ledger()
    include.Say('/packer: pending requests cleared. Run /packer again to fetch missing items.')
end

-- Drop answered requests. Returns the in-flight amount per item id, and items Bellhop never sent.
local function settle(now)
    local inflight, refused, changed = {}, {}, false
    for id, entry in pairs(ledger.pending) do
        local left, why = gcpacker.Outstanding(entry, (counts(id)), now)
        if left > 0 then
            inflight[id] = left
        else
            if why == 'refused' then refused[id] = true end
            ledger.pending[id], changed = nil, true
        end
    end
    if changed then save_ledger() end
    return inflight, refused
end

local function report(include, items, quiet)
    local inflight, refused = settle(os.time())
    local waiting, short = {}, {}
    for _, item in ipairs(items) do
        local have = counts(item.id)
        if (inflight[item.id] or 0) > 0 then
            waiting[#waiting + 1] = item.name .. ' +' .. inflight[item.id]
        elseif have < item.n then
            short[#short + 1] = item.name .. ' ' .. have .. '/' .. item.n .. (refused[item.id]
                and ' (Bellhop moved none)' or '')
        end
    end
    if #waiting > 0 and not quiet then include.Say('/packer: Bellhop still moving: ' .. table.concat(waiting, ', ')) end
    if #short > 0 then include.Err('/packer: still short: ' .. table.concat(short, ', ')) end
end

function gcpacker.Run(include, quiet)
    inc = include
    load_ledger()
    local items = include.PackerList()
    local keep = {}
    for _, item in ipairs(items) do keep[item.id] = item.n end
    local player = gData.GetPlayer()
    local job = (player ~= nil) and player.MainJob or nil
    local bellhop = bellhop_loaded()
    local chat = AshitaCore:GetChatManager()

    -- A job change: put back what only the previous job kept. Bellhop runs its commands in order,
    -- so these leave before the new job's items arrive.
    local putAway = {}
    if bellhop and (include.settings.PackerPutAway ~= false) and (job ~= nil) and (ledger.job ~= nil)
        and (ledger.job ~= job) then
        for _, left in ipairs(gcpacker.Leftovers(ledger.keep, keep, function(id) return (counts(id)) end)) do
            local name = item_name(left.id)
            ledger.pending[left.id] = nil
            chat:QueueCommand(-1, '/bh put "' .. name .. '" ' .. left.n)
            putAway[#putAway + 1] = name .. ' ' .. left.n
        end
    end
    if bellhop and (job ~= nil) then ledger.job, ledger.keep = job, keep end
    if #putAway > 0 then include.Say('/packer: putting away ' .. table.concat(putAway, ', ')) end

    if #items == 0 then
        save_ledger()
        if not quiet then include.Say('/packer: nothing listed (PackerItems, gcinclude.Packer)') end
        return
    end

    local now = os.time()
    local inflight = settle(now)
    local rows, waiting = {}, {}
    for _, item in ipairs(items) do
        local have, reach = counts(item.id)
        local stack = AshitaCore:GetResourceManager():GetItemById(item.id)
        rows[#rows + 1] = { item = item, name = item.name, n = item.n, have = have, reach = reach,
            outstanding = inflight[item.id] or 0, stack = (stack ~= nil) and stack.StackSize or 1 }
        if (inflight[item.id] or 0) > 0 then waiting[#waiting + 1] = item.name .. ' +' .. inflight[item.id] end
    end
    local asks, notes = gcpacker.Plan(rows, include.FreeSlots(0))

    if not bellhop then
        save_ledger()
        local short = {}
        for _, a in ipairs(asks) do short[#short + 1] = a.row.name .. ' +' .. a.get end
        if #short > 0 then include.Err('/packer needs Bellhop (/load bellhop): short ' .. table.concat(short, ', ')) end
        if (#short == 0) and not quiet then include.Say('/packer: all in inventory') end
        return
    end

    -- Reserve before queuing: a reload or another /packer from here on sees the request in flight.
    local asked = {}
    for _, a in ipairs(asks) do
        local row = a.row
        ledger.pending[row.item.id] = { count = row.outstanding + a.get, before = row.have, at = now,
            sent = 0, last = 0 }
        chat:QueueCommand(-1, '/bh get "' .. row.name .. '" ' .. a.get)
        asked[#asked + 1] = row.name .. ' +' .. a.get
    end
    save_ledger()

    if #asked > 0 then include.Say('/packer: ' .. table.concat(asked, ', ')) end
    if #notes > 0 then include.Err('/packer: short: ' .. table.concat(notes, ', ')) end
    if (#asked == 0) and (#notes == 0) and not quiet then
        include.Say((#waiting > 0) and ('/packer: waiting for Bellhop: ' .. table.concat(waiting,
            ', ')) or '/packer: all in inventory')
    end
    if #asked > 0 then (function() report(include, items, quiet) end):once(gcpacker.SEND_GRACE + 2); end
end

return gcpacker
