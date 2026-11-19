-- LuAshitacast selectors and the editor's rank-progress metadata.
local augmentInfo = {}

function augmentInfo.Read(item, reader)
    local result = { augs = {} }
    local ok, decoded = pcall(reader, item)
    if not ok or type(decoded) ~= 'table' then
        result.unreadable = true
        return result
    end

    result.path = decoded.Path
    result.rank = tonumber(decoded.Rank)
    result.system = decoded.Type

    local seen = {}
    for _, value in pairs(decoded.Augs or {}) do
        local text
        if type(value) == 'string' then
            text = value
        elseif type(value) == 'table' then
            text = value.String
        end

        if type(text) == 'string' and text ~= '' and not seen[text] then
            seen[text] = true
            result.augs[#result.augs + 1] = text
        end
    end

    -- The decoder may use keyed tables; sorting gives identical copies stable keys.
    table.sort(result.augs)
    result.unreadable = result.rank ~= nil and #result.augs == 0
    return result
end

function augmentInfo.Progress(gear)
    if not gear then return nil end

    local cap = tonumber(gear.cap)
    if not cap and gear.system == 'Delve' then cap = 15 end
    if gear.rank == nil then return nil end

    if cap and cap > 0 then
        local unfinished = gear.rank < cap
        local status = unfinished and 'NEEDS RP  ' or 'At current cap: '
        return { unfinished = unfinished, label = status .. 'R' .. gear.rank .. '/' .. cap, }
    end

    return { unfinished = false, unknown = true, label = 'Check RP  R' .. gear.rank .. ' (cap unknown)', }
end

local function hasSelectors(gear, selectors)
    for selector in string.gmatch(selectors, '[^,]+') do
        selector = string.match(selector, '^%s*(.-)%s*$')
        local found = false
        for _, text in ipairs(gear.augs) do
            if text == selector then
                found = true
                break
            end
        end
        if not found then return false end
    end
    return true
end

-- Preserve scan order, preferring a matching copy in an equip-enabled bag.
function augmentInfo.Match(value, owned)
    if not value or not value.name then return nil end

    local best
    for _, gear in ipairs(owned or {}) do
        local matches = gear.lname == string.lower(value.name)
            and (value.path == nil or value.path == gear.path) and (value.rank == nil or value.rank == gear.rank)

        if matches and type(value.augs) == 'string' and value.augs ~= '' then
            matches = hasSelectors(gear, value.augs)
        end
        if matches and (not best or (gear.equippable and not best.equippable)) then best = gear end
    end
    return best
end

-- Rank decoding shares the inventory/selector module; generated data stays separate.
do
-- Decode display stats from the item's system-4 bundle ID, rank, and cap tier.
-- Data provenance and formats are documented in gcaugmentdata.lua.
local rankDecoder = {}
local RANK_CAPS = { 15, 20, 25, 30 }

function rankDecoder.Read(extra, bundles)
    if type(extra) ~= 'string' or #extra < 12 then return nil end

    local itemType = extra:byte(1)
    if (itemType ~= 2 and itemType ~= 3) or extra:byte(2) ~= 131 then return nil end

    local rankByte, tierByte = extra:byte(7, 8)
    local rank = math.floor((rankByte % 128) / 4)
    local tier = math.floor(rankByte / 128) + (tierByte % 2) * 2
    local cap = RANK_CAPS[tier + 1]
    if rank > cap then return nil end

    -- Bytes 9..12 hold the bundle ID as a little-endian uint32.
    local byte1, byte2, byte3, byte4 = extra:byte(9, 12)
    local bundleId = byte1 + byte2 * 256 + byte3 * 65536 + byte4 * 16777216
    local effects = bundles[bundleId]
    local result = { rank = rank, cap = cap, bundle = bundleId, augs = {}, resolved = effects ~= nil, }

    for _, effect in ipairs(effects or {}) do
        local value = effect[2][rank + 1] -- tables include rank zero
        if value and value ~= 0 then
            for _, format in ipairs(effect[1]) do
                result.augs[#result.augs + 1] = string.format(format, value)
            end
        end
    end
    return result
end

augmentInfo.Rank = rankDecoder
end

return augmentInfo
