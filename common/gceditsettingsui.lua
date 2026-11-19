-- /gcedit Settings: every GoomSwap setting, its value now and where that comes from (the default, the shared file
-- every character uses, this character's char.lua, the job file open in the editor); change one for this character,
-- for every character, or for this job. Below them, the job file's own options (WeaponModes, Packer...).
return function(imgui, palette, set_tip, files, groups, setFile, editorState, feedback)
    -- Not in the defaults table (nil there) but read when set.
    local OPTIONAL = { 'EditorGroups', 'EditorHidden', 'EditorSort', 'EditorOrder', 'DisplayBarX', 'LockstyleSet' }
    local LUA_TEXT = { Theme = true } -- false, or a preset's name: typed as Lua
    local FROM = { own = 'this character', shared = 'every character', default = 'default', job = 'this job' }
    local DOCS = gFunc.LoadFile('common\\gceditsettingsdoc.lua')
    local DOC, JOB = DOCS.settings, DOCS.job -- [key] = { what it does, an example as typed }; job: its own list
    local ADVANCED, LIMITS, JOB_ONLY = DOCS.advanced, DOCS.limits, DOCS.jobOnly
    local BOX_W = 340

    local function job_name() return files.JobFile() or 'the job file' end
    local function target_name(t)
        if t == 'own' then return 'char.lua' end
        if t == 'shared' then return 'goomswap-shared.lua' end
        return job_name()
    end

    -- A value as its box shows it: a text setting as it is, anything else as Lua.
    local function text_of(v, plain)
        if v == nil then return '' end
        if (type(v) == 'string') and plain then return v end
        return groups.SerializeValue(v, setFile.QuoteText, setFile.FormatKey)
    end
    -- Lua data (no code run; T{...} allowed): the value, and whether it read.
    local function data(text)
        local chunk = (loadstring or load)('return ' .. text)
        if chunk == nil then return nil, false end
        if setfenv ~= nil then setfenv(chunk, { T = function(t) return t end }) end
        local ok, v = pcall(chunk)
        return v, ok
    end
    local function same(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= 'table' then return a == b end
        for k, v in pairs(a) do
            if not same(v, b[k]) then return false end
        end
        for k in pairs(b) do
            if a[k] == nil then return false end
        end
        return true
    end
    -- One the panel can write back as it is (tables: what the writer gives reads back the same).
    local function editable(v)
        if (type(v) == 'function') or (type(v) == 'userdata') then return false end
        if type(v) ~= 'table' then return true end
        local back, ok = data(groups.SerializeValue(v, setFile.QuoteText, setFile.FormatKey))
        return ok and same(back, v)
    end
    -- The typed text as a value of the setting's kind (by its default); nil and what it must be when it can't be.
    local function parse(key, text, default)
        local lim = LIMITS[key]
        if ((type(default) == 'number') or (lim ~= nil)) and not LUA_TEXT[key] then
            local n = tonumber(text)
            if n == nil then return nil, 'a number' end
            if lim ~= nil then
                local range = tostring(lim[1]) .. ((lim[2] ~= nil) and ('-' .. lim[2]) or ' or more')
                if (n < lim[1]) or ((lim[2] ~= nil) and (n > lim[2])) then return nil, range end
                if lim[3] and (math.floor(n) ~= n) then return nil, 'a whole number, ' .. range end
            end
            return n
        end
        if (type(default) == 'string') and not LUA_TEXT[key] then return text end
        local v, ok = data(text)
        if (not ok) or (v == nil) then return nil, "Lua data, like { 'a', 'b' } or 'text'" end
        if (type(default) == 'table') and (type(v) ~= 'table') then return nil, 'a table: { ... }' end
        return v
    end

    local function keys()
        local seen, out = {}, {}
        local function add(k)
            if (type(k) == 'string') and not seen[k] then seen[k], out[#out + 1] = true, k end
        end
        for k in pairs(files.Defaults()) do add(k) end
        for k in pairs(files.Layer('shared')) do add(k) end
        for k in pairs(files.Layer('own')) do add(k) end
        for _, k in ipairs(OPTIONAL) do add(k) end
        table.sort(out, function(a, b) return string.lower(a) < string.lower(b) end)
        return out
    end

    -- Long values (Keybinds, ElementalWS) cut to a few lines in a tooltip.
    local function clip(text)
        local lines, out = 0, {}
        for line in string.gmatch(text, '[^\n]+') do
            lines = lines + 1
            if lines > 6 then
                out[#out + 1] = '    ...'
                break
            end
            out[#out + 1] = line
        end
        return table.concat(out, '\n')
    end
    local function how_to(kind, example, lim)
        if kind == 'check' then return 'Tick: on. Untick: off.' end
        if (kind == 'number') or (tonumber(example or '') ~= nil) then
            local range = (lim ~= nil) and (' from ' .. lim[1] .. ((lim[2] ~= nil) and (' to ' .. lim[2]) or ' up')) or ''
            return ((lim ~= nil) and lim[3] and 'A whole number' or 'A number') .. range
                .. (example and (', like: ' .. example) or '.')
        end
        if kind == 'text' then return 'Text as it is, no quotes' .. (example and (', like: ' .. example) or '.') end
        return 'Lua' .. (example and (', like: ' .. example) or (": { 'a', 'b' } or 'text'"))
    end
    -- This job's own line for name, as the tooltip says it.
    local function job_says(name, plain)
        local v, how = files.Job(name)
        if how == 'code' then return '(code in the file: edit it there)' end
        if (how ~= 'staged') and (how ~= 'file') then
            return (how == 'none') and '(not set)' or ('(' .. how .. ': edit it in the file)')
        end
        return ((v == nil) and '(taken out)' or clip(text_of(v, plain))) .. ((how == 'staged') and ' (unsaved)' or '')
    end
    -- What a row's tooltip says: what it does, how to type it (with an example), then each file's value.
    local function tip_of(key, kind, default)
        local doc = DOC[key]
        local plain = (kind == 'text') -- shown as typed
        local function layer(which)
            local v = files.Layer(which)[key]
            return (v == nil) and '(not set)' or clip(text_of(v, plain))
        end
        return ((doc ~= nil) and (doc[1] .. '\n\n') or '') .. how_to(kind, doc and doc[2], LIMITS[key])
            .. '\n\nDefault: ' .. ((default == nil) and '(none)' or clip(text_of(default, plain)))
            .. '\nEvery character: ' .. layer('shared') .. '\nThis character: ' .. layer('own')
            .. '\nThis job (' .. job_name() .. '): ' .. job_says('settings.' .. key, plain)
    end

    -- Saved now (char.lua, the shared file), or staged for the job file's Save.
    local function save(target, key, value, tMeta)
        local ui = editorState.ui
        if target == 'job' then
            files.StageJob('settings.' .. key, value, tMeta)
            feedback(key .. ((value == files.REMOVE) and ' taken out of ' or ' set in ') .. job_name()
                .. ': written by Save.')
            ui.settingsEdit[key] = nil
            return true
        end
        local ok, err = files.Write(target, { [key] = value })
        if ok then
            feedback(key .. ((value == files.REMOVE) and ' cleared' or ' saved') .. ' in ' .. target_name(target)
                .. ': /lac reload to use it everywhere.')
        else
            feedback(key .. ' not saved: ' .. tostring(err) .. '.')
        end
        ui.settingsEdit[key] = nil -- its box shows the new value
        return ok
    end

    -- The value box (or checkbox) of a row; true when its text differs from the value. ed: the row's state.
    local function value_box(id, ed, check, v, example, onCheck)
        if not ed.editable then
            imgui.TextColored(palette.dim, ed.why or '(edit this one in the file)')
            return false
        end
        if check then
            local b = { v == true }
            if imgui.Checkbox('##' .. id, b) then onCheck(b[1]) end
            return false
        end
        local lines = select(2, string.gsub(ed.text[1], '\n', '\n')) + 1
        if (type(v) == 'table') or (lines > 1) then
            imgui.InputTextMultiline('##' .. id, ed.text, 2048, { BOX_W, math.min(8, lines + 1) * 15 + 6 })
        else
            imgui.PushItemWidth(BOX_W)
            imgui.InputTextWithHint('##' .. id, example or '', ed.text, 512) -- empty: the example, greyed
            imgui.PopItemWidth()
        end
        return ed.text[1] ~= ed.base
    end

    local function row(key, target)
        local ui = editorState.ui
        local v, from
        if target == 'job' then v, from = files.GetForJob(key) else v, from = files.Get(key) end
        local default = files.Defaults()[key]
        local plain = (type(default) == 'string') and not LUA_TEXT[key]
        local now = text_of(v, plain)
        local jobHow = (target == 'job') and select(2, files.Job('settings.' .. key)) or nil
        local ed = ui.settingsEdit[key]
        if (ed == nil) or (ed.base ~= now) or (ed.target ~= target) then
            ed = { base = now, text = { now }, target = target, editable = editable(v) } -- read back once
            if (jobHow == 'code') or ((jobHow ~= nil) and string.match(jobHow, '^set in')) then
                ed.editable, ed.why = false, '(' .. ((jobHow == 'code') and 'code' or jobHow) .. ' in the job file: edit it there)'
            end
            ui.settingsEdit[key] = ed
        end
        local check = ((type(v) == 'boolean') or ((v == nil) and (type(default) == 'boolean'))) and not LUA_TEXT[key]
        if ed.tip == nil then -- made when the row's value changes, not every frame
            local kind = check and 'check' or (((type(default) == 'number') and not LUA_TEXT[key]) and 'number')
                or (plain and 'text') or 'lua'
            ed.tip = tip_of(key, kind, default)
        end
        imgui.TextUnformatted(key)
        if imgui.IsItemHovered() then set_tip(ed.tip) end
        imgui.SameLine(200)
        -- a T{} default: this job's line is written T{...} (its methods: HoldExempt:contains)
        local tMeta = (type(default) == 'table') and (getmetatable(default) ~= nil)
        local changed = value_box('set_' .. key, ed, check, v, DOC[key] and DOC[key][2],
            function(b) save(target, key, b, tMeta) end)
        if imgui.IsItemHovered() then set_tip(ed.tip) end
        imgui.SameLine()
        imgui.TextColored(((from == 'own') or (from == 'job')) and palette.ok
            or ((from == 'shared') and palette.blue or palette.dim), FROM[from])
        if changed then
            imgui.SameLine()
            if imgui.SmallButton('Save##set_save_' .. key) then
                local value, want = parse(key, ed.text[1], default)
                if value == nil then feedback(key .. ' must be ' .. want .. '.') else save(target, key, value, tMeta) end
            end
            imgui.SameLine()
            if imgui.SmallButton('Undo##set_undo_' .. key) then ed.text[1] = ed.base end
        end
        local has
        if target == 'job' then
            local jv, how = files.Job('settings.' .. key)
            has = (jv ~= nil) and ((how == 'staged') or (how == 'file'))
        else
            has = (files.Layer(target)[key] ~= nil)
        end
        if has and ed.editable then
            imgui.SameLine()
            if imgui.SmallButton('Clear##set_clear_' .. key) then save(target, key, files.REMOVE) end
            if imgui.IsItemHovered() then
                set_tip('Takes it out of ' .. target_name(target) .. (((target == 'own') or (target == 'job'))
                    and ': the value below it comes back.' or ': the default comes back.'))
            end
        end
        if (target == 'shared') and (from == 'own') then
            imgui.SameLine()
            imgui.TextColored(palette.warn, '(char.lua sets its own here)')
        elseif (target ~= 'job') and (files.Job('settings.' .. key) ~= nil) then
            imgui.SameLine()
            imgui.TextColored(palette.warn, '(' .. job_name() .. ' sets its own)')
        end
    end

    -- A job-file-only option (gcinclude.<name>): staged for Save.
    local function job_row(entry)
        local ui = editorState.ui
        local name, desc, example, unset, readonly = entry[1], entry[2], entry[3], entry[4], entry[5]
        local v, how = files.Job(name)
        local now = text_of(v)
        local id = 'job_' .. name
        local ed = ui.settingsEdit[id]
        if (ed == nil) or (ed.base ~= now) then
            ed = { base = now, text = { now }, editable = editable(v) and not readonly }
            if readonly then ed.why = (v ~= nil) and clip(now) or ('(not set: ' .. tostring(unset) .. ')') end
            if (how == 'code') or string.match(how or '', '^set in') then
                ed.editable, ed.why = false, '(' .. how .. ' in the file: edit it there)'
            end
            ed.tip = desc .. '\n\n' .. (readonly and 'Shown here; changed as it says.' or how_to((example == nil) and 'check' or 'lua', example))
                .. '\n\nNot set: ' .. tostring(unset or 'nothing') .. '\n' .. job_name() .. ': ' .. job_says(name)
            ui.settingsEdit[id] = ed
        end
        imgui.TextUnformatted(name)
        if imgui.IsItemHovered() then set_tip(ed.tip) end
        imgui.SameLine(200)
        local check = (example == nil) and not readonly
        local cur = v
        if check and (cur == nil) then cur = (unset == 'true') end
        local changed = value_box(id, ed, check, cur, example, function(b) files.StageJob(name, b) end)
        if imgui.IsItemHovered() then set_tip(ed.tip) end
        imgui.SameLine()
        imgui.TextColored((how == 'staged') and palette.warn or ((v ~= nil) and palette.ok or palette.dim),
            (how == 'staged') and 'unsaved' or ((v ~= nil) and 'this job' or 'not set'))
        if changed then
            imgui.SameLine()
            if imgui.SmallButton('Save##job_save_' .. name) then
                local value, ok = data(ed.text[1])
                if (not ok) or (value == nil) then
                    feedback(name .. ' must be Lua data, like ' .. tostring(example) .. '.')
                else
                    files.StageJob(name, value)
                    feedback(name .. ' set in ' .. job_name() .. ': written by Save.')
                    ui.settingsEdit[id] = nil
                end
            end
            imgui.SameLine()
            if imgui.SmallButton('Undo##job_undo_' .. name) then ed.text[1] = ed.base end
        end
        if (v ~= nil) and ed.editable then
            imgui.SameLine()
            if imgui.SmallButton('Clear##job_clear_' .. name) then
                files.StageJob(name, files.REMOVE)
                ui.settingsEdit[id] = nil
            end
            if imgui.IsItemHovered() then set_tip('Takes its line out of ' .. job_name() .. ' on Save.') end
        end
    end

    -- A setting's row shows: every one with Show all; else not the advanced ones, unless a file sets it (yours to see).
    local function wanted(key)
        if editorState.ui.settingsAll[1] or not ADVANCED[key] then return true end
        if (files.Layer('own')[key] ~= nil) or (files.Layer('shared')[key] ~= nil) then return true end
        return files.Job('settings.' .. key) ~= nil
    end
    -- A job option's row shows on the jobs that read it, or when the file sets it.
    local function job_wanted(name)
        local only = JOB_ONLY[name]
        if (only == nil) or editorState.ui.settingsAll[1] then return true end
        local abbr = string.match(job_name(), '^(%u%u%u)') -- the job file's name: BRD.lua
        if (abbr ~= nil) and only[abbr] then return true end
        return files.Job(name) ~= nil
    end

    local M = { Parse = parse, Doc = DOC, Job = JOB, Optional = OPTIONAL, LuaText = LUA_TEXT, Advanced = ADVANCED,
        Limits = LIMITS } -- for tests
    -- The window's contents (gcedit opens and closes the window around it).
    function M.Body()
        local ui = editorState.ui
        ui.settingsEdit, ui.settingsFind = ui.settingsEdit or {}, ui.settingsFind or { '' }
        ui.settingsAll = ui.settingsAll or { false }
        ui.settingsTarget = ui.settingsTarget or 'own'
        imgui.TextColored(palette.dim, 'Save to:')
        for _, t in ipairs({ { 'own', 'This character (char.lua)' }, { 'shared', 'Every character (goomswap-shared.lua)' },
            { 'job', 'This job (' .. job_name() .. ')' } }) do
            imgui.SameLine()
            if imgui.SmallButton(((ui.settingsTarget == t[1]) and '> ' or '') .. t[2] .. '##set_target_' .. t[1]) then
                ui.settingsTarget = t[1]
            end
            if imgui.IsItemHovered() then
                set_tip((t[1] == 'job') and ('The job file open in the editor. Changes wait for its Save, like set edits.')
                    or tostring(files.Path(t[1])))
            end
        end
        if imgui.PushTextWrapPos ~= nil then imgui.PushTextWrapPos(0) end
        imgui.TextColored(palette.dim, 'A job file wins over char.lua, and char.lua over the shared file. char.lua and the'
            .. ' shared file are saved at once, after a backup; the job file with Save. Hover a name for what it does.')
        if imgui.PopTextWrapPos ~= nil then imgui.PopTextWrapPos() end
        imgui.PushItemWidth(260)
        imgui.InputTextWithHint('##set_find', 'Find a setting: Hpp, Editor, Moonshade...', ui.settingsFind, 48)
        imgui.PopItemWidth()
        imgui.SameLine()
        imgui.Checkbox('Show all##set_all', ui.settingsAll)
        if imgui.IsItemHovered() then
            set_tip('Also the ones most never change: item names, game data, timing windows, what the heading menus '
                .. 'write. One a file sets, or a search finds, always shows.')
        end
        imgui.Separator()
        imgui.BeginChild('##set_rows', { 0, 0 }, 0)
        local find = string.lower(ui.settingsFind[1] or '')
        local function shown(name) return (find == '') or (string.find(string.lower(name), find, 1, true) ~= nil) end
        for _, key in ipairs(keys()) do
            if shown(key) and ((find ~= '') or wanted(key)) then row(key, ui.settingsTarget) end
        end
        imgui.Separator()
        imgui.TextColored(palette.blue, 'Only in ' .. job_name() .. ' (written by Save)')
        for _, entry in ipairs(JOB) do
            if shown(entry[1]) and ((find ~= '') or job_wanted(entry[1])) then job_row(entry) end
        end
        imgui.EndChild()
    end
    return M
end
