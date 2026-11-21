-- /gcedit's bag scans: every piece of gear you own (bags and Storage Slips), and every equippable item in the game
-- for the picker's search (3+ letters also finds items you don't own). No editor state: the editor keeps what these
-- return.
local bags = {}
local augmentInfo = gFunc.LoadFile('common\\gcaugments.lua')
local rankDecoder = augmentInfo.Rank
local rankData = gFunc.LoadFile('common\\gcaugmentdata.lua')
local storageSlips = gFunc.LoadFile('common\\gcslips.lua') -- what each Storage Slip holds

local BAGS = {
    [0] = 'Inventory',
    'Safe',
    'Storage',
    'Temporary',
    'Locker',
    'Satchel',
    'Sack',
    'Case',
    'Wardrobe',
    'Safe 2',
    'Wardrobe 2',
    'Wardrobe 3',
    'Wardrobe 4',
    'Wardrobe 5',
    'Wardrobe 6',
    'Wardrobe 7',
    'Wardrobe 8',
}
local EQUIP_BAGS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 } -- LAC's default gSettings.EquipBags

local function augments_of(it) -- Keep equip selectors separate from decoded display stats.
    local out = augmentInfo.Read(it, gData.GetAugment)
    local ranked = rankDecoder.Read(it.Extra, rankData)
    if ranked then
        out.rank, out.cap = ranked.rank, ranked.cap
        out.displayAugs = ranked.resolved and ranked.augs or nil
        out.unreadable = not ranked.resolved
    end
    return out
end

local function unity_item(r)
    local description = (r ~= nil) and (r.Description ~= nil) and r.Description[1] or nil
    return (type(description) == 'string') and (string.find(string.lower(description), 'unity ranking', 1, true) ~= nil)
end

-- Every piece of gear in every bag (not Temporary): { id, name, lname, slots, jobs, level, bag, equippable, augs, path
-- }.
local function scan_owned()
    local equippable = {}
    local equipBags = ((gSettings ~= nil) and (type(gSettings.EquipBags) == 'table')) and gSettings.EquipBags
        or EQUIP_BAGS
    for _, c in pairs(equipBags) do
        equippable[c] = true
    end
    local inv, res = AshitaCore:GetMemoryManager():GetInventory(), AshitaCore:GetResourceManager()
    local list, inBag, onSlip = {}, {}, {}
    for c = 0, 16 do
        if c ~= 3 then
            for i = 1, (gData.GetContainerMax(c) or 0) do
                local it = inv:GetContainerItem(c, i)
                local stored = (it ~= nil) and (type(storageSlips) == 'table') and (storageSlips[it.Id] ~= nil)
                    and storageSlips.Contents(it) or nil
                for _, id in ipairs(stored or {}) do
                    onSlip[id] = onSlip[id] or storageSlips.number[it.Id]
                end
                local r = (it ~= nil)
                        and (it.Id ~= 0)
                        and (it.Id ~= 65535) and ((it.Count or 0) > 0) and res:GetItemById(it.Id) or nil
                if (r ~= nil) and (r.Slots ~= 0) and (r.Name ~= nil) and (type(r.Name[1]) == 'string') then
                    local a = augments_of(it)
                    list[#list + 1] = {
                        order = c * 1000 + i, -- bag, then slot: the order the copies were found in
                        id = it.Id,
                        name = r.Name[1],
                        lname = string.lower(r.Name[1]),
                        slots = r.Slots,
                        jobs = r.Jobs,
                        level = r.Level,
                        bag = BAGS[c] or tostring(c),
                        equippable = (equippable[c] == true),
                        augs = a.augs,
                        path = a.path,
                        rank = a.rank,
                        cap = a.cap,
                        displayAugs = a.displayAugs,
                        system = a.system,
                        unreadable = a.unreadable,
                        unity = unity_item(r),
                    }
                    inBag[it.Id] = true
                end
            end
        end
    end
    -- Gear only on a Storage Slip: owned, never equippable from here (retrieve it from the slip).
    for id, number in pairs(onSlip) do
        local r = (not inBag[id]) and res:GetItemById(id) or nil
        if (r ~= nil) and (r.Slots ~= 0) and (r.Name ~= nil) and (type(r.Name[1]) == 'string') then
            list[#list + 1] = { id = id, name = r.Name[1], lname = string.lower(r.Name[1]),
                slots = r.Slots, jobs = r.Jobs,
                level = r.Level, bag = string.format('Slip %02d', number), equippable = false, augs = {},
                    unity = unity_item(r) }
        end
    end
    table.sort(list, function(x, y) if x.lname == y.lname then return x.bag < y.bag end return x.lname < y.lname end)
    -- by name: the first copy in a bag you can equip from, else the first copy (where / game_name, every frame)
    local idx = {}
    for _, g in ipairs(list) do
        local cur = idx[g.lname]
        if (cur == nil) or (g.equippable and not cur.equippable) then idx[g.lname] = g end
        local labels = {}
        g.progress = augmentInfo.Progress(g)
        if g.rank then labels[#labels + 1] = 'R' .. g.rank .. (g.cap and ('/' .. g.cap) or '') end
        if g.path ~= nil then labels[#labels + 1] = 'Path ' .. g.path end
        if #g.augs > 0 then labels[#labels + 1] = 'Aug' end
        if g.unity then
            labels[#labels + 1] = 'Unity'
        end -- Unity Ranking is in the item description, not custom extdata.
        local searchLabel = g.name .. ((#labels > 0) and ('  (' .. table.concat(labels, ', ') .. ')') or '')
        g.search = string.lower(searchLabel .. ' ' .. table.concat(g.displayAugs or g.augs, ' '))
            .. (g.unity and ' unity ranking' or '')
        g.key = g.lname
            .. '\0'
            .. (g.path or '')
            .. '\0'
            .. tostring(g.rank or '')
            .. '\0'
            .. table.concat(g.augs, '\0') -- copies alike in every way
    end
    return list, idx
end

-- Every equippable item in the game, one row per name (the highest level), for the picker's search (3+ letters also
-- finds items you don't own): indexed a slice per frame the first time (all 65535 ids at once hitches the game, as
-- luashitaview found), ~15000 rows, kept while LuAshitacast runs.
local allItems = { done = false, nextId = 1, rows = {}, byName = {} }
local function index_all_items()
    if allItems.done then return true end
    local res = AshitaCore:GetResourceManager()
    local last = math.min(allItems.nextId + 1599, 65534)
    for id = allItems.nextId, last do
        local r = res:GetItemById(id)
        local name = (r ~= nil) and (r.Slots ~= 0) and (r.Name ~= nil) and r.Name[1] or nil
        if (type(name) == 'string') and string.match(name, '%a') then
            local lname, have = string.lower(name), allItems.byName[string.lower(name)]
            if (have == nil) or ((r.Level or 0) >= (have.level or 0)) then
                local g = { id = id, name = name, lname = lname, slots = r.Slots, jobs = r.Jobs, level = r.Level,
                    bag = 'not owned', equippable = false, unowned = true, augs = {}, search = lname,
                        key = 'all\0' .. lname }
                if have == nil then allItems.rows[#allItems.rows + 1] = g else allItems.rows[have.at] = g end
                g.at = (have ~= nil) and have.at or #allItems.rows
                allItems.byName[lname] = g
            end
        end
    end
    allItems.nextId = last + 1
    allItems.done = allItems.nextId > 65534
    return allItems.done
end


bags.AugmentsOf, bags.ScanOwned, bags.IndexAllItems, bags.AllItems = augments_of, scan_owned, index_all_items, allItems
return bags
