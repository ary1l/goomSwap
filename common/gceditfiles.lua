-- /gcedit: this character's other job files: copy a set's pieces into them, find an item in them. No drawing.
local files = {}

-- Can job (an id: 1 WAR .. 22 RUN) wear item resource r at level (0 or nil: not known)? As LuAshitacast's
-- equip.lua checks it: bit.band(resource.Jobs, 2^job), resource.Level. A Jobs of 0 is taken as not known.
function files.CanWear(r, job, level)
    if (type(r.Jobs) == 'number') and (r.Jobs ~= 0) and (bit.band(r.Jobs, bit.lshift(1, job)) == 0) then
        return false, 'job'
    end
    if (type(level) == 'number') and (level > 0) and (type(r.Level) == 'number') and (r.Level > level) then
        return false, 'Lv' .. r.Level
    end
    return true
end

local function by_lower(model)
    local out = {}
    for _, set in ipairs(model.list) do out[string.lower(set.name)] = set end
    return out
end

-- What copying a set's pieces into each target job file does; nothing is written. o: { name (the set), slots
-- (SCREEN), piece(slot) -> the editor's slot value { kind, name, text, raw } or nil, read(path), parse(text),
-- item(name) -> resource or nil, level(job) }. targets: setFile.JobFiles entries { path, job, name }.
-- Each plan: { file, text, model, set (the file's own, nil: made new), edits, dropped = { { slot, name, why } }, err }.
-- A piece the job can't wear is dropped (that file's own piece in the slot stays); slots this set leaves empty
-- keep that file's own pieces.
function files.PlanCopy(o, targets)
    local out = {}
    for _, file in ipairs(targets) do
        local p = { file = file, edits = {}, dropped = {} }
        p.text = o.read(file.path)
        p.model = (p.text ~= nil) and o.parse(p.text) or nil
        if p.text == nil then
            p.err = 'could not read it'
        elseif p.model == nil then
            p.err = 'no sets table in it'
        else
            local sets = by_lower(p.model)
            p.set = sets[string.lower(o.name)]
            if (p.set ~= nil) and ((p.set.code ~= nil) or p.set.extra or (p.set.close == nil)) then
                p.err = p.set.name .. ' is written as code there'
            elseif (p.set == nil) and (o.parentName ~= nil) then -- a set inside a set (Buffs['X']): into that file's
                p.parent, p.childKey = sets[string.lower(o.parentName)], o.key
                if (p.parent == nil) or (p.parent.code ~= nil) or (p.parent.close == nil)
                    or (p.parent.parentName ~= nil) then
                    p.err = 'no ' .. o.parentName .. ' table there'
                end
            end
        end
        if p.err == nil then
            for _, slot in ipairs(o.slots) do
                local v = o.piece(slot)
                if v ~= nil then
                    local cur = (p.set ~= nil) and p.set.slots[slot] or nil
                    if v.kind ~= 'item' then
                        p.dropped[#p.dropped + 1] = { slot = slot, name = v.raw or '?', why = 'code' }
                    elseif (cur ~= nil) and (cur.value.kind == 'code') then
                        p.dropped[#p.dropped + 1] = { slot = slot, name = v.name, why = 'code there' }
                    else
                        local r = o.item(v.name)
                        local ok, why = true, nil
                        if r ~= nil then ok, why = files.CanWear(r, file.job, o.level(file.job)) end
                        if ok then
                            p.edits[slot] = { kind = 'item', name = v.name, text = v.text or v.raw }
                        else
                            p.dropped[#p.dropped + 1] = { slot = slot, name = v.name, why = why }
                        end
                    end
                end
            end
            if next(p.edits) == nil then p.err = 'nothing in it this job can wear' end
        end
        out[#out + 1] = p
    end
    return out
end

-- Writes each plan without an err: a backup of the file first, and only when the file still parses and compiles.
-- o: { name, setFile, read(path), exists(path), prune(path, backup) or nil }. Returns { { file, ok, err } }.
function files.WriteCopies(o, plans)
    local results, F = {}, o.setFile
    for _, p in ipairs(plans) do
        if p.err == nil then
            local r = { file = p.file }
            local splices = {}
            if o.read(p.file.path) ~= p.text then
                r.err = 'changed on disk since: open the copy again'
            else
                local ok
                if p.set ~= nil then
                    ok = F.AddSlotEdits(p.text, p.set, p.edits, splices)
                elseif p.parent ~= nil then
                    local n = F.ChildName(p.parent.name, p.childKey)
                    ok = F.AddNewSets(p.text, p.model, { { name = n, parentName = p.parent.name, key = p.childKey } },
                        { [n] = p.edits }, splices)
                else
                    ok = F.AddNewSets(p.text, p.model, { { name = o.name } }, { [o.name] = p.edits }, splices)
                end
                local text = ok and F.Apply(p.text, splices) or nil
                if (text == nil) or (F.Parse(text) == nil) or ((loadstring or load)(text) == nil) then
                    r.err = 'the change would break the file'
                else
                    local backup, berr = F.Backups.Path(p.file.path, o.exists)
                    local bok, werr = false, berr
                    if backup ~= nil then bok, werr = F.Write(backup, p.text) end
                    if not bok then
                        r.err = 'backup failed: ' .. tostring(werr)
                    else
                        local wok, err = F.Write(p.file.path, text)
                        if wok then
                            r.ok = true
                            if o.prune ~= nil then o.prune(p.file.path, backup) end
                        else
                            F.Write(p.file.path, p.text)
                            r.err = tostring(err)
                        end
                    end
                end
            end
            results[#results + 1] = r
        end
    end
    return results
end

-- Every set naming item (any case) in the job files: { { file, set, slot } }, by file, then the file's order.
-- Commented-out pieces don't count. read(path), parse(text); slots: SCREEN.
function files.FindItem(name, targets, read, parse, slots)
    local l, out = string.lower(name), {}
    for _, file in ipairs(targets) do
        local text = read(file.path)
        local model = (text ~= nil) and parse(text) or nil
        for _, set in ipairs((model ~= nil) and model.list or {}) do
            for _, slot in ipairs(slots) do
                local cur = set.slots[slot]
                if (cur ~= nil) and (cur.value.kind == 'item') and (string.lower(cur.value.name or '') == l) then
                    out[#out + 1] = { file = file, set = set.name, slot = slot }
                end
            end
        end
    end
    return out
end

return files
