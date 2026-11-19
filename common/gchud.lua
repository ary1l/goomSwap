local gchud = {}


local inc = nil
local disp = nil
local nextWrite = 0
local nextRead = 0
local lastLine = nil
local lastWriteTime = 0
local rows = {}
local visible = false

-- The HUD is the drop under /gcbar (gcdisplay draws it): this file shares each box's modes (hud\<Name>.txt),
-- reads the other boxes' and forwards clicks. /gchud turns the drop on or off.

local STALE = 15

-- Main/Sub/Range/Ammo, MeleeSet, WsSet fold into wpn (FOLDED)
gchud.CycleOrder = { 'Weapons', 'Main', 'Sub', 'Range', 'Ammo', 'MeleeSet', 'WsSet', 'IdleSet' }
gchud.ToggleOrder = { 'DTset', 'MDTset', 'Aminon', 'SIR', 'TH', 'Kite' }

-- read_all: the rows' content (not their timestamps); unchanged keeps rows (and the drop's built lines)
local rowsKey = nil

local function dir()
    return string.format('%sconfig\\addons\\luashitacast\\hud\\', AshitaCore:GetInstallPath())
end

local listCache, listCacheUntil = nil, 0 -- read_all's last folder listing, kept 5s
local listTry = nil -- the path/mask form that listed files last time: tried first (read_all runs twice a second)
local function listing()
    local base = dir()
    local trimmed = string.sub(base, 1, string.len(base) - 1)
    -- mask: a regex (Ashita's blusets addon passes '.*.txt'); read_all keeps the .txt files itself
    local tries = { { base, '.*' }, { base }, { trimmed, '.*' }, { trimmed } }
    local function try(i)
        local t = tries[i]
        local ok, files = pcall(ashita.fs.get_directory, t[1], t[2])
        if (ok == true) and (type(files) == 'table') and (next(files) ~= nil) then return files end
        return nil
    end
    if (listTry ~= nil) then
        local files = try(listTry)
        if (files ~= nil) then return files, tries[listTry][1], (tries[listTry][2] or 'nil') end
    end
    for i = 1, #tries do
        if (i ~= listTry) then
            local files = try(i)
            if (files ~= nil) then listTry = i; return files, tries[i][1], (tries[i][2] or 'nil') end
        end
    end
    return nil, base, 'none matched'
end

local function me()
    local player = gData.GetPlayer()
    if (player == nil) then return nil end
    if (player.Name == nil) or (player.Name == '') then return nil end
    return player
end

local function encode(map, order)
    local parts = {}
    for _, k in ipairs(order) do
        if (map[k] ~= nil) then
            parts[#parts + 1] = k .. '=' .. tostring(map[k])
            map[k] = nil
        end
    end
    for k, v in pairs(map) do
        parts[#parts + 1] = k .. '=' .. tostring(v)
    end
    return table.concat(parts, ',')
end

local function decode(text)
    local map = {}
    local order = {}
    for pair in string.gmatch(text or '', '[^,]+') do
        local k, v = string.match(pair, '^([^=]+)=(.*)$')
        if (k ~= nil) then
            map[k] = v
            order[#order + 1] = k
        end
    end
    return map, order
end

-- Nothing changed (gcdisplay's version, jobs, name) and the 3s heartbeat isn't due: skip building the line
-- (me() is LAC's whole gData.GetPlayer). A sub job change without a profile reload is caught by the heartbeat too.
local lastKey = nil
local outSeq, sentSeq = 0, nil -- my last message's seq (gchud.Relay), and the one the state line last carried
local function state_key()
    if (type(disp.Version) ~= 'function') then return nil end
    local mm = AshitaCore:GetMemoryManager()
    local p, party = mm:GetPlayer(), mm:GetParty()
    if (p == nil) or (party == nil) then return nil end
    return disp.Version() .. '|' .. tostring(p:GetMainJob()) .. '|' .. tostring(p:GetSubJob()) .. '|'
        .. tostring(party:GetMemberName(0))
end
local function write_state()
    local key = state_key()
    if (key ~= nil) and (key == lastKey) and (outSeq == sentSeq) and ((os.time() - lastWriteTime) < 3) then return end
    local player = me()
    if (player == nil) then return end
    -- '~' marks a value still at its load default, so readers can hide it.
    local tmap, cmap = disp.GetToggles(), disp.GetCycles()
    for k, v in pairs(tmap) do tmap[k] = (disp.IsDefault('toggle', k) and '~' or '') .. tostring(v) end
    for k, v in pairs(cmap) do
        if (k ~= 'Weapons') and disp.IsDefault('cycle', k) then cmap[k] = '~' .. tostring(v) end
    end
    -- the drop colours this box's weapon
    if (type(disp.WeaponClass) == 'function') then cmap.WpnClass = disp.WeaponClass() end
    local toggles = encode(tmap, gchud.ToggleOrder)
    local cycles = encode(cmap, gchud.CycleOrder)
    local line = table.concat({
        player.Name,
        -- COR99/DNC49, the drop's job text: the levels in effect (LAC's *Sync; *JobLevel is that job's own level,
        -- DNC99)
        tostring(player.MainJob or '?') .. tostring(player.MainJobSync or player.MainJobLevel or '') .. '/'
            .. tostring(player.SubJob or '-') ..
            (((tonumber(player.SubJobSync) or 0) > 0) and tostring(player.SubJobSync) or ''),
        toggles,
        cycles,
    }, '\t')
    local now = os.time()
    if (line == lastLine) and (outSeq == sentSeq) and ((now - lastWriteTime) < 3) then lastKey = key; return end
    local d = dir()
    if not ashita.fs.exists(d) then ashita.fs.create_directory(d) end
    local f = io.open(d .. player.Name .. '.txt', 'w')
    if (f == nil) then return end
    -- after the stamp: my last message's seq, so the others read hud\<Name>.msg only when it moved (a 5-field line
    -- from an older copy: they read it every time, as before)
    f:write(line .. '\t' .. tostring(now) .. '\t' .. tostring(outSeq))
    f:close()
    sentSeq = outSeq
    lastLine = line
    lastWriteTime = now
    lastKey = key
end

-- box name -> its last message's seq, from its state line (nil: an older copy, read its .msg anyway)
local msgSeqOf = {}
local function read_all()
    -- the folder is listed every 5s, not on each read: a new box shows up a few seconds later, nothing else changes
    local now0 = os.clock()
    if (listCache == nil) or (now0 >= listCacheUntil) then listCache, listCacheUntil = listing(), now0 + 5 end
    local files = listCache
    if (type(files) ~= 'table') then return end
    local now, d = os.time(), dir()
    local out = {}
    for _, entry in pairs(files) do
        local fname = (type(entry) == 'string') and string.match(entry, '([^\\/]+)$') or nil
        if (fname ~= nil) and (string.sub(fname, -4) == '.txt') then
            local f = io.open(d .. fname, 'r')
            if (f ~= nil) then
                local text = f:read('*a')
                f:close()
                local parts = {}
                local rest = text or ''
                while true do
                    local at = string.find(rest, '\t', 1, true)
                    if (at == nil) then parts[#parts + 1] = rest; break end
                    parts[#parts + 1] = string.sub(rest, 1, at - 1)
                    rest = string.sub(rest, at + 1)
                end
                local stamp = tonumber(parts[5])
                if (parts[1] ~= nil) and (parts[1] ~= '') then msgSeqOf[parts[1]] = tonumber(parts[6]) end
                if (parts[1] ~= nil) and (parts[1] ~= '') and (stamp ~= nil) and ((now - stamp) <= STALE) then
                    local tmap, torder = decode(parts[3])
                    local cmap, corder = decode(parts[4])
                    out[#out + 1] = {
                        Raw = table.concat(parts, '\t', 1, 4),
                        Name = parts[1],
                        Job = parts[2],
                        Toggles = tmap, ToggleOrder = torder,
                        Cycles = cmap, CycleOrder = corder,
                    }
                end
            end
        end
    end
    -- Order: HUDOwners first (in their order), then party/alliance order, then by name.
    local rank = {}
    for i, n in ipairs(inc.settings.HUDOwners or {}) do rank[string.lower(n)] = i end
    local okp, party = pcall(function() return AshitaCore:GetMemoryManager():GetParty() end)
    for i = 0, 17 do
        local okn, n = pcall(function() return party:GetMemberName(i) end)
        if okp and okn and (type(n) == 'string') and (n ~= '') and (rank[string.lower(n)] == nil) then
            rank[string.lower(n)] = 100 + i
        end
    end
    table.sort(out, function (a, b)
        local ra, rb = rank[string.lower(a.Name)] or 1000, rank[string.lower(b.Name)] or 1000
        if (ra ~= rb) then return ra < rb end
        return a.Name < b.Name
    end)
    -- With HUDOwners set, a box not in it shows only its own line.
    local owners, player = inc.settings.HUDOwners, me()
    if (type(owners) == 'table') and (#owners > 0) and (player ~= nil) then
        local owner = false
        for _, n in ipairs(owners) do
            if (string.lower(n) == string.lower(player.Name)) then owner = true end
        end
        if not owner then
            local mine = {}
            for _, r in ipairs(out) do
                if (string.lower(r.Name) == string.lower(player.Name)) then mine[#mine + 1] = r end
            end
            out = mine
        end
    end
    local raw = {}
    for i, r in ipairs(out) do raw[i] = r.Raw end
    local key = table.concat(raw, '\n')
    if (key == rowsKey) then return end
    rowsKey = key
    rows = out
end

-- Messages: every box keeps its last GoomSwap lines in hud\<Name>.msg, one "seq\tS|E\ttext" per line;
-- the box with the HUD open prints the other boxes' new ones as [Name]. seq is time based, so it keeps rising
-- across reloads; a box seen for the first time has its backlog skipped.
local MSG_KEEP = 10
local outbox, lastSeq, seenSeq = {}, 0, {}

function gchud.Relay(text, isErr)
    local player = me()
    if (player == nil) then return end
    lastSeq = math.max(lastSeq + 1, os.time() * 1000)
    outSeq = lastSeq
    outbox[#outbox + 1] = lastSeq .. '\t' .. (isErr and 'E' or 'S') .. '\t' .. (string.gsub(tostring(text),
        '[\r\n\t]', ' '))
    while (#outbox > MSG_KEEP) do table.remove(outbox, 1) end
    local d = dir()
    if not ashita.fs.exists(d) then ashita.fs.create_directory(d) end
    local f = io.open(d .. player.Name .. '.msg', 'w')
    if (f == nil) then return end
    f:write(table.concat(outbox, '\n'))
    f:close()
end

local function read_msgs()
    local player = me()
    if (player == nil) then return end
    local d = dir()
    for _, row in ipairs(rows) do
        local said = msgSeqOf[row.Name]
        -- its state line says nothing new since the last read: skip the file (first sight: read, to skip its backlog)
        local fresh = (said == nil) or (seenSeq[row.Name] == nil) or (said > seenSeq[row.Name])
        if (row.Name ~= player.Name) and fresh then
            local f = io.open(d .. row.Name .. '.msg', 'r')
            if (f ~= nil) then
                local text = f:read('*a') or ''
                f:close()
                local last = seenSeq[row.Name]
                local top = last or 0
                for line in string.gmatch(text, '[^\n]+') do
                    local seq, kind, msg = string.match(line, '^(%d+)\t([SE])\t(.*)$')
                    seq = tonumber(seq)
                    if (seq ~= nil) then
                        if (last ~= nil) and (seq > last) then
                            print(chat.header(row.Name):append((kind == 'E') and chat.error(msg) or chat.message(msg)))
                        end
                        if (seq > top) then top = seq end
                    end
                end
                seenSeq[row.Name] = top
            elseif (said == 0) and (seenSeq[row.Name] == nil) then
                seenSeq[row.Name] = 0 -- no message yet and no file: nothing to skip, so no read until it says one
            end
        end
    end
end


local function multisend_loaded()
    local pm = AshitaCore:GetPluginManager()
    return (pm ~= nil) and ((pm:Get('Multisend') ~= nil) or (pm:Get('multisend') ~= nil))
end

-- This box runs the command itself; another box gets it through the Multisend plugin.
local function send(name, command)
    nextRead = 0
    local player = me()
    if (player ~= nil) and (string.lower(player.Name) == string.lower(name)) then
        AshitaCore:GetChatManager():QueueCommand(-1, '/lac fwd ' .. command)
    elseif multisend_loaded() then
        AshitaCore:GetChatManager():QueueCommand(-1, '/ms sendto ' .. name .. ' /lac fwd ' .. command)
    else
        print(chat.header('GCHUD'):append(chat.error(name .. ': needs the Multisend plugin (/load multisend)')))
    end
end


local running = false
local function present()
    if (not running) or (inc == nil) or (disp == nil) then return end
    local now = os.clock()
    if (now >= nextWrite) then
        nextWrite = now + 0.25
        pcall(write_state)
    end
    if visible then
        if (now >= nextRead) then
            nextRead = now + 0.5
            local ok, err = pcall(read_all)
            if (ok ~= true) and (gchud.Errors ~= true) then
                gchud.Errors = true
                print(chat.header('GCHUD'):append(chat.error('read failed: ' .. tostring(err))))
            end
            pcall(read_msgs)
        end
    end
end

-- True when <name> is one of my boxes: every box running this engine rewrites hud\<Name>.txt when its modes
-- change and at least every 3s (write_state), so a fresh file means a box that can take '/lac fwd'. Cached 5s per name.
local boxCache = {}
function gchud.IsBox(name)
    if (type(name) ~= 'string') or (name == '') then return false end
    local key = string.lower(name)
    local now = os.time()
    local hit = boxCache[key]
    if (hit ~= nil) and ((now - hit.at) < 5) then return hit.ok end
    local ok = false
    local f = io.open(dir() .. name .. '.txt', 'r')
    if (f ~= nil) then
        -- Name, Job, toggles, cycles, stamp[, message seq]: the 5th field
        local stamp = tonumber(string.match(f:read('*a') or '', '^[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t(%d+)'))
        f:close()
        ok = (stamp ~= nil) and ((now - stamp) <= STALE)
    end
    boxCache[key] = { ok = ok, at = now }
    return ok
end

function gchud.Bind(gcinclude, gcdisplay)
    inc = gcinclude
    disp = gcdisplay
    if (type(disp.SetHud) == 'function') then disp.SetHud(gchud) end
end

-- The drop's lines: every other reporting box (this box's own line is the bar), nil while /gchud is off.
local dropSrc, dropRows = nil, nil
function gchud.DropRows()
    if not visible then return nil end
    if (dropSrc ~= rows) then
        dropSrc, dropRows = rows, {}
        local player = me()
        local mine = (player ~= nil) and string.lower(player.Name) or ''
        for _, r in ipairs(rows) do
            if (string.lower(r.Name) ~= mine) then dropRows[#dropRows + 1] = r end
        end
    end
    return dropRows
end
gchud.Tick = present
gchud.Send = send -- a click on a dropped line: that box runs the command

-- Each box's weapon mode and pick lists, for the bar's right-click menu on its line: hud\<Name>.lists, written once
-- per load (the lists only change with the job file), read when a menu opens.
-- the bar's right-click menus
local PICK_LISTS = { 'Weapons', 'Main', 'Sub', 'Range', 'Ammo', 'MeleeSet', 'WsSet', 'IdleSet', 'NukeSet', 'Weapon',
    'TankSet', 'PupMode' }
local function write_lists()
    local player = me()
    if (player == nil) then return end
    local lines = {}
    for _, k in ipairs(PICK_LISTS) do
        local v = disp.GetCycleValues(k)
        if (type(v) == 'table') and (#v > 1) then lines[#lines + 1] = k .. '\t' .. table.concat(v, '|') end
    end
    local d = dir()
    if not ashita.fs.exists(d) then ashita.fs.create_directory(d) end
    local f = io.open(d .. player.Name .. '.lists', 'w')
    if (f ~= nil) then f:write(table.concat(lines, '\n')); f:close() end
end

-- { [cycle] = { values } } for a box, or nil.
function gchud.Lists(name)
    local f = io.open(dir() .. tostring(name) .. '.lists', 'r')
    if (f == nil) then return nil end
    local out = {}
    for k, v in string.gmatch(f:read('*a') or '', '([%w]+)\t([^\n]*)') do
        local list = {}
        for x in string.gmatch(v, '[^|]+') do list[#list + 1] = x end
        out[k] = list
    end
    f:close()
    return out
end

function gchud.Start()
    pcall(write_lists)
    boxCache = {}
    seenSeq = {}
    rowsKey = nil
    running = true -- present runs from gcinclude.Tick (the engine's one per-frame hook)
    local player = me()
    local owners = inc.settings.HUDOwners
    if (player ~= nil) and (type(owners) == 'table') then
        for _, n in ipairs(owners) do
            if (string.lower(n) == string.lower(player.Name)) then visible = true end
        end
    end
end

function gchud.Stop()
    running = false
    visible = false
end

function gchud.Debug()
    local files, path, mask = listing()
    print(chat.header('GCHUD'):append(chat.message('path: ' .. path)))
    print(chat.header('GCHUD'):append(chat.message('mask used: ' .. tostring(mask))))
    if (type(files) ~= 'table') then
        print(chat.header('GCHUD'):append(chat.error('get_directory returned nothing')))
    else
        for _, entry in pairs(files) do
            print(chat.header('GCHUD'):append(chat.message('file: ' .. tostring(entry))))
        end
    end
    read_all()
    print(chat.header('GCHUD'):append(chat.message('rows parsed: ' .. tostring(#rows))))
    for _, row in ipairs(rows) do
        print(chat.header('GCHUD'):append(chat.message(row.Name .. ' ' .. row.Job)))
    end
end

function gchud.HandleCommand(args)
    local arg = (args[2] ~= nil) and string.lower(args[2]) or nil
    if (arg == 'debug') then
        gchud.Debug()
        return
    end
    if (arg == 'on') then
        visible = true
    elseif (arg == 'off') then
        visible = false
    elseif (arg == nil) then
        visible = not visible
    else
        print(chat.header('GCHUD'):append(chat.error('usage: /gchud [on|off|debug]')))
        return
    end
    nextRead = 0
    if visible and (inc.settings.DisplayBar ~= true) and (type(disp.BarCommand) == 'function') then
        disp.BarCommand({ 'gcbar', 'on' }) -- the drop hangs off the bar
    end
    print(chat.header('GCHUD'):append(chat.message('Drop under the bar: ' .. (visible and 'On' or 'Off'))))
end

return gchud
