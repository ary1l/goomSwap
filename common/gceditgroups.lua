-- /gcedit headings: their order and your own headings, from settings.EditorGroups (char.lua). Pure: no game calls.
--
-- settings.EditorGroups = {
--     { 'Weapons', 'Weapon_*' }, -- a heading and the set names it takes ('*': any text; any case)
--     'Idle', 'Defense', 'Melee', -- a heading by name: where it goes in the list
--     { 'Mythic WS', 'Savage Blade', 'Upheaval' },
-- }
-- Listed headings come first, in this order; the built-in ones you leave out follow in their usual order, 'Other'
-- last. A set whose name a heading's pattern takes sits under that heading (the first such heading in the list),
-- else under its built-in one. A heading named like a built-in one (Weapons) is that heading, with more sets.
local groups = {}

-- A pattern as a Lua pattern: magic characters escaped, '*' = any text, whole name, lower case.
local function lua_pattern(p)
    local out = string.gsub(string.lower(p), '[%^%$%(%)%%%.%[%]%+%-%?]', '%%%0')
    out = string.gsub(out, '%*', '.*')
    return '^' .. out .. '$'
end

-- The setting as { { name, patterns = { text... } }... } in order, names once each (any case); junk left out.
function groups.Normalize(setting)
    local out, seen = {}, {}
    for _, e in ipairs((type(setting) == 'table') and setting or {}) do
        local name, patterns = nil, {}
        if type(e) == 'string' then
            name = e
        elseif type(e) == 'table' and type(e[1]) == 'string' then
            name = e[1]
            for i = 2, #e do
                if (type(e[i]) == 'string') and (e[i] ~= '') then patterns[#patterns + 1] = e[i] end
            end
        end
        name = name and string.match(name, '^%s*(.-)%s*$')
        if (name ~= nil) and (name ~= '') then
            local key = string.lower(name)
            if seen[key] == nil then
                seen[key] = { name = name, patterns = patterns }
                out[#out + 1] = seen[key]
            else
                for _, p in ipairs(patterns) do table.insert(seen[key].patterns, p) end
            end
        end
    end
    return out
end

-- Every heading, in list order: the listed ones, then the built-in ones left out (their order; 'Other' last).
-- builtins: the editor's own list, 'Other' among them.
function groups.Order(setting, builtins)
    local out, seen = {}, {}
    for _, h in ipairs(groups.Normalize(setting)) do
        out[#out + 1], seen[string.lower(h.name)] = h.name, true
    end
    local other = nil
    for _, b in ipairs(builtins) do
        if not seen[string.lower(b)] then
            if b == 'Other' then other = b else out[#out + 1] = b end
            seen[string.lower(b)] = true
        end
    end
    if other ~= nil then out[#out + 1] = other end
    return out
end

-- True when name is one of your own headings (not a built-in one).
function groups.IsCustom(name, builtins)
    for _, b in ipairs(builtins) do
        if string.lower(b) == string.lower(name) then return false end
    end
    return true
end

-- Back to setting form: { 'Idle', { 'Weapons', 'Weapon_*' }, ... }.
local function denormalize(list)
    local out = {}
    for _, h in ipairs(list) do
        if #h.patterns == 0 then
            out[#out + 1] = h.name
        else
            local e = { h.name }
            for _, p in ipairs(h.patterns) do e[#e + 1] = p end
            out[#out + 1] = e
        end
    end
    return out
end

-- The full order as a normalized list, every heading in it (so a move keeps the others where they are).
local function full(setting, builtins)
    local byKey = {}
    for _, h in ipairs(groups.Normalize(setting)) do byKey[string.lower(h.name)] = h end
    local out = {}
    for _, name in ipairs(groups.Order(setting, builtins)) do
        out[#out + 1] = byKey[string.lower(name)] or { name = name, patterns = {} }
    end
    return out
end

local function index_of(list, name)
    for i, h in ipairs(list) do
        if string.lower(h.name) == string.lower(name) then return i end
    end
    return nil
end

-- A heading moved by delta places (-1 up, +1 down). New setting, or nil when it can't move.
function groups.Move(setting, builtins, name, delta)
    local list = full(setting, builtins)
    local i = index_of(list, name)
    local j = (i ~= nil) and (i + delta) or nil
    if (j == nil) or (j < 1) or (j > #list) then return nil end
    list[i], list[j] = list[j], list[i]
    return denormalize(list)
end

-- A new heading of yours just below `after` (or at the end). New setting, or nil, why.
function groups.Add(setting, builtins, name, after)
    name = string.match(tostring(name or ''), '^%s*(.-)%s*$')
    if (name == '') or string.find(name, '[\r\n]') then return nil, 'type a name' end
    local list = full(setting, builtins)
    if index_of(list, name) ~= nil then return nil, 'there is a heading ' .. name .. ' already' end
    local at = ((after ~= nil) and index_of(list, after) or #list) + 1
    table.insert(list, at, { name = name, patterns = {} })
    return denormalize(list)
end

-- Your own heading renamed. New setting, or nil, why.
function groups.Rename(setting, builtins, name, newName)
    newName = string.match(tostring(newName or ''), '^%s*(.-)%s*$')
    if (newName == '') or string.find(newName, '[\r\n]') then return nil, 'type a name' end
    if not groups.IsCustom(name, builtins) then return nil, name .. ' is a built-in heading' end
    local list = full(setting, builtins)
    local i = index_of(list, name)
    if i == nil then return nil, 'no heading ' .. name end
    local clash = index_of(list, newName)
    if (clash ~= nil) and (clash ~= i) then return nil, 'there is a heading ' .. newName .. ' already' end
    list[i].name = newName
    return denormalize(list)
end

-- Your own heading taken out: its sets go back to their built-in headings. New setting, or nil, why.
function groups.Remove(setting, builtins, name)
    if not groups.IsCustom(name, builtins) then return nil, name .. ' is a built-in heading' end
    local list = full(setting, builtins)
    local i = index_of(list, name)
    if i == nil then return nil, 'no heading ' .. name end
    table.remove(list, i)
    return denormalize(list)
end

-- One set put under a heading by its exact name, taken off every other heading's exact names ('*' patterns stay;
-- an exact name beats them). heading nil: back to where its name puts it. New setting.
function groups.Place(setting, builtins, setName, heading)
    local list = full(setting, builtins)
    local lname = string.lower(setName)
    for _, h in ipairs(list) do
        local keep = {}
        for _, p in ipairs(h.patterns) do
            if string.lower(p) ~= lname then keep[#keep + 1] = p end
        end
        h.patterns = keep
    end
    if heading ~= nil then
        local i = index_of(list, heading)
        if i == nil then
            list[#list + 1] = { name = heading, patterns = {} }
            i = #list
        end
        table.insert(list[i].patterns, 1, setName)
    end
    return denormalize(list)
end

-- The heading a set goes under: a heading that names it exactly, else the first whose '*' pattern takes it, else
-- builtin (where the editor's own rules put it).
function groups.Assign(setName, builtin, setting)
    local lname = string.lower(setName)
    local list = groups.Normalize(setting)
    for _, h in ipairs(list) do
        for _, p in ipairs(h.patterns) do
            if (string.find(p, '*', 1, true) == nil) and (string.lower(p) == lname) then return h.name end
        end
    end
    for _, h in ipairs(list) do
        for _, p in ipairs(h.patterns) do
            if (string.find(p, '*', 1, true) ~= nil) and (string.find(lname, lua_pattern(p)) ~= nil) then return h.name end
        end
    end
    return builtin
end

-- The heading that names this set exactly (it was moved there), or nil.
function groups.PlacedBy(setting, setName)
    local lname = string.lower(setName)
    for _, h in ipairs(groups.Normalize(setting)) do
        for _, p in ipairs(h.patterns) do
            if (string.find(p, '*', 1, true) == nil) and (string.lower(p) == lname) then return h.name end
        end
    end
    return nil
end

-- == Hidden headings: settings.EditorHidden = { all = { 'Received' }, WAR = { 'Hoxne' } } (all: every job) ==

-- Hidden on this job (an abbreviation, 'WAR')? Also says where: 'all' or the job.
function groups.IsHidden(hidden, name, job)
    local l = string.lower(name)
    for _, key in ipairs({ 'all', job or '' }) do
        local list = (type(hidden) == 'table') and hidden[key] or nil
        for _, n in ipairs((type(list) == 'table') and list or {}) do
            if (type(n) == 'string') and (string.lower(n) == l) then return true, key end
        end
    end
    return false
end

-- A copy of hidden with lists for every key, name taken out of keys (nil: all of them).
local function without(hidden, name, keys)
    local out, l = {}, string.lower(name)
    for k, list in pairs((type(hidden) == 'table') and hidden or {}) do
        if type(list) == 'table' then
            local keep, drop = {}, (keys == nil) or keys[k]
            for _, n in ipairs(list) do
                if (type(n) == 'string') and not (drop and (string.lower(n) == l)) then keep[#keep + 1] = n end
            end
            if #keep > 0 then out[k] = keep end
        end
    end
    return out
end

-- Hidden on key ('all', or a job abbreviation). New table.
function groups.Hide(hidden, name, key)
    local out = without(hidden, name, { [key] = true })
    out[key] = out[key] or {}
    table.insert(out[key], name)
    return out
end

-- Shown again on this job: taken off 'all' and the job's list. New table.
function groups.Unhide(hidden, name, job)
    return without(hidden, name, { all = true, [job or ''] = true })
end

-- == Sorting inside a heading: settings.EditorSort = { Melee = 'az' } ('file' when not set, 'az', 'own'), and for
-- 'own' settings.EditorOrder = { Melee = { 'Tp_Default', 'Tp_Acc' } } (names not listed follow, in file order). ==

-- A heading's value in EditorSort / EditorOrder, its key in any case.
function groups.Get(map, heading)
    if type(map) ~= 'table' then return nil end
    if map[heading] ~= nil then return map[heading] end
    local l = string.lower(heading)
    for k, v in pairs(map) do
        if (type(k) == 'string') and (string.lower(k) == l) then return v end
    end
    return nil
end
local lookup = groups.Get

function groups.SortMode(sort, heading)
    local m = lookup(sort, heading)
    return ((m == 'az') or (m == 'own')) and m or 'file'
end

-- rows ({ name = ... }, file order) sorted for the heading's mode. A new list.
function groups.SortRows(rows, mode, order)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r end
    if mode == 'az' then
        table.sort(out, function(a, b)
            local x, y = string.lower(a.name), string.lower(b.name)
            if x == y then return a.name < b.name end
            return x < y
        end)
    elseif mode == 'own' then
        local at = {}
        for i, n in ipairs((type(order) == 'table') and order or {}) do
            if type(n) == 'string' then at[string.lower(n)] = at[string.lower(n)] or i end
        end
        local file = {}
        for i, r in ipairs(rows) do file[r] = i end
        table.sort(out, function(a, b)
            local x, y = at[string.lower(a.name)], at[string.lower(b.name)]
            if (x ~= nil) and (y ~= nil) then return x < y end
            if (x ~= nil) ~= (y ~= nil) then return x ~= nil end
            return file[a] < file[b]
        end)
    end
    -- a set inside a set (parentName: Buffs['Haste']) stays right after its parent, in file order
    local present, kids, flat = {}, {}, {}
    for _, r in ipairs(out) do present[r.name] = true end
    for _, r in ipairs(rows) do
        if (r.parentName ~= nil) and present[r.parentName] then
            kids[r.parentName] = kids[r.parentName] or {}
            table.insert(kids[r.parentName], r)
        end
    end
    for _, r in ipairs(out) do
        if (r.parentName == nil) or not present[r.parentName] then
            flat[#flat + 1] = r
            for _, k in ipairs(kids[r.name] or {}) do flat[#flat + 1] = k end
        end
    end
    return flat
end

-- A copy of map with heading's value replaced (nil: removed); the key keeps its written case.
function groups.With(map, heading, value)
    local out, l = {}, string.lower(heading)
    for k, v in pairs((type(map) == 'table') and map or {}) do
        if not ((type(k) == 'string') and (string.lower(k) == l)) then out[k] = v end
    end
    out[heading] = value
    return out
end

-- The heading's own order with setName moved delta places (rows: the heading's sets as shown now). nil at an end.
function groups.MoveInOrder(rows, setName, delta)
    local names = {}
    for i, r in ipairs(rows) do names[i] = r.name end
    local i = nil
    for k, n in ipairs(names) do
        if string.lower(n) == string.lower(setName) then i = k end
    end
    local j = (i ~= nil) and (i + delta) or nil
    if (j == nil) or (j < 1) or (j > #names) then return nil end
    names[i], names[j] = names[j], names[i]
    return names
end

-- The heading's own order with setName put just before beforeName (nil: at the end).
function groups.DropInOrder(rows, setName, beforeName)
    local names, moved = {}, nil
    for _, r in ipairs(rows) do
        if string.lower(r.name) == string.lower(setName) then moved = r.name else names[#names + 1] = r.name end
    end
    moved = moved or setName
    local at = #names + 1
    for k, n in ipairs(names) do
        if (beforeName ~= nil) and (string.lower(n) == string.lower(beforeName)) then at = k end
    end
    table.insert(names, at, moved)
    return names
end

-- Any Lua value of strings, numbers, booleans and tables as Lua text (keys sorted, so a file diffs well).
-- quote: the string quoter; key: a key's text (gcsetfile FormatKey).
function groups.SerializeValue(v, quote, key, ind)
    ind = ind or ''
    if type(v) == 'string' then return quote(v) end
    if type(v) ~= 'table' then return tostring(v) end
    local flat, simple = {}, true
    for _, x in ipairs(v) do
        if type(x) == 'table' then simple = false end
        flat[#flat + 1] = groups.SerializeValue(x, quote, key, ind .. '    ')
    end
    local keys = {}
    for k in pairs(v) do
        if (type(k) == 'string') then
            keys[#keys + 1] = k
            if type(v[k]) == 'table' then simple = false end
        end
    end
    table.sort(keys)
    if simple then -- no table inside: one line when it fits ({ Ring2 = "Roller's Ring" })
        if (#flat == 0) and (#keys == 0) then return '{}' end
        local parts = {}
        for _, x in ipairs(flat) do parts[#parts + 1] = x end
        for _, k in ipairs(keys) do parts[#parts + 1] = key(k) .. ' = ' .. groups.SerializeValue(v[k], quote, key, ind) end
        local one = '{ ' .. table.concat(parts, ', ') .. ' }'
        if #one + #ind <= 110 then return one end
    end
    local lines = { '{' }
    for _, x in ipairs(flat) do lines[#lines + 1] = ind .. '    ' .. x .. ',' end
    for _, k in ipairs(keys) do
        lines[#lines + 1] = ind .. '    ' .. key(k) .. ' = ' .. groups.SerializeValue(v[k], quote, key, ind .. '    ') .. ','
    end
    lines[#lines + 1] = ind .. '}'
    return table.concat(lines, '\n')
end

-- The setting as Lua text, for char.lua: one heading a line, indented under ind.
function groups.Serialize(setting, quote, ind)
    ind = ind or ''
    local lines = { '{' }
    for _, e in ipairs(setting or {}) do
        if type(e) == 'string' then
            lines[#lines + 1] = ind .. '    ' .. quote(e) .. ','
        else
            local parts = {}
            for _, s in ipairs(e) do parts[#parts + 1] = quote(s) end
            lines[#lines + 1] = ind .. '    { ' .. table.concat(parts, ', ') .. ' },'
        end
    end
    lines[#lines + 1] = ind .. '}'
    return table.concat(lines, '\n')
end

return groups
