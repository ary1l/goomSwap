-- Text-only job analysis and action/layer models. Job code is never executed.
local models = {}

-- ============================================================================
-- Job
-- ============================================================================
do
-- Read handler references and conditions as text. Job code is never executed.
-- Dependencies: buff-name lookup and the engine's job-specific lists/settings.
local analysis = {}
function analysis.New(options)
    local gearEngine = options.engine
    local HANDLER_EVENT = {
        HandleDefault = 'Default',
        HandlePrecast = 'Precast',
        HandleMidcast = 'Midcast',
        HandleAbility = 'Ability',
        HandleWeaponskill = 'Weaponskill',
        HandlePreshot = 'Preshot',
        HandleMidshot = 'Midshot',
        HandleItem = 'Item',
    }
    local KEYWORD = {
        ['if'] = true,
        ['then'] = true,
        ['elseif'] = true,
        ['else'] = true,
        ['end'] = true,
        ['do'] = true,
        ['function'] = true,
        ['repeat'] = true,
        ['until'] = true,
    }

    local function masked(s) -- string contents blanked (same length), so words and brackets inside them don't count
        s = string.gsub(s, '\\.', '__')
        s = string.gsub(s, "'[^']*'", function(x)
            return "'" .. string.rep('_', #x - 2) .. "'"
        end)
        return (
            string.gsub(s, '"[^"]*"', function(x)
                return '"' .. string.rep('_', #x - 2) .. '"'
            end)
        )
    end

    local function close_paren(m, open) -- the ')' that closes the '(' at open, in a masked text
        local depth = 0
        for i = open, #m do
            local c = string.sub(m, i, i)
            if c == '(' then
                depth = depth + 1
            elseif c == ')' then
                depth = depth - 1
                if depth == 0 then
                    return i
                end
            end
        end
        return nil
    end

    local function trim(s)
        return (string.match(s or '', '^%s*(.-)%s*$'))
    end

    local function unwrap(s) -- '((a and b))' -> 'a and b'
        s = trim(s)
        while (string.sub(s, 1, 1) == '(') and (close_paren(masked(s), 1) == #s) do
            s = trim(string.sub(s, 2, -2))
        end
        return s
    end

    local function split_top(s, sep) -- s split at each top-level sep ('and', 'or' as words; ',')
        local m, parts, depth, last, i = masked(s), {}, 0, 1, 1
        local word = string.match(sep, '^%a+$') ~= nil
        while i <= #m do
            local c = string.sub(m, i, i)
            if (c == '(') or (c == '{') then
                depth = depth + 1
            elseif (c == ')') or (c == '}') then
                depth = depth - 1
            elseif
                (depth == 0)
                and (string.sub(m, i, i + #sep - 1) == sep)
                and (
                    not word
                    or (
                        not string.match(string.sub(m, i - 1, i - 1), '[%w_]')
                        and not string.match(string.sub(m, i + #sep, i + #sep), '[%w_]')
                    )
                )
            then
                parts[#parts + 1] = string.sub(s, last, i - 1)
                last = i + #sep
                i = last - 1
            end
            i = i + 1
        end
        parts[#parts + 1] = string.sub(s, last)
        return parts
    end

    local TOGGLE_TEXT = {
        DTset = 'DT mode',
        MDTset = 'MDT mode',
        Aminon = 'Aminon mode',
        Kite = 'kite mode',
        PROC = 'proc mode',
        TH = 'TH mode',
        SIR = 'SIR mode',
        Burst = 'burst mode',
        Death = 'death mode',
        String = 'harp mode',
        SongLock = 'song lock',
    }
    local CYCLE_TEXT = {
        NukeSet = 'nuke mode',
        Weapon = 'weapon',
        Weapons = 'weapon mode',
        PupMode = 'pup mode',
        TankSet = 'tank mode',
        RangedSet = 'ranged mode',
        Element = 'element',
        Hoxne = 'Hoxne',
    }
    local ACTION_VAR = { ws = true, spell = true, ability = true, action = true }
    local GUARD = {
        target = true,
        player = true,
        spell = true,
        ws = true,
        ability = true,
        action = true,
        me = true,
        env = true,
    }
    local STATUS_TEXT = { Engaged = 'engaged', Idle = 'idle', Resting = 'resting' }

    local function buff_text(arg)
        local lit = string.match(trim(arg), "^'(.-)'$")
        if lit ~= nil then
            return lit
        end
        local id = tonumber(arg)
        if id ~= nil then
            local n = options.buffName(id)
            return ((type(n) == 'string') and (n ~= '')) and (string.gsub(n, '%z+$', '')) or ('buff ' .. id)
        end
        return trim(arg)
    end

    local function cycle_text(name, v)
        if name == 'MeleeSet' then
            return 'melee mode ' .. v
        end
        if name == 'WsSet' then
            return (string.lower(v) == 'high') and 'WS high-buff mode' or ('WS mode ' .. v)
        end
        if name == 'IdleSet' then
            return 'idle mode ' .. v
        end
        return (CYCLE_TEXT[name] or name) .. ' ' .. v
    end

    local function in_list(list, name) -- a T{...} or a plain list, matched without case
        if (type(list) ~= 'table') or (name == nil) then
            return nil
        end
        for _, v in pairs(list) do
            if (type(v) == 'string') and (string.lower(v) == string.lower(name)) then
                return true
            end
        end
        return false
    end

    -- ctx: the action looked at { status (Default: 'Idle' / 'Engaged' / 'Resting', nil = either), action, skill, family };
    -- vars: the handler's locals the conditions read. A verdict: true / false / nil (depends on the moment), and words.
    local eval_cond
    local function eval_atom(a, ctx, vars)
        a = unwrap(a)
        local inner = string.match(a, '^not%s+(.+)$')
        if inner ~= nil then
            local v, t = eval_cond(inner, ctx, vars)
            if v ~= nil then
                return not v, {}
            end
            return nil, { 'not ' .. table.concat(t, ' + ') }
        end
        local cmp = function(op, eq)
            if op == '==' then
                return eq
            end
            return not eq
        end
        -- buffs: gcinclude.BuffCount('X') > 0, or a local that holds it (local sa = gcinclude.BuffCount('Sneak Attack'))
        local arg, op, n = string.match(a, '^gcinclude%.BuffCount%((.-)%)%s*([<>=~]+)%s*(%d+)$')
        local buff = (arg ~= nil) and buff_text(arg) or nil
        if buff == nil then
            local var
            var, op, n = string.match(a, '^([%a_][%w_]*)%s*([<>=~]+)%s*(%d+)$')
            if (var ~= nil) and (vars[var] ~= nil) then
                buff = vars[var].buff
            end
        end
        if buff ~= nil then
            n = tonumber(n)
            if ((op == '>') and (n == 0)) or ((op == '>=') and (n == 1)) or ((op == '~=') and (n == 0)) then
                return nil, { buff .. ' up' }
            end
            if ((op == '==') and (n == 0)) or ((op == '<') and (n == 1)) or ((op == '<=') and (n == 0)) then
                return nil, { buff .. ' not up' }
            end
        end
        local tname, top, tval = string.match(a, "^gcdisplay%.GetToggle%('(%w+)'%)%s*([=~]=)%s*(%a+)$")
        if (tname ~= nil) or string.match(a, "^gcdisplay%.GetToggle%('(%w+)'%)$") then
            tname = tname or string.match(a, "^gcdisplay%.GetToggle%('(%w+)'%)$")
            local on = (top == nil) or cmp(top, tval == 'true')
            local t = TOGGLE_TEXT[tname] or (tname .. ' on')
            return nil, { on and t or ('not ' .. t) }
        end
        local cname, cop, cval = string.match(a, "^gcdisplay%.GetCycle%('(%w+)'%)%s*([=~]=)%s*'(.-)'$")
        if cname == nil then
            local var
            var, cop, cval = string.match(a, "^([%a_][%w_]*)%s*([=~]=)%s*'(.-)'$")
            if (var ~= nil) and (vars[var] ~= nil) and (vars[var].cycle ~= nil) then
                cname = vars[var].cycle
            end
            if (var ~= nil) and (vars[var] ~= nil) and vars[var].family then
                if ctx.family ~= nil then
                    return cmp(cop, string.lower(ctx.family) == string.lower(cval)), {}
                end
                return nil, { (cop == '==') and (cval .. ' spells') or ('not ' .. cval) }
            end
        end
        if cname ~= nil then
            local t = cycle_text(cname, cval)
            return nil, { (cop == '==') and t or ('not ' .. t) }
        end
        local pop, pval = string.match(a, "^pet%.Status%s*([=~]=)%s*'(%a+)'$")
        if pop ~= nil then
            return nil,
                { ((pop == '==') and 'pet ' or 'pet not ') .. (STATUS_TEXT[pval] or string.lower(pval)) }
        end
        local sop, sval = string.match(a, "^player%.Status%s*([=~]=)%s*'(%a+)'$")
        if sop == nil then
            sop, sval = string.match(a, "^gData%.GetPlayer%(%)%.Status%s*([=~]=)%s*'(%a+)'$")
        end
        if sop ~= nil then
            if ctx.status ~= nil then
                return cmp(sop, ctx.status == sval), {}
            end
            local t = STATUS_TEXT[sval] or string.lower(sval)
            return nil, { (sop == '==') and t or ('not ' .. t) }
        end
        if string.match(a, 'IsMoving%s*==%s*true$') or string.match(a, 'IsMoving$') then
            return nil, { 'moving' }
        end
        local avar, aop, aval = string.match(a, "^([%a_]+)%.Name%s*([=~]=)%s*'(.-)'$")
        if (avar ~= nil) and ACTION_VAR[avar] then
            if ctx.action ~= nil then
                return cmp(aop, string.lower(ctx.action) == string.lower(aval)), {}
            end
            return nil, { ((aop == '==') and 'only ' or 'not ') .. aval }
        end
        local mop, who = string.match(a, '^target%.Name%s*([=~]=)%s*(.+)$')
        if
            (mop ~= nil) and ((who == 'me') or (who == 'player.Name') or (who == 'gData.GetPlayer().Name'))
        then
            return nil, { (mop == '==') and 'cast on yourself' or 'cast on someone else' }
        end
        local nv, nop = string.match(a, '^([%a_]+)%s*([=~]=)%s*nil$')
        if nv == 'pet' then
            return nil, { (nop == '~=') and 'pet out' or 'no pet' }
        end
        if nv == 'petAction' then
            return nil, { (nop == '~=') and 'pet using an ability' or 'pet not acting' }
        end
        if (nv ~= nil) and (nop == '~=') and GUARD[nv] then
            return true, {}
        end -- target ~= nil: a guard, not a circumstance
        local wel = string.match(a, "WeatherElement%s*==%s*'(%a+)'$")
        if wel ~= nil then
            return nil, { wel .. ' weather' }
        end
        local del = string.match(a, "DayElement%s*==%s*'(%a+)'$")
        if del ~= nil then
            return nil, { del .. ' day' }
        end
        local kop, kval = string.match(a, "^spell%.Skill%s*([=~]=)%s*'(.-)'$")
        if kop ~= nil then
            if ctx.skill ~= nil then
                return cmp(kop, string.lower(ctx.skill) == string.lower(kval)), {}
            end
            return nil, { ((kop == '==') and '' or 'not ') .. kval .. ' spells' }
        end
        local fop, fval = string.match(a, "^Family%(spell%.Name%)%s*([=~]=)%s*'(.-)'$")
        if fop ~= nil then
            if ctx.family ~= nil then
                return cmp(fop, string.lower(ctx.family) == string.lower(fval)), {}
            end
            return nil, { ((fop == '==') and '' or 'not ') .. fval .. ' spells' }
        end
        if (a == 'gcinclude.BurstWanted()') or ((vars[a] ~= nil) and vars[a].burst) then
            local mb = (gearEngine ~= nil) and gearEngine.settings and gearEngine.settings.MBSkills or nil -- BurstWanted: only these skills
            if (ctx.skill ~= nil) and (in_list(mb, ctx.skill) == false) then
                return false, {}
            end
            return nil, { 'magic burst' }
        end
        if a == 'gcinclude.RangedAcc()' then
            return nil, { 'ranged mode Acc' }
        end
        local blist, barg = string.match(a, '^T%s*(%b{})%s*:%s*contains%((.-)%)$')
        if blist ~= nil then
            local names = {}
            for s in string.gmatch(blist, "'(.-)'") do
                names[#names + 1] = s
            end
            local bv = string.match(barg, '^([%a_]+)%.Name$')
            local fam = (barg == 'Family(spell.Name)') or ((vars[barg] ~= nil) and vars[barg].family)
            if (bv ~= nil) and ACTION_VAR[bv] then
                if ctx.action ~= nil then
                    return in_list(names, ctx.action), {}
                end
                return nil, { 'only ' .. table.concat(names, ', ') }
            elseif fam then
                if ctx.family ~= nil then
                    return in_list(names, ctx.family), {}
                end
                return nil, { table.concat(names, ' / ') .. ' spells' }
            end
        end
        local lname, lvar = string.match(a, '^gcinclude%.([%w_]+)%s*:%s*contains%(([%a_]+)%.Name%)$')
        if (lname ~= nil) and ACTION_VAR[lvar] then
            local v = (ctx.action ~= nil) and (gearEngine ~= nil) and in_list(gearEngine[lname], ctx.action)
                or nil
            if v ~= nil then
                return v, {}
            end
            return nil, { 'a spell in ' .. lname }
        end
        local fvar, fpat = string.match(a, "^string%.%a+%(([%a_]+)%.Name,%s*'(.-)'")
        if (fvar ~= nil) and ACTION_VAR[fvar] then
            if ctx.action ~= nil then
                local ok, hit =
                    pcall(string.find, ctx.action, fpat, 1, string.find(a, '^string%.match') == nil)
                if ok then
                    return (hit ~= nil), {}
                end
            end
            return nil, { 'name has ' .. fpat }
        end
        local nb = string.match(a, '^ByName%((.-)%)$')
        if nb ~= nil then
            return nil, { 'a set for ' .. nb }
        end
        local pct, pn = string.match(a, '([HM]PP)%s*<=?%s*(%d+)$')
        if pct ~= nil then
            return nil, { string.sub(pct, 1, 2) .. ' ' .. pn .. '% or less' }
        end
        return nil, { 'code: ' .. ((#a > 48) and (string.sub(a, 1, 45) .. '...') or a) }
    end

    eval_cond = function(c, ctx, vars)
        c = unwrap(c)
        local ors = split_top(c, 'or')
        if #ors > 1 then
            local texts, anyNil = {}, false
            for _, p in ipairs(ors) do
                local v, t = eval_cond(p, ctx, vars)
                if v == true then
                    return true, {}
                end
                if v == nil then
                    anyNil = true
                    texts[#texts + 1] = table.concat(t, ' + ')
                end
            end
            if not anyNil then
                return false, {}
            end
            return nil, { table.concat(texts, ' or ') }
        end
        local ands = split_top(c, 'and')
        if #ands > 1 then
            local texts, anyNil = {}, false
            for _, p in ipairs(ands) do
                local v, t = eval_cond(p, ctx, vars)
                if v == false then
                    return false, {}
                end
                if v == nil then
                    anyNil = true
                    for _, x in ipairs(t) do
                        texts[#texts + 1] = x
                    end
                end
            end
            if not anyNil then
                return true, {}
            end
            return nil, texts
        end
        return eval_atom(c, ctx, vars)
    end

    -- { [event] = { { kind, arg, frames, vars, line, code } } }: kind 'set' (sets.X, FindSet), 'byname' (ByName), 'mode'
    -- (EquipMode), 'idle' (EquipIdle), 'th' (CheckTH); arg the name or the expression; frames the if-blocks around it.
    local function scan_job(text)
        local out = {}
        local ev, frames, vars, ln, pending = nil, {}, {}, 0, nil
        for raw in string.gmatch(text .. '\n', '(.-)\r?\n') do
            ln = ln + 1
            local h = string.match(raw, '^profile%.(Handle%a+)%s*=%s*function')
            if h ~= nil then
                ev, frames, vars, pending = HANDLER_EVENT[h], {}, {}, nil
                if ev ~= nil then
                    out[ev] = out[ev] or {}
                end
            elseif (ev ~= nil) and string.match(raw, '^end') then
                ev = nil
            elseif ev ~= nil then
                local line, m = raw, masked(raw)
                local cut = string.find(m, '--', 1, true)
                if cut ~= nil then
                    line, m = string.sub(raw, 1, cut - 1), string.sub(m, 1, cut - 1)
                end
                -- locals the conditions read
                local lv, rhs = string.match(line, '^%s*local%s+([%w_,%s]-)%s*=%s*(.+)$')
                if lv ~= nil then
                    local names, vals = split_top(lv, ','), split_top(rhs, ',')
                    for i, v in ipairs(names) do
                        local r, info = trim(vals[i] or ''), nil
                        local buffs = {}
                        for b in string.gmatch(r, 'gcinclude%.BuffCount%((.-)%)') do
                            buffs[#buffs + 1] = buff_text(b)
                        end
                        if #buffs > 0 then
                            info = { buff = table.concat(buffs, ' or ') }
                        elseif string.match(r, "^gcdisplay%.GetCycle%('(%w+)'%)$") then
                            info = { cycle = string.match(r, "'(%w+)'") }
                        elseif r == 'gcinclude.BurstWanted()' then
                            info = { burst = true }
                        elseif string.match(r, '^Family%(') then
                            info = { family = true }
                        end
                        if info ~= nil then
                            vars[trim(v)] = info
                        end
                    end
                end
                -- keywords and set references in line order
                local items = {}
                for pos, w in string.gmatch(m, '()%f[%w_]([%a_]+)%f[^%w_]') do
                    if KEYWORD[w] then
                        items[#items + 1] = { pos = pos, kw = w }
                    end
                end
                local function ref(pos, kind, arg)
                    items[#items + 1] = { pos = pos, kind = kind, arg = arg }
                end
                for pos in string.gmatch(m, '()gcinclude%.EquipIdle%s*%(') do
                    ref(pos, 'idle')
                end
                for pos, n in string.gmatch(line, "()gcinclude%.EquipMode%s*%(%s*'([^']*)'") do
                    ref(pos, 'mode', n)
                end
                for pos in string.gmatch(m, '()gcinclude%.CheckTH%s*%(') do
                    ref(pos, 'th')
                end
                for _, fn in ipairs({ 'ByName', 'FindSet' }) do
                    for pos, open in string.gmatch(m, '()%f[%w_]' .. fn .. '%s*()%(') do
                        local close = close_paren(m, open)
                        if close ~= nil then
                            ref(
                                pos,
                                (fn == 'ByName') and 'byname' or 'set',
                                trim(string.sub(line, open + 1, close - 1))
                            )
                        end
                    end
                end
                for pos, n, after in string.gmatch(line, '()%f[%w_]sets%.([%a_][%w_]*)()') do
                    local before = string.sub(line, pos - 1, pos - 1)
                    if (before ~= '.') and not string.match(string.sub(line, after, after), '[%.%[%w_]') then
                        ref(pos, 'set', "'" .. n .. "'")
                    end
                end
                for pos, q in string.gmatch(line, "()%f[%w_]sets%s*%[%s*(%b'')%s*%]") do
                    if string.sub(line, pos - 1, pos - 1) ~= '.' then
                        ref(pos, 'set', q)
                    end
                end
                for pos, q in string.gmatch(line, '()%f[%w_]sets%s*%[%s*(%b"")%s*%]') do
                    if string.sub(line, pos - 1, pos - 1) ~= '.' then
                        ref(pos, 'set', "'" .. string.sub(q, 2, -2) .. "'")
                    end
                end
                table.sort(items, function(x, y)
                    return x.pos < y.pos
                end)
                for i, it in ipairs(items) do
                    if (it.kw == 'if') or (it.kw == 'elseif') then
                        local stop = #line + 1
                        for j = i + 1, #items do
                            if items[j].kw == 'then' then
                                stop = items[j].pos
                                break
                            end
                        end
                        pending = { kw = it.kw, cond = string.sub(line, it.pos + #it.kw, stop - 1) }
                        if stop > #line then -- 'then' on a later line: the block starts here
                            if pending.kw == 'if' then
                                frames[#frames + 1] = { cond = pending.cond, prior = {} }
                            elseif #frames > 0 then
                                local f = frames[#frames]
                                f.prior[#f.prior + 1] = f.cond
                                f.cond = pending.cond
                            end
                            pending = nil
                        end
                    elseif (it.kw == 'then') and (pending ~= nil) then
                        if pending.kw == 'if' then
                            frames[#frames + 1] = { cond = pending.cond, prior = {} }
                        elseif #frames > 0 then
                            local f = frames[#frames]
                            f.prior[#f.prior + 1] = f.cond
                            f.cond = pending.cond
                        end
                        pending = nil
                    elseif it.kw == 'else' then
                        if #frames > 0 then
                            local f = frames[#frames]
                            f.prior[#f.prior + 1] = f.cond
                            f.cond = nil
                        end
                    elseif (it.kw == 'do') or (it.kw == 'function') or (it.kw == 'repeat') then
                        frames[#frames + 1] = { prior = {} }
                    elseif (it.kw == 'end') or (it.kw == 'until') then
                        frames[#frames] = nil
                    elseif it.kind ~= nil then
                        local snap = {}
                        for _, f in ipairs(frames) do
                            local prior = {}
                            for _, p in ipairs(f.prior) do
                                prior[#prior + 1] = p
                            end
                            snap[#snap + 1] = { cond = f.cond, prior = prior }
                        end
                        -- a reference inside the if's own condition (if not ByName(x) then) is under the blocks before it
                        table.insert(out[ev], {
                            kind = it.kind,
                            arg = it.arg,
                            frames = snap,
                            vars = vars,
                            line = ln,
                            code = trim(line),
                        })
                    end
                end
            end
        end
        return out
    end

    -- An expression naming a set, for the action looked at: the name; else nil, a literal start and the rest of a name
    -- built in code ('Tank_' .. tank), and miss = true when only the action is unknown here (ByName(ws.Name) under Ws_Default).
    local function resolve(e, ctx, vars)
        e = trim(e or '')
        local lit = string.match(e, "^'([^']*)'$") or string.match(e, '^"([^"]*)"$')
        if lit ~= nil then
            return lit
        end
        local v = string.match(e, '^([%a_]+)%.Name$')
        if (v ~= nil) and ACTION_VAR[v] then
            return ctx.action, nil, nil, true
        end
        if e == 'spell.Skill' then
            return ctx.skill, nil, nil, true
        end
        if string.match(e, '^Family%(spell%.Name%)$') or ((vars[e] ~= nil) and vars[e].family) then
            return ctx.family, nil, nil, true
        end
        local left, suffix = string.match(e, "^(.-)%s*%.%.%s*'([^']*)'$")
        if left ~= nil then
            local l, pre, _, miss = resolve(left, ctx, vars)
            if l ~= nil then
                return l .. suffix
            end
            return nil, pre, nil, miss
        end
        local pre, rest = string.match(e, "^'([^']*)'%s*%.%.%s*(.+)$")
        return nil, pre, rest, false
    end
    local function cycle_of(rest, vars) -- the cycle a name's built-in part reads: GetCycle('PupMode'), or a local holding it
        rest = trim(rest or '')
        return string.match(rest, "^gcdisplay%.GetCycle%('(%w+)'%)$")
            or ((vars[rest] ~= nil) and vars[rest].cycle)
            or nil
    end

    return {
        Scan = scan_job,
        Evaluate = eval_cond,
        Resolve = resolve,
        CycleOf = cycle_of,
        CycleText = cycle_text,
        InList = in_list,
        StatusText = STATUS_TEXT,
    }
end

models.Job = analysis
end

-- ============================================================================
-- Actions
-- ============================================================================
do
-- Build action, replacement, and related-set data. No ImGui calls or palette values.
-- The document and inventory are snapshots owned by the editor; callbacks read slots
-- and host resources. Drawing code consumes the returned view data.
local actionModel = {}
function actionModel.New(context)
    local document, inventory = context.document, context.inventory
    local gcdisplay = context.display
    local SCREEN, SLOT_BIT, NUM_SLOT = context.slots, context.slotBits, context.slotNames
    local current, has_set, filled, is_ws =
        context.current, context.hasSet, context.filled, context.isWeaponskill
    local item_id, read_file, gearEngine = context.itemId, context.readFile, context.engine
    local jobLines, jobLinesModel
    local parsed = context.analysis
    local scan_job, eval_cond, resolve = parsed.Scan, parsed.Evaluate, parsed.Resolve
    local cycle_of, cycle_text, in_list, STATUS_TEXT =
        parsed.CycleOf, parsed.CycleText, parsed.InList, parsed.StatusText
    local function layers_of(r)
        local layers, final = {}, {}
        for _, w in ipairs(r.writes) do
            local slot = NUM_SLOT[w.slot] or tostring(w.slot)
            local L = layers[#layers]
            if (L == nil) or (L.by ~= w.by) then
                L = { by = w.by, why = w.why, reason = w.reason, writes = {} }
                layers[#layers + 1] = L
            end
            local entry = { slot = slot, name = w.name, blocked = w.blocked }
            L.writes[#L.writes + 1] = entry
            if not w.blocked then
                local prev = final[slot]
                if prev ~= nil then
                    -- the same piece again is no loss: the earlier layer still put it there
                    if string.lower(prev.name) == string.lower(w.name) then
                        prev.entry.same = true
                    end
                    prev.entry.won = false
                end
                entry.won = true
                final[slot] = { name = w.name, by = w.by, entry = entry, layer = L }
            end
        end
        return layers, final
    end

    local function is_set_label(by, name)
        local l, n = string.lower(by), string.lower(name)
        return (l == n) or (string.sub(l, 1, #n + 1) == (n .. '['))
    end

    -- A record's layer names, lower case, for is_set_label in one lookup: each name and each part before a '['
    -- (Buffs['Aftermath: Lv.3'] also counts as Buffs). Worked out once per record.
    local function labels_of(r)
        local t = r.gcLabels
        if t ~= nil then
            return t
        end
        t = {}
        for _, w in ipairs(r.writes) do
            local l = string.lower(w.by)
            if t[l] == nil then
                t[l] = true
                local at = string.find(l, '[', 1, true)
                while at ~= nil do
                    t[string.sub(l, 1, at - 1)] = true
                    at = string.find(l, '[', at + 1, true)
                end
            end
        end
        r.gcLabels = t
        return t
    end

    -- Records this set was worn in, newest first.
    local function records_for(name)
        local out = {}
        local records = context.getRecords()
        if records == nil then
            return out
        end
        local n = string.lower(name)
        for _, key in ipairs(records.order) do
            local r = records.byKey[key]
            if (r ~= nil) and (r.job == context.job) and labels_of(r)[n] then
                out[#out + 1] = r
            end
        end
        table.sort(out, function(x, y)
            return x.time > y.time
        end)
        return out
    end

    local KIND = {
        Default = '',
        Precast = 'spell, start of cast',
        Midcast = 'spell, as it goes off',
        Ability = 'job ability',
        Weaponskill = 'weapon skill',
        Preshot = 'ranged attack, start',
        Midshot = 'ranged attack, as it fires',
        Item = 'item',
    }
    local STATUS = { Idle = 'standing idle', Engaged = 'fighting (engaged)', Resting = 'resting' }

    local function action_label(r)
        if r.event == 'Default' then
            return STATUS[r.seenKey or r.key] or (r.seenKey or r.key)
        end
        if r.expected and (r.label ~= nil) then
            return r.label
        end -- expected, no action of its own: 'a weapon skill with no set of its own'
        return (r.action or '?') .. '  (' .. (KIND[r.event] or r.event) .. ')'
    end

    local function source_label(by)
        local engine = string.match(by, '^gcinclude%.sets%.(.+)$')
        if engine ~= nil then
            return 'engine set ' .. engine
        end
        local fn = string.match(by, '^(.+)%(%)$')
        if fn ~= nil then
            return ({
                WearWeaponLayer = 'Weapon mode',
                ApplyElementGear = 'Element bonus',
                EquipIdle = 'Idle gear',
                EquipMode = 'Combat mode',
            })[fn] or ('Rule: ' .. fn)
        end
        return by
    end

    -- Why a layer went on, in plain words: from the functions that put it on (rec chain, closest first) and what was
    -- on at the time (r.state). Each line matches the gcinclude code that does it.
    local GENERIC = { ByName = true, EquipMode = true, EquipIdle = true }
    local function has_buff(st, id)
        for _, b in ipairs((st and st.buffs) or {}) do
            if b == id then
                return true
            end
        end
        return false
    end
    local function why(L, r)
        local by, st, cfg = L.by, r.state or {}, (gearEngine ~= nil) and gearEngine.settings or {}
        local engine = string.match(by, '^gcinclude%.sets%.(.+)$')
        local inner = string.match(by, "%['(.+)'%]$")
        local fn = nil
        for _, f in ipairs(L.why or {}) do
            if not GENERIC[f] then
                fn = f
                break
            end
        end
        local first = (L.why or {})[1]
        local R = {
            CheckCommonDebuffs = function()
                if engine == 'Reraise' then
                    return "Weakness is on you (after a raise): the engine's Reraise set"
                end
                if (by == 'Sleeping') or (engine == 'Sleeping') then
                    return 'you are asleep'
                end
                if (by == 'Doomed') or (engine == 'Doomed') then
                    return 'Doom or Bane is on you'
                end
                return 'a status effect on you'
            end,
            CheckIncapacitated = function()
                return 'slept, petrified, stunned or terrorized: your defense set without weapons, then Incapacitated'
            end,
            wear = function()
                if by == 'Idle_Regen' then
                    return string.format(
                        'HP %s%% is below RegenGearHPP %s%%, out of combat',
                        tostring(st.hpp),
                        tostring(cfg.RegenGearHPP)
                    )
                end
                if by == 'Idle_Refresh' then
                    return string.format(
                        'MP %s%% is below RefreshGearMPP %s%%, out of combat',
                        tostring(st.mpp),
                        tostring(cfg.RefreshGearMPP)
                    )
                end
                if by == 'Dt' then
                    return string.format(
                        'HP %s%% is below DTGearHPP %s%%',
                        tostring(st.hpp),
                        tostring(cfg.DTGearHPP)
                    )
                end
                if by == 'Pet_Dt' then
                    return 'pet HP below PetDTGearHPP'
                end
                return 'HP or MP low'
            end,
            SetTownGear = function()
                return 'you are in a town'
            end,
            CheckWeapons = function()
                return 'weapon mode '
                    .. tostring(st.weapons or '?')
                    .. ' (/wm)'
                    .. (
                        (st.status ~= 'Engaged') and '; not fighting, so weapons your idle sets name win'
                        or ''
                    )
            end,
            BuildWeaponLayer = function()
                return 'weapon mode ' .. tostring(st.weapons or '?') .. ' (/wm)'
            end,
            CheckMDT = function()
                return (by == 'mdt') and 'MDT mode (/mdt)' or 'Aminon mode (/aminon)'
            end,
            CheckHoxne = function()
                return 'Hoxne Locked (/hoxne): the Ampulla goes in Ammo'
            end,
            CheckTH = function()
                return 'TH mode (/th): the mob is not tagged yet'
            end,
            CheckReceived = function()
                return 'a spell is coming at you (' .. by .. ')'
            end,
            CheckBuffSets = function()
                return tostring(inner or by) .. ' is up'
            end,
            CheckXIRoll = function()
                return 'standing idle with a roll at 11'
            end,
            CheckLockingRings = function()
                return 'a ring in use stays on (warp, experience...)'
            end,
            CheckMoonshade = function()
                return string.format(
                    'TP %s is below MoonshadeTP %s: Moonshade adds TP to the WS',
                    tostring(st.tp),
                    tostring(cfg.MoonshadeTP)
                )
            end,
            ApplyElementGear = function()
                return 'element bonus: day, weather or distance (obi, Orpheus)'
            end,
            CheckSIR = function()
                return 'SIR mode (/sir): spell interruption'
            end,
            CheckLightBonus = function()
                return 'Healing Magic: LightBonus set'
            end,
            CheckAbsorb = function()
                return 'an Absorb- spell'
            end,
            CheckDaybreak = function()
                return 'Dispelga needs Daybreak in Main'
            end,
            StripWeaponSwaps = function()
                return 'SmartSwap: a light spell keeps your weapons'
            end,
            wearHoxneCombos = function()
                return 'Hoxne Locked + Enchantment up, and the buffs in the name are up'
            end,
            CheckHoxneWs = function()
                return 'Hoxne Locked + Enchantment up: Hoxne WS set'
            end,
            WearHoxne = function()
                local where = string.match(by, '^Hoxne_(%a+)')
                local tail = ({ Dt = ', DT mode (/dt)', Tp = ', fighting', Idle = ', standing idle' })[where or '']
                    or ''
                return 'Hoxne Locked + Enchantment up' .. tail
            end,
            CheckHoxneSets = function()
                return 'Hoxne Locked + Enchantment up'
            end,
            WearChildren = function()
                local key = string.match(by, '_([^_]+)$')
                if key == 'HighBuff' then
                    return 'WS high-buff mode (/wsset high)'
                end
                if key == 'Dt' then
                    return 'DT mode (/dt)'
                end
                if key == 'Self' then
                    return 'the spell is on yourself'
                end
                if key == 'Others' then
                    return 'the spell is on someone else'
                end
                if key == 'Burst' then
                    return 'magic burst: the spell lands in a skillchain'
                end
                return 'a child set of one worn before it'
            end,
            checkDefault = function()
                if by == 'Proc' then
                    return 'Proc mode (/proc) while fighting'
                end
                if by == 'Dt' then
                    return 'DT mode (/dt), over Proc'
                end
                return 'a set you switched on (/rrset, /craftset, /zeniset, /fishset)'
            end,
        }
        if L.reason ~= nil then
            return L.reason
        end -- an expected layer says why itself
        if (fn ~= nil) and (R[fn] ~= nil) then
            return R[fn]()
        end
        if string.match(by, '^Sub ') then
            return by
        end -- 'Sub held: no Dual Wield', 'Sub dropped: ...'
        -- a set the job file (or a helper) wears by name
        if first == 'EquipIdle' then
            if by == 'Idle' then
                return 'base: Idle goes on first, every time'
            end
            return 'idle mode ' .. tostring(st.idleset) .. ' (/idleset), standing idle'
        end
        if first == 'EquipMode' then
            if by == 'Ws_Default' then
                return 'base: every weapon skill starts with it'
            end
            if by == 'Tp_Default' then
                return 'base while fighting'
            end
            if string.match(by, '_Default$') then
                return 'base set'
            end
            return 'melee mode ' .. tostring(st.mset) .. ' (/mset)'
        end
        if
            (st.mset ~= nil)
            and (st.mset ~= 'Default')
            and (string.sub(by, -(#st.mset + 1)) == ('_' .. st.mset))
        then
            return 'melee mode ' .. st.mset .. ' (/mset)'
        end
        if (r.action ~= nil) and (string.lower(by) == string.lower(r.action)) then
            return 'the set named after ' .. r.action
        end
        if (by == 'Dt') or string.match(by, '^Dt_') then
            return 'DT mode (/dt)'
        end
        if by == 'Movement' then
            return st.kite and 'kite mode (/kite)' or 'you are moving'
        end
        if by == 'Resting' then
            return 'you are resting'
        end
        if string.match(by, '^Tp_') then
            return 'fighting (engaged)'
        end
        if string.match(by, '^Weapon_') then
            return 'weapon mode ' .. tostring(st.weapons) .. ' (/wm)'
        end
        if first == 'ByName' then
            return 'your job file wears it by name'
        end
        return 'your job file puts it on'
    end

    local function buff_names(st)
        local out, res = {}, context.resources
        for _, b in ipairs((st and st.buffs) or {}) do
            local n = res:GetString('buffs.names', b)
            if (type(n) == 'string') and (n ~= '') then
                out[#out + 1] = n
            end
        end
        return out
    end

    -- An item as the game spells it ('naegling' -> 'Naegling'): from your bags, else the item's resource, else as written.
    local function game_name(n)
        local g = (inventory.firstByName ~= nil) and inventory.firstByName[string.lower(n)] or nil
        if g ~= nil then
            return g.name
        end
        local id = item_id(n)
        local r = (id ~= nil) and context.resources:GetItemById(id) or nil
        if (r ~= nil) and (r.Name ~= nil) and (type(r.Name[1]) == 'string') and (r.Name[1] ~= '') then
            return r.Name[1]
        end
        return n
    end

    -- The picked record, worked out for drawing: the cover per slot, the table rows, the order list, the missing sets.
    local function layer_view(set, pick)
        if jobLinesModel ~= document.model then
            jobLines, jobLinesModel = nil, document.model
        end
        local V = { rec = pick, set = set.name, ver = document.revision }
        local layers, final = layers_of(pick)
        local mineLost = {} -- this set's piece in a slot, when a later set replaced it
        for _, L in ipairs(layers) do
            if is_set_label(L.by, set.name) then
                for _, w in ipairs(L.writes) do
                    if not w.won and not w.same then
                        mineLost[w.slot] = { name = w.name, blocked = w.blocked }
                    end
                end
            end
        end
        V.cover = {}
        for slot, m in pairs(mineLost) do
            local by = (final[slot] ~= nil) and final[slot].by or '?'
            local short = string.match(by, '^gcinclude%.sets%.(.+)$') or string.match(by, '^(.+)%(%)$') or by
            V.cover[slot] = m.blocked and { short = 'a lock', full = 'a locked slot' }
                or { short = short, full = source_label(by) }
        end
        V.head = 'For ' .. action_label(pick) .. ':'
        if pick.expected then
            local st, on = pick.state, {}
            if (st.mset ~= nil) and (st.mset ~= 'Default') then
                on[#on + 1] = 'melee ' .. st.mset
            end
            if (st.idleset ~= nil) and (st.idleset ~= 'Default') then
                on[#on + 1] = 'idle ' .. st.idleset
            end
            if st.wsset == 'High' then
                on[#on + 1] = 'WS high-buff'
            end
            if st.dt then
                on[#on + 1] = 'DT'
            end
            if st.kite then
                on[#on + 1] = 'kite'
            end
            if st.proc then
                on[#on + 1] = 'proc'
            end
            V.head = 'Expected for ' .. action_label(pick) .. ' (not seen since load):'
            V.state = 'Modes now: '
                .. ((#on > 0) and table.concat(on, ', ') or 'none')
                .. ((pick.as ~= nil) and ('  (' .. pick.as .. ')') or '')
            V.buffs =
                "Your sets as the editor has them, unsaved changes too.\nLeft out until seen: weapons (/wm), Moonshade, obi, TH, buffs, Hoxne, your job file's own logic."
        elseif pick.state ~= nil then
            local st, on = pick.state, {}
            if (st.mset ~= nil) and (st.mset ~= 'Default') then
                on[#on + 1] = 'melee ' .. st.mset
            end
            if st.wsset == 'High' then
                on[#on + 1] = 'WS high-buff'
            end
            if st.dt then
                on[#on + 1] = 'DT'
            end
            if st.mdt then
                on[#on + 1] = 'MDT'
            end
            if st.aminon then
                on[#on + 1] = 'Aminon'
            end
            if st.kite then
                on[#on + 1] = 'kite'
            end
            if st.th then
                on[#on + 1] = 'TH'
            end
            if st.sir then
                on[#on + 1] = 'SIR'
            end
            if st.proc then
                on[#on + 1] = 'proc'
            end
            if st.hoxne == 'Locked' then
                on[#on + 1] = 'Hoxne'
            end
            V.state = string.format(
                'At the time: HP %s%%  MP %s%%  TP %s  |  weapons %s  |  modes on: %s',
                tostring(st.hpp),
                tostring(st.mpp),
                tostring(st.tp),
                tostring(st.weapons or '-'),
                (#on > 0) and table.concat(on, ', ') or 'none'
            )
            local bn = buff_names(st)
            if #bn > 0 then
                V.buffs = 'Buffs/effects on you: ' .. table.concat(bn, ', ')
            end
        end
        local num = {} -- layer -> its number in the order list
        for i, L in ipairs(layers) do
            num[L] = i
        end
        V.rows, V.still = {}, {}
        for _, slot in ipairs(SCREEN) do
            local f = final[slot]
            if (f == nil) and (mineLost[slot] == nil) then
                V.still[#V.still + 1] = slot -- slots no set touched, on one row
            else
                local row = { slot = slot }
                if f == nil then
                    row.worn, row.src, row.sourceRole = nil, 'no set: keeps what you had on', 'dim'
                else
                    row.worn = (f.name == 'ignore') and '(left empty)' or game_name(f.name)
                    local n = ((f.layer ~= nil) and num[f.layer]) and (num[f.layer] .. '. ') or ''
                    if is_set_label(f.by, set.name) then
                        row.src, row.sourceRole = n .. 'this set', 'blue'
                    else
                        local lab = source_label(f.by)
                        row.src, row.sourceRole = n .. lab, string.match(lab, '^engine ') and 'dim' or 'text'
                    end
                end
                local m = mineLost[slot]
                if m ~= nil then
                    row.replacedName = game_name(m.name)
                    row.locked = m.blocked
                end
                V.rows[#V.rows + 1] = row
            end
        end
        V.still = (#V.still > 0) and table.concat(V.still, ' ') or nil
        V.order = {}
        for i, L in ipairs(layers) do
            local won, same, lost = {}, {}, {}
            for _, w in ipairs(L.writes) do
                if w.won then
                    won[#won + 1] = w.slot
                elseif w.same then
                    same[#same + 1] = w.slot
                else
                    lost[#lost + 1] = w.slot
                end
            end
            V.order[i] = {
                title = i .. '. ' .. source_label(L.by),
                rawSource = L.by,
                mine = is_set_label(L.by, set.name),
                why = 'why: ' .. why(L, pick),
                won = (#won > 0) and ('kept: ' .. table.concat(won, ' ')) or nil,
                same = (#same > 0) and ('same piece put on again later: ' .. table.concat(same, ' ')) or nil,
                lost = (#lost > 0) and ('replaced later: ' .. table.concat(lost, ' ')) or nil,
            }
        end
        -- sets looked for and not there: why each was looked for, and what goes on without it
        V.missing, V.variants = {}, {}
        local VARIANT = {
            Self = 'the spell is on you',
            Others = 'the spell is on someone else',
            Burst = 'a magic burst',
            HighBuff = '/wsset high',
        }
        for _, n in ipairs(pick.misses or {}) do
            if (string.find(string.lower(n), '_default_', 1, true) == nil) and not has_set(n) then
                local base, key = string.match(n, '^(.+)_(%a+)$')
                local line = (pick.missLine ~= nil) and pick.missLine[string.lower(n)] or nil
                if (base ~= nil) and (VARIANT[key] ~= nil) and has_set(base) then
                    V.variants[#V.variants + 1] = {
                        name = n,
                        why = 'over '
                            .. base
                            .. ' when '
                            .. VARIANT[key]
                            .. '. Without it: '
                            .. base
                            .. ' alone.',
                    }
                else
                    local m =
                        { name = n, why = 'looked for during this action. Without it: the sets above stay.' }
                    if line ~= nil then
                        jobLines = jobLines or {}
                        if jobLines[0] == nil then
                            local t = read_file(document.path) or ''
                            jobLines[0] = true
                            local i = 0
                            for l in string.gmatch(t .. '\n', '(.-)\r?\n') do
                                i = i + 1
                                jobLines[i] = l
                            end
                        end
                        local code = string.match(jobLines[line] or '', '^%s*(.-)%s*$') or ''
                        m.why = 'your job file looks for it, line '
                            .. line
                            .. ':\n  '
                            .. code
                            .. '\nWithout it: the sets above stay.'
                    end
                    V.missing[#V.missing + 1] = m
                end
            end
        end
        return V
    end

    local SLOT_NUM = {}
    for name, b in pairs(SLOT_BIT) do
        SLOT_NUM[name] = b + 1
    end
    -- Spell skill ids (the spell resource's Skill) to the names LAC's spell.Skill gives (Windower res skills 32-45).
    local SKILL = {
        [32] = 'Divine Magic',
        [33] = 'Healing Magic',
        [34] = 'Enhancing Magic',
        [35] = 'Enfeebling Magic',
        [36] = 'Elemental Magic',
        [37] = 'Dark Magic',
        [38] = 'Summoning Magic',
        [39] = 'Ninjutsu',
        [40] = 'Singing',
        [41] = 'String Instrument',
        [42] = 'Wind Instrument',
        [43] = 'Blue Magic',
        [44] = 'Geomancy',
        [45] = 'Handbell',
    }
    local SKILL_OF = {}
    for _, n in pairs(SKILL) do
        SKILL_OF[string.lower(n)] = n
    end

    local function family(name) -- gcinclude.Family: 'Utsusemi: Ni' -> 'Utsusemi', 'Cure IV' -> 'Cure'
        local base = string.match(name, '^(.-):') or name
        return (string.gsub(base, ' [IVX]+$', ''))
    end

    local function modes_now() -- as gcaction's snapshot reads them
        local st = {}
        if gcdisplay == nil then
            return st
        end
        local function cyc(n)
            local v = gcdisplay.GetCycle(n)
            return (v ~= 'Unknown') and v or nil
        end
        st.mset, st.wsset, st.idleset, st.hoxne = cyc('MeleeSet'), cyc('WsSet'), cyc('IdleSet'), cyc('Hoxne')
        st.weapons = cyc('Weapons') or cyc('Main')
        st.dt, st.kite, st.proc =
            gcdisplay.GetToggle('DTset') == true,
            gcdisplay.GetToggle('Kite') == true,
            gcdisplay.GetToggle('PROC') == true
        return st
    end

    -- The action a set is for, and the modes to show it under: { event, key, action, label, as } or nil.
    -- A mode set (Tp_Acc, Idle_Regen, Savage Blade_HighBuff) is shown as if its mode were on ('as').
    local function action_for(set, st)
        local n, res = set.name, context.resources
        local function mset_of(suffix)
            if suffix == 'HighBuff' then
                st.wsset = 'High'
                return 'as if WS high-buff mode (/wsset high)'
            end
            if suffix == 'Dt' then
                st.dt = true
                return 'as if DT mode (/dt)'
            end
            if suffix == 'Proc' then
                st.proc = true
                return 'as if proc mode (/proc)'
            end
            local modes = {}
            for _, m in ipairs(((gcdisplay ~= nil) and gcdisplay.GetCycleValues('MeleeSet')) or {}) do
                modes[#modes + 1] = m
            end
            for _, m in ipairs(document.newModes or {}) do
                modes[#modes + 1] = m
            end
            for _, m in ipairs(modes) do
                if string.lower(m) == string.lower(suffix) then
                    st.mset = m
                    return 'as if melee mode ' .. m .. ' (/mset)'
                end
            end
            -- not a mode (MNK's _Impetus, _Footwork): the job file wears it by its own logic, which this view leaves out
            return n .. ' is no mode: your job file wears it by its own logic, not shown here'
        end
        if n == 'Idle' then
            return { event = 'Default', key = 'Idle' }
        end
        local im = string.match(n, '^Idle_(%a+)$')
        if im ~= nil then
            st.idleset = im
            return { event = 'Default', key = 'Idle', as = 'as if idle mode ' .. im .. ' (/idleset)' }
        end
        if n == 'Dt' then
            st.dt = true
            return { event = 'Default', key = 'Idle', as = 'as if DT mode (/dt)' }
        end
        if n == 'Movement' then
            st.kite = true
            return { event = 'Default', key = 'Idle', as = 'as if kite mode (/kite)' }
        end
        if n == 'Resting' then
            return { event = 'Default', key = 'Resting' }
        end
        if n == 'Tp_Default' then
            return { event = 'Default', key = 'Engaged' }
        end
        local tm = string.match(n, '^Tp_(.+)$')
        if tm ~= nil then
            return { event = 'Default', key = 'Engaged', as = mset_of(tm) }
        end
        if n == 'Ws_Default' then
            return { event = 'Weaponskill', action = nil, label = 'a weapon skill with no set of its own' }
        end
        local wm = string.match(n, '^Ws_(.+)$')
        if wm ~= nil then
            return { event = 'Weaponskill', label = 'a weapon skill with no set of its own', as = mset_of(wm) }
        end
        if is_ws(n) then
            return { event = 'Weaponskill', action = n }
        end
        local wb, wsuf = string.match(n, '^(.+)_([^_]+)$')
        if (wb ~= nil) and is_ws(wb) then
            return { event = 'Weaponskill', action = wb, as = mset_of(wsuf) }
        end
        if n == 'Precast' then
            return { event = 'Precast', label = 'a spell with no sets of its own, start of cast' }
        end
        if n == 'Midcast' then
            return { event = 'Midcast', label = 'a spell with no sets of its own, as it goes off' }
        end
        local sk = SKILL_OF[string.lower(n)]
        if sk ~= nil then
            return { event = 'Midcast', label = 'any ' .. sk .. ' spell with no set of its own', skill = sk }
        end
        local pre = string.match(n, '^(.+)_Precast$')
        if pre ~= nil then
            local psk = SKILL_OF[string.lower(pre)]
            if psk ~= nil then
                return { event = 'Precast', label = 'any ' .. psk .. ' spell, start of cast', skill = psk }
            end
            local r = res:GetSpellByName(pre, 0)
            if r ~= nil then
                return { event = 'Precast', action = pre, skill = SKILL[r.Skill] }
            end
        end
        local sp = res:GetSpellByName(n, 0)
        if sp ~= nil then
            return { event = 'Midcast', action = n, skill = SKILL[sp.Skill] }
        end
        if res:GetAbilityByName(n, 0) ~= nil then
            return { event = 'Ability', action = n }
        end
        local ab, asuf = string.match(n, '^(.+)_([^_]+)$')
        if (ab ~= nil) and (res:GetAbilityByName(ab, 0) ~= nil) then
            return { event = 'Ability', action = ab, as = mset_of(asuf) }
        end
        return nil
    end

    -- A plain-language summary for the set header. The order and overwrite details remain in Equipped result.
    local function when_description(set)
        local a = action_for(set, modes_now())
        if a == nil then
            return 'No built-in trigger was found. This set is worn only if your job file explicitly equips or combines it; inspect its Handle functions.'
        end
        local description
        if a.event == 'Midcast' then
            if a.action ~= nil then
                description = 'When ' .. a.action .. ' goes off (midcast).'
            elseif a.skill ~= nil then
                description = 'When any ' .. a.skill .. ' spell goes off (midcast).'
            else
                description =
                    'Every spell, as it goes off (midcast). This is the base layer; skill- and spell-specific sets go on afterward and can replace its slots. Empty slots keep the gear already worn, including Precast gear.'
            end
        elseif a.event == 'Precast' then
            if a.action ~= nil then
                description = 'At the start of ' .. a.action .. "'s cast (precast)."
            elseif a.skill ~= nil then
                description = 'At the start of any ' .. a.skill .. ' spell (precast).'
            else
                description = 'At the start of every spell cast (precast).'
            end
        elseif a.event == 'Weaponskill' then
            description = (a.action ~= nil) and ('When using ' .. a.action .. '.')
                or 'When using a weapon skill.'
        elseif a.event == 'Ability' then
            description = 'When using ' .. (a.action or 'this ability') .. '.'
        elseif a.event == 'Default' then
            if set.name == 'Dt' then
                description = 'When DT mode is active.'
            elseif set.name == 'Movement' then
                description = 'When kite mode is active.'
            elseif a.key == 'Idle' then
                description = 'While standing idle.'
            elseif a.key == 'Engaged' then
                description = 'While engaged in combat.'
            elseif a.key == 'Resting' then
                description = 'While resting.'
            end
        end
        description = description or a.label
        if (description ~= nil) and (a.as ~= nil) and (set.name ~= 'Dt') and (set.name ~= 'Movement') then
            description = description .. ' (' .. a.as .. ')'
        end
        return description
    end

    -- An expected record for the set's action (the shape gcaction records have, plus expected = true), or nil.
    local function expected_for(set, preview)
        local st = preview and { mset = 'Default', idleset = 'Default', wsset = 'Default' } or modes_now()
        local a = action_for(set, st)
        if a == nil then
            return nil
        end
        local steps, misses = {}, {}
        local function look(name, why, direct) -- FindSet: worn when the file has it, else a miss (direct: sets.X, no lookup)
            if has_set(name) then
                steps[#steps + 1] = { name = document.model.byLower[string.lower(name)].name, why = why }
                return true
            end
            if not direct then
                misses[#misses + 1] = name
            end
            return false
        end
        local function mode(prefix) -- EquipMode
            look(
                prefix .. '_Default',
                (prefix == 'Ws') and 'base: every weapon skill starts with it' or 'base while fighting'
            )
            if (st.mset ~= nil) and (st.mset ~= 'Default') then
                look(prefix .. '_' .. st.mset, 'melee mode ' .. st.mset .. ' (/mset)')
            end
        end
        local function byname(n, why) -- ByName
            if not has_set(n) then
                misses[#misses + 1] = n
                return false
            end
            look(n, why)
            if (st.mset ~= nil) and (st.mset ~= 'Default') then
                look(n .. '_' .. st.mset, 'melee mode ' .. st.mset .. ' (/mset)')
            end
            return true
        end
        if a.event == 'Default' then
            look('Idle', 'base: Idle goes on first, every time')
            if (a.key == 'Idle') and (st.idleset ~= nil) and (st.idleset ~= 'Default') then
                look('Idle_' .. st.idleset, 'idle mode ' .. st.idleset .. ' (/idleset), standing idle')
            end
            if a.key == 'Engaged' then
                mode('Tp')
            end
            if a.key == 'Resting' then
                look('Resting', 'you are resting', true)
            end
            if st.dt then
                look('Dt', 'DT mode (/dt)', true)
            end
            if st.kite then
                look('Movement', 'kite mode (/kite)', true)
            end
            if st.proc and (a.key == 'Engaged') then -- /proc: Proc in place of all of it (then the weapon mode)
                steps = {}
                look('Proc', 'Proc mode (/proc): in place of your engaged sets', true)
            end
        elseif a.event == 'Weaponskill' then
            mode('Ws')
            if a.action ~= nil then
                byname(a.action, 'the set named after ' .. a.action)
            end
            if st.proc then -- /proc drops the WS gear above: only the proc set, then its _Dt
                steps = {}
                if filled('Ws_Proc') then
                    look('Ws_Proc', 'Proc mode (/proc): in place of the WS gear')
                else
                    look('Proc', 'Proc mode (/proc): in place of the WS gear, no gear in Ws_Proc')
                end
            end
            local worn = {}
            for _, w in ipairs(steps) do
                worn[#worn + 1] = w.name
            end
            local function children(key, why) -- WearChildren: each worn n: n_<key>, and <prefix>_<key> for <prefix>_Default
                local done = {}
                for _, n in ipairs(worn) do
                    local prefix = string.match(n, '^(.-)_[Dd][Ee][Ff][Aa][Uu][Ll][Tt]$')
                    for _, cand in ipairs({
                        n .. '_' .. key,
                        (prefix ~= nil) and (prefix .. '_' .. key) or nil,
                    }) do
                        local l = string.lower(cand)
                        if not done[l] and has_set(cand) then
                            done[l] = true
                            look(cand, why)
                        end
                    end
                end
            end
            if (st.wsset == 'High') and not st.proc then
                children('HighBuff', 'WS high-buff mode (/wsset high)')
            end
            if st.dt and not st.proc then
                children('Dt', 'DT mode (/dt)')
            end
        elseif a.event == 'Ability' then
            byname(a.action, 'the set named after ' .. a.action)
        elseif a.event == 'Precast' then
            look('Precast', 'base: every spell starts with it', true)
            if a.skill ~= nil then
                byname(a.skill .. '_Precast', a.skill .. ": the skill's precast set")
            end
            if a.action ~= nil then
                byname(family(a.action) .. '_Precast', "the spell's own precast set")
            end
        elseif a.event == 'Midcast' then
            look('Midcast', 'base: every spell goes off in it', true)
            if a.skill ~= nil then
                byname(a.skill, a.skill .. ": the skill's set")
            end
            if (a.action ~= nil) and not byname(a.action, 'the set named after ' .. a.action) then
                byname(family(a.action), "the spell's family (" .. family(a.action) .. ')')
            end
        end
        if preview then return steps, a end
        local writes = {}
        for _, step in ipairs(steps) do
            local es = document.model.byName[step.name]
            if (es ~= nil) and (es.code == nil) then
                for _, slot in ipairs(SCREEN) do
                    local v = current(es, slot)
                    if (v ~= nil) and (v.kind == 'item') then
                        writes[#writes + 1] =
                            { slot = SLOT_NUM[slot], name = v.name, by = step.name, reason = step.why }
                    end
                end
            end
        end
        local key = (a.event == 'Default') and a.key
            or ((a.action ~= nil) and (a.event .. ' ' .. a.action) or nil)
        return {
            expected = true,
            key = 'expected ' .. tostring(key),
            seenKey = key,
            event = a.event,
            action = a.action or a.label,
            writes = writes,
            misses = misses,
            state = st,
            as = a.as,
            label = a.label,
        }
    end

    -- Resolve definitions, not recorded item names: selectors and pending edits survive.
    -- Preview routes use neutral modes with the selected variant assumed active.
    local function equipment_for(set, baseName, definitionsOnly)
        local result = { definitions = {}, sources = {}, layers = {}, warnings = {}, pending = false,
            layered = not definitionsOnly, base = baseName }
        local omitted = {}
        local function lookup(name)
            return name and document.model.byLower[string.lower(name)] or nil
        end
        local function route(candidate)
            local steps, action = expected_for(candidate, true)
            if steps then return steps, action, true end
            local parent = lookup(candidate.name:match('^(.+)_[^_]+$'))
            if parent then
                local inherited, event, known = route(parent)
                if known then
                    inherited[#inherited + 1] = { name = candidate.name, why = 'selected variant assumed active' }
                    return inherited, event, true
                end
            end
            local name = string.lower(candidate.name)
            if name == 'town' then
                return { { name = 'Idle' }, { name = candidate.name } }, { event = 'Default' }, true
            elseif name == 'preshot' or name == 'midshot' then
                local ranged = { { name = 'Preshot' } }
                if name == 'midshot' then ranged[#ranged + 1] = { name = candidate.name } end
                return ranged, { event = 'Ranged' }, true
            elseif name:match('^weapon_') then
                return { { name = candidate.name } }, { event = 'Weapon' }, true
            end
            return { { name = candidate.name } }, nil, false
        end
        local function apply(name)
            local layer = lookup(name)
            if not layer then return end
            local deleted = document.deleted and document.deleted[layer.name]
            if layer.new or document.edits[layer.name] or deleted then result.pending = true end
            if deleted then
                if not omitted[layer.name] then
                    result.warnings[#result.warnings + 1] = layer.name .. ' is pending deletion and was omitted.'
                    omitted[layer.name] = true
                end
                return
            end
            if result.layers[#result.layers] == layer.name then return end
            result.layers[#result.layers + 1] = layer.name
            if layer.code or layer.extra then
                result.warnings[#result.warnings + 1] = layer.name .. ' contains Lua/nested gear; affected slots are unknown.'
                for _, slot in ipairs(SCREEN) do
                    result.definitions[slot], result.sources[slot] = { kind = 'code', raw = layer.code or 'nested set' }, layer.name
                end
                return
            end
            for _, slot in ipairs(SCREEN) do
                local value = current(layer, slot)
                if value then result.definitions[slot], result.sources[slot] = value, layer.name end
            end
        end
        if definitionsOnly then apply(set.name); return result end
        local steps, action, known = route(set)
        if baseName then
            local base = lookup(baseName)
            if base then
                local first, _, baseKnown = route(base)
                if baseKnown then apply('Idle') end
                for _, step in ipairs(first) do apply(step.name) end
                apply(base.name)
                if not baseKnown then
                    result.warnings[#result.warnings + 1] = 'Chosen base uses its definition; its custom parent order is unknown.'
                end
            else result.warnings[#result.warnings + 1] = 'Chosen base is unavailable: ' .. baseName end
        elseif known then
            apply('Idle')
            if action and action.event == 'Weaponskill' then apply('Tp_Default') end
        end
        if action and action.event == 'Midcast' then
            local precast = { name = action.action and (action.action .. '_Precast')
                or action.skill and (action.skill .. '_Precast') or 'Precast' }
            local before = expected_for(precast, true)
            for _, step in ipairs(before or {}) do apply(step.name) end
        end
        for _, step in ipairs(steps) do
            if not baseName or string.lower(step.name) ~= 'idle' or string.lower(set.name) == 'idle' then
                apply(step.name)
            end
        end
        local included = false
        for _, name in ipairs(result.layers) do if name == set.name then included = true; break end end
        if not included then apply(set.name) end
        if not known and not baseName then
            result.warnings[#result.warnings + 1] = 'Custom layer order is unknown. Only this definition is shown; choose a base to preview an overlay.'
            result.layered = false
        end
        return result
    end

    local function child(n, key) -- WearChildren's name: X_Default's child is X_<key>
        local prefix = string.match(n, '^(.-)_[Dd][Ee][Ff][Aa][Uu][Ll][Tt]$')
        return ((prefix ~= nil) and prefix or n) .. '_' .. key
    end

    -- The buff combos a Hoxne base takes: each buff alone, and all of them together (A&B, A-Z) when more than one.
    local function combos(buffs)
        local out = {}
        for _, b in ipairs(buffs) do
            out[#out + 1] = b
        end
        if #buffs > 1 then
            local all = {}
            for _, b in ipairs(buffs) do
                all[#all + 1] = b
            end
            table.sort(all)
            out[#out + 1] = table.concat(all, '&')
        end
        return out
    end

    local DEFAULT_KEY = {
        Idle = 'Idle',
        Resting = 'Resting',
        Town = 'Idle',
        XIRoll = 'Idle',
        Tp_Default = 'Engaged',
        Proc = 'Engaged',
    }
    local ENGINE_DEFAULT = {
        mdt = true,
        Aminon = true,
        TH = true,
        Incapacitated = true,
        Sleeping = true,
        Doomed = true,
        Pet_Dt = true,
        Dt = true,
        Movement = true,
    }
    local function what_if(set, o)
        local out, seen, notes, dyn = {}, {}, {}, {}
        local function rank(c) -- one order for every heading: state, modes, Hoxne, buffs, the rest
            if
                STATUS_TEXT[string.gsub(c, '^%l', string.upper)]
                or (c == 'moving')
                or string.match(c, '^idle mode')
            then
                return 1
            end
            if string.match(c, '^melee mode') then
                return 2
            end
            if c == 'WS high-buff mode' then
                return 3
            end
            if c == 'DT mode' then
                return 4
            end
            if c == 'proc mode' then
                return 5
            end
            if c == 'Hoxne' then
                return 6
            end
            if string.match(c, ' up$') then
                return 7
            end
            return 8
        end
        local msetOn = {}
        for _, m in ipairs(o.msets) do
            msetOn[m] = true
        end
        local function allowed(conds) -- the modes ticked (Every mode: all of them)
            for _, c in ipairs(conds) do
                local m = string.match(c, '^melee mode (.+)$')
                if (m ~= nil) and not msetOn[m] then
                    return false
                end
                if
                    ((c == 'DT mode') and not o.dt)
                    or ((c == 'proc mode') and not o.proc)
                    or ((c == 'WS high-buff mode') and not o.high)
                    or ((c == 'Hoxne') and not o.hoxne)
                then
                    return false
                end
            end
            return true
        end
        local function add(name, conds, parent, extra)
            if (name == nil) or (name == '') or not allowed(conds) then
                return false
            end
            local l = string.lower(name)
            if seen[l] then
                return true
            end
            seen[l] = true
            local sorted, dup = {}, {}
            for _, c in ipairs(conds) do
                if not dup[c] then
                    dup[c] = true
                    sorted[#sorted + 1] = c
                end
            end
            table.sort(sorted, function(x, y)
                if rank(x) ~= rank(y) then
                    return rank(x) < rank(y)
                end
                return x < y
            end)
            local w = { name = name, conds = sorted, parent = parent, self = (l == set.lname) }
            for k, v in pairs(extra or {}) do
                w[k] = v
            end
            out[#out + 1] = w
            return true
        end
        local function plus(conds, ...) -- conds + more, as a new list
            local t = {}
            for _, x in ipairs(conds) do
                t[#t + 1] = x
            end
            for _, x in ipairs({ ... }) do
                t[#t + 1] = x
            end
            return t
        end
        local function mset(m)
            return 'melee mode ' .. m
        end
        local worn = {} -- the job file's sets, in order: their children (_HighBuff, _Dt, _Self...) come after
        local function wear(name, conds, parent, extra)
            if add(name, conds, parent, extra) then
                worn[#worn + 1] = { name, conds }
            end
        end
        -- base and its /mset variants (ByName / EquipMode; under: EquipMode's prefix, Ws_Default -> Ws_Acc)
        local function with_msets(base, conds, parent, under, extra)
            wear(base, conds, parent, extra)
            for _, m in ipairs(o.msets) do
                wear(under and (under .. '_' .. m) or (base .. '_' .. m), plus(conds, mset(m)), base, extra)
            end
        end
        local OPPOSITE =
            { ['cast on yourself'] = 'cast on someone else', ['cast on someone else'] = 'cast on yourself' }
        local function children(key, cond, from) -- WearChildren: each worn n: n_<key> (X_Default: X_<key>)
            for _, w in ipairs(from) do
                local clash = false
                for _, c in ipairs(w[2]) do
                    if OPPOSITE[c] == cond then
                        clash = true
                    end
                end -- Self_Cure_Others: never
                if not clash then
                    add(child(w[1], key), plus(w[2], cond), w[1])
                end
            end
        end
        -- a Hoxne base (WearHoxne / CheckHoxneWs): itself, its /mset, its buff combos (the file's own and the buffs typed)
        local function hoxne(bases, dtKids)
            local keep = worn
            worn = {}
            for _, b in ipairs(bases) do
                with_msets(b[1], b[2], nil)
            end
            for _, b in ipairs(bases) do
                local cs, have = {}, {}
                for _, c in ipairs(combos(o.buffs)) do
                    cs[#cs + 1] = c
                    have[string.lower(c)] = true
                end
                local pre = string.lower(b[1]) .. '_'
                for _, s in ipairs(document.model.list) do -- Hoxne_Tp_Impetus, Hoxne_Ws_Impetus&Footwork: any buff name
                    if (s.parentName == nil) and (string.sub(s.lname, 1, #pre) == pre) then
                        local rest = string.sub(s.name, #pre + 1)
                        local isMode = msetOn[rest] or (rest == 'Dt') or (rest == 'HighBuff')
                        for _, m in ipairs(o.msets) do
                            if string.sub(rest, -(#m + 1)) == ('_' .. m) then
                                isMode = true
                            end
                        end
                        if string.match(rest, '_Dt$') then
                            isMode = true
                        end
                        if not isMode and not have[string.lower(rest)] then
                            have[string.lower(rest)] = true
                            cs[#cs + 1] = rest
                        end
                    end
                end
                for _, c in ipairs(cs) do
                    with_msets(b[1] .. '_' .. c, plus(b[2], (string.gsub(c, '&', ' + ')) .. ' up'), b[1])
                end
            end
            if dtKids and o.dt then
                children('Dt', 'DT mode', worn)
            end
            worn = keep
        end
        local name = set.name
        if string.match(name, '^Hoxne_') then
            local base = string.match(name, '^(Hoxne_[^_]+)') or name
            hoxne({ { base, { 'Hoxne' } } }, (base == 'Hoxne_Ws') or is_ws(string.sub(base, 7)))
            return out
        end

        -- the action this set is for (action_for: by its name; else the handler of the job file that names it)
        local a = action_for(set, {})
        if
            (a == nil)
            and (
                (DEFAULT_KEY[name] ~= nil)
                or ENGINE_DEFAULT[name]
                or string.match(name, '_Received$')
                or string.match(name, '^Weapon_')
            )
        then
            a = { event = 'Default', key = DEFAULT_KEY[name] }
        end
        if document.model.scan == nil then -- read once per file
            local ok, r = pcall(scan_job, document.model.text or '')
            document.model.scan = ok and r or {}
        end
        local scan = document.model.scan
        if a == nil then
            -- A custom set can appear in several handlers. Follow source order
            -- rather than table hash order, which changes between Lua runtimes.
            local firstLine = math.huge
            for event, refs in pairs(scan) do
                for _, reference in ipairs(refs) do
                    if
                        reference.line < firstLine
                        and string.lower(resolve(reference.arg, {}, reference.vars) or '') == set.lname
                    then
                        a, firstLine = { event = event }, reference.line
                    end
                end
            end
        end
        if a == nil then -- worn by name (an ability or spell the resources don't know?): its /mset variants
            with_msets(name, {}, nil)
            return out
        end
        local ev = a.event
        if
            (ev == 'Default')
            and (a.key == 'Idle')
            and not (string.match(name, '^Idle') or (name == 'Resting') or (name == 'Town'))
        then
            a.key = nil
        end
        local ctx = { status = (ev == 'Default') and a.key or nil, action = a.action, skill = a.skill }
        if ctx.action ~= nil then
            ctx.family = family(ctx.action)
            if (ctx.skill == nil) and ((ev == 'Midcast') or (ev == 'Precast')) then
                local r = context.resources:GetSpellByName(ctx.action, 0)
                if r ~= nil then
                    ctx.skill = SKILL[r.Skill]
                end
            end
        end
        local function st(s) -- a status as a condition, when the view covers more than one
            if ctx.status == nil then
                return { STATUS_TEXT[s] }
            end
            if ctx.status == s then
                return {}
            end
            return nil
        end

        -- 1. the job file's handler, line by line
        local refs = scan[ev]
        if refs ~= nil then
            for _, r in ipairs(refs) do
                local ok, conds = true, {}
                for _, f in ipairs(r.frames) do
                    for _, p in ipairs(f.prior) do
                        if eval_cond(p, ctx, r.vars) == true then
                            ok = false
                        end
                    end
                    if f.cond ~= nil then
                        local v, t = eval_cond(f.cond, ctx, r.vars)
                        if v == false then
                            ok = false
                        end
                        for _, x in ipairs(t) do
                            conds[#conds + 1] = x
                        end
                    end
                end
                if ok then
                    local extra = { src = 'job', line = r.line, code = r.code }
                    if r.kind == 'idle' then
                        local c = st('Idle')
                        wear('Idle', conds, nil, extra)
                        if c ~= nil then
                            for _, m in ipairs({ 'Refresh', 'Regen', 'Regain' }) do
                                wear('Idle_' .. m, plus(conds, 'idle mode ' .. m, unpack(c)), 'Idle', extra)
                            end
                        end
                    elseif r.kind == 'mode' then
                        local c = (r.arg == 'Tp') and st('Engaged') or {}
                        if c ~= nil then
                            with_msets(r.arg .. '_Default', plus(conds, unpack(c)), nil, r.arg, extra)
                        end
                    elseif r.kind == 'th' then
                        add('TH', plus(conds, 'TH mode'), nil, extra)
                    else
                        local n, pre, rest, miss = resolve(r.arg, ctx, r.vars)
                        local cyc = (n == nil) and (pre ~= nil) and (pre ~= '') and cycle_of(rest, r.vars)
                            or nil
                        if n ~= nil then
                            if r.kind == 'byname' then
                                with_msets(n, conds, nil, nil, extra)
                            else
                                wear(n, conds, nil, extra)
                            end
                        elseif cyc ~= nil then -- 'Tank_' .. tank: each set of the file with that start, one per mode
                            local lp = string.lower(pre)
                            for _, s in ipairs(document.model.list) do
                                local val = string.sub(s.name, #pre + 1)
                                if
                                    (s.parentName == nil)
                                    and (string.sub(s.lname, 1, #lp) == lp)
                                    and (val ~= '')
                                    and not string.find(val, '_', 1, true)
                                then
                                    local c = plus(conds, cycle_text(cyc, val))
                                    if r.kind == 'byname' then
                                        with_msets(s.name, c, nil, nil, extra)
                                    else
                                        wear(s.name, c, nil, extra)
                                    end
                                end
                            end
                        elseif not miss and string.find(r.arg, '..', 1, true) then
                            dyn[#dyn + 1] = 'line ' .. r.line .. ': ' .. r.code
                        end
                    end
                end
            end
        end

        -- 2. the engine's layers after the job file (gcinclude: WrapHoldHandlers, CheckDefault)
        if ev == 'Weaponskill' then
            -- /proc drops the job's WS gear: only Ws_Proc (else Proc) goes on; no _HighBuff, _Dt, Hoxne or Buffs_Ws
            local jobWorn = {}
            for _, w in ipairs(worn) do
                jobWorn[#jobWorn + 1] = w
            end
            worn = {}
            wear('Ws_Proc', { 'proc mode' }, nil, { proc = true })
            if not filled('Ws_Proc') then
                wear('Proc', { 'proc mode', 'no gear in Ws_Proc' }, nil, { proc = true })
            end -- FindFilled
            local procWorn = worn
            worn = jobWorn
            if o.high then
                children('HighBuff', 'WS high-buff mode', jobWorn)
            end
            if o.dt then
                children('Dt', 'DT mode', jobWorn)
            end -- the proc sets take no _Dt
            if o.hoxne then
                local bases = { { 'Hoxne_Ws', { 'Hoxne' } } }
                if ctx.action ~= nil then
                    bases[2] = { 'Hoxne_' .. ctx.action, { 'Hoxne' } }
                end
                hoxne(bases, true)
            end
            notes[#notes + 1] =
                "Buffs_Ws: a set per buff (Buffs_Ws = { ['Aftermath: Lv.3'] = {...} }), listed under Buffs_Ws."
        elseif ev == 'Midcast' then
            -- WearChildren over every set the handler wore; left out: TH, idle/weapon swaps (Idle_Staff) and a set that
            -- already carries the word (Burst, Self_Cure: no Burst_Burst)
            local function kids(key, cond)
                local from = {}
                for _, w in ipairs(worn) do
                    local l = string.lower(w[1])
                    if
                        (l ~= 'th')
                        and not string.match(l, '^idle')
                        and not string.match(l, '^weapon_')
                        and not string.find(l, string.lower(key), 1, true)
                    then
                        from[#from + 1] = w
                    end
                end
                children(key, cond, from)
            end
            kids('Self', 'cast on yourself')
            kids('Others', 'cast on someone else')
            local mb = (gearEngine ~= nil) and gearEngine.settings and gearEngine.settings.MBSkills or nil
            if (ctx.skill == nil) or (in_list(mb, ctx.skill) ~= false) then
                kids('Burst', 'magic burst')
            end -- MBSkills only
            if
                ((ctx.action == nil) and ((ctx.skill == nil) or (ctx.skill == 'Dark Magic')))
                or ((ctx.action ~= nil) and (string.sub(ctx.action, 1, 7) == 'Absorb-'))
            then
                local c = (ctx.action == nil) and { 'an Absorb- spell' } or {}
                add('Absorb', c)
                if (ctx.action == nil) or (ctx.action == 'Absorb-TP') then
                    add('Absorb_TP', plus(c, (ctx.action == nil) and 'Absorb-TP' or nil))
                end
            end
            if (ctx.skill == nil) or (ctx.skill == 'Healing Magic') then
                add('LightBonus', (ctx.skill == nil) and { 'Healing Magic spells' } or {})
            end
            add('SIR', { 'SIR mode' })
            notes[#notes + 1] = 'Buffs_Midcast: a set per buff, listed under Buffs_Midcast.'
        elseif ev == 'Default' then
            local eng, idle = st('Engaged'), st('Idle')
            if eng ~= nil then
                add('Proc', plus(eng, 'proc mode'), nil, { proc = 'engaged' })
            end -- in place of the rest
            if o.hoxne then
                hoxne({ { 'Hoxne_Dt', { 'Hoxne', 'DT mode' } } }, false)
                if eng ~= nil then
                    hoxne({ { 'Hoxne_Tp', plus(eng, 'Hoxne') } }, false)
                end
                if idle ~= nil then
                    hoxne({ { 'Hoxne_Idle', plus(idle, 'Hoxne') } }, false)
                end
            end
            local cfg = (gearEngine ~= nil) and gearEngine.settings or {}
            add('Idle_Regen', {
                'HP under RegenGearHPP'
                    .. (((cfg.RegenGearHPP or 0) > 0) and (' ' .. cfg.RegenGearHPP .. '%') or ' (off)'),
                'not fighting',
            })
            add('Idle_Refresh', {
                'MP under RefreshGearMPP'
                    .. (((cfg.RefreshGearMPP or 0) > 0) and (' ' .. cfg.RefreshGearMPP .. '%') or ' (off)'),
                'not fighting',
            })
            add('Dt', { 'HP under DTGearHPP' })
            if has_set('Pet_Dt') then
                add('Pet_Dt', { 'pet HP under PetDTGearHPP' })
            end -- pet jobs' files have one
            if (idle ~= nil) or (ctx.status == 'Resting') then
                add('Town', { 'in a town' })
            end
            local modes = {}
            local p = context.getPlayer()
            if
                (gearEngine ~= nil)
                and (type(gearEngine.WeaponModes) == 'table')
                and (p ~= nil)
                and (context.job == p:GetMainJob())
            then
                for _, m in ipairs(gearEngine.WeaponModes) do
                    if (type(m) == 'string') and (m ~= 'None') then
                        modes[#modes + 1] = m
                    end
                end
            else
                for _, s in ipairs(document.model.list) do
                    local m = string.match(s.name, '^Weapon_([^_]+)$')
                    if m ~= nil then
                        modes[#modes + 1] = m
                    end
                end
            end
            for _, m in ipairs(modes) do
                local c = { 'weapon mode ' .. m }
                add('Weapon_' .. m, c)
                add('Weapon_' .. m .. '_1h', plus(c, 'no Dual Wield'), 'Weapon_' .. m)
                for _, ms in ipairs(o.msets) do
                    add('Weapon_' .. m .. '_' .. ms, plus(c, mset(ms)), 'Weapon_' .. m)
                end
            end
            add('mdt', { 'MDT mode' })
            add('Aminon', { 'Aminon mode' }) -- empty: mdt (FindFilled)
            add('TH', { 'TH mode' })
            local rs, order = {}, {}
            for prefix, sn in pairs(cfg.ReceivedSets or {}) do
                if rs[sn] == nil then
                    rs[sn] = {}
                    order[#order + 1] = sn
                end
                table.insert(rs[sn], prefix)
            end
            table.sort(order)
            for _, sn in ipairs(order) do
                -- the spells the set is named after first, in the name's order (Protect_Shell: Protect / Shell), then the
                -- shortest (Cure / Cura / Curaga); capitalised as the game writes them
                local ln = string.lower(sn)
                local function at(x)
                    return string.find(ln, x, 1, true) or 1000
                end
                table.sort(rs[sn], function(x, y)
                    if at(x) ~= at(y) then
                        return at(x) < at(y)
                    end
                    if #x ~= #y then
                        return #x < #y
                    end
                    return x < y
                end)
                local names = {}
                for i, x in ipairs(rs[sn]) do
                    names[i] = (
                        string.gsub(x, '(%a)(%a*)', function(f, r)
                            return string.upper(f) .. r
                        end)
                    )
                end
                add(sn, { table.concat(names, ' / ') .. ' on its way to you' })
            end
            if idle ~= nil then
                add('XIRoll', plus(idle, 'a roll at 11'))
            end
            add('Incapacitated', { 'slept, petrified, stunned or terrorized' })
            add('Sleeping', { 'asleep' })
            add('Doomed', { 'Doom or Bane' })
            notes[#notes + 1] =
                "Buffs: a set per buff (Buffs = { ['Aftermath: Lv.3'] = {...} }), listed under Buffs."
        end

        -- 3. the file's own variants of a set listed (Ws_Default_SA): nothing above looks for them
        local listed = {}
        for _, w in ipairs(out) do
            listed[#listed + 1] = w
        end
        for _, w in ipairs(listed) do
            local pre = string.lower(w.name) .. '_'
            for _, s in ipairs(document.model.list) do
                if
                    (s.parentName == nil)
                    and (string.sub(s.lname, 1, #pre) == pre)
                    and not seen[s.lname]
                    and ((ev == 'Precast') or not string.match(s.lname, '_precast$'))
                then
                    add(s.name, plus(w.conds, "your job file's own logic"), w.name, { src = 'file' })
                end
            end
        end
        if #dyn > 0 then
            notes[#notes + 1] =
                'Your job file also builds set names in code, not listed above (their sets show as "your job file\'s own logic"):'
            for _, d in ipairs(dyn) do
                notes[#notes + 1] = '  ' .. d
            end
        end
        return out, (#notes > 0) and table.concat(notes, '\n') or nil
    end

    return {
        Layers = layers_of,
        IsSetLabel = is_set_label,
        Labels = labels_of,
        RecordsFor = records_for,
        ActionLabel = action_label,
        SourceLabel = source_label,
        Explain = why,
        View = layer_view,
        Family = family,
        ModesNow = modes_now,
        ActionFor = action_for,
        When = when_description,
        Expected = expected_for,
        Equipment = equipment_for,
        Related = what_if,
    }
end

models.Actions = actionModel
end

-- ============================================================================
-- Additive, listed equipment bonuses. Conditional/unknown effects stay separate.
-- ============================================================================
do
local stats = {}
local aliases, definitions = {}, {}
local groups = { Core = 1, Attributes = 2, Physical = 3, Magic = 4, Defense = 5, Utility = 6, Skills = 7, Weapons = 8, Pet = 9, Abilities = 10 }
local function normalize(value) return value:lower():gsub('[%s%p]', '') end
local function define(name, group, unit, direction, names, weapon)
    local entry = { name = name, group = group, unit = unit or '', direction = direction or 1,
        order = #definitions + 1, weapon = weapon }
    definitions[#definitions + 1] = entry
    aliases[normalize(name)] = entry
    for _, alias in ipairs(names or {}) do aliases[normalize(alias)] = entry end
end
for _, name in ipairs({ 'HP', 'MP' }) do define(name, 'Core') end
define('Defense', 'Core', '', 1, { 'DEF' })
for _, name in ipairs({ 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' }) do define(name, 'Attributes') end
define('Accuracy', 'Physical', '', 1, { 'Acc.' })
define('Attack', 'Physical', '', 1, { 'Atk.' })
define('Ranged accuracy', 'Physical', '', 1, { 'Ranged Acc.', 'Rng. Acc.', 'R. Acc.' })
define('Ranged attack', 'Physical', '', 1, { 'Ranged Atk.', 'Rng. Atk.', 'R. Atk.' })
define('Evasion', 'Defense', '', 1, { 'Eva.' })
define('Magic accuracy', 'Magic', '', 1, { 'Magic Acc.', 'Mag. Acc.', 'M.Acc.' })
define('Magic attack bonus', 'Magic', '', 1, { 'Magic Atk. Bonus', 'Mag. Atk. Bns.', 'MAB' })
define('Magic defense bonus', 'Defense', '', 1, { 'Magic Def. Bonus', 'Mag. Def. Bns.', 'MDB' })
define('Magic evasion', 'Defense', '', 1, { 'M.Eva.', 'Magic Eva.', 'Mag. Eva.', 'Mag. Evasion', 'MEVA' })
define('Magic damage', 'Magic', '', 1, { 'Magic Dmg.', 'Mag. Dmg.' })
for _, name in ipairs({ 'Haste', 'Fast Cast', 'Snapshot', 'Rapid Shot', 'Double Attack', 'Triple Attack',
    'Quadruple Attack', 'Dual Wield', 'Critical hit rate', 'Critical hit damage', 'Weapon skill damage',
    'Skillchain bonus', 'Skillchain damage' }) do define(name, 'Physical', '%') end
define('Weapon skill accuracy', 'Physical')
aliases[normalize('Crit. hit rate')] = aliases[normalize('Critical hit rate')]
aliases[normalize('Crit. hit damage')] = aliases[normalize('Critical hit damage')]
aliases[normalize('WS damage')] = aliases[normalize('Weapon skill damage')]
aliases[normalize('Dbl. Atk.')] = aliases[normalize('Double Attack')]
aliases[normalize('Quad. Atk.')] = aliases[normalize('Quadruple Attack')]
for _, name in ipairs({ 'Store TP', 'Subtle Blow', 'Subtle Blow II', 'Save TP', 'Conserve TP' }) do define(name, 'Physical') end
for _, name in ipairs({ 'TP Bonus', 'Martial Arts', 'Fencer' }) do define(name, 'Physical') end
for _, name in ipairs({ 'Physical damage limit', 'Counter', 'Kick Attacks' }) do define(name, 'Physical', '%') end
aliases[normalize('PDL')] = aliases[normalize('Physical damage limit')]
for _, name in ipairs({ 'Magic burst damage', 'Magic burst damage II', 'Cure potency', 'Cure potency II',
    'Cure potency received', 'Enhancing magic duration', 'Enfeebling magic duration', 'Conserve MP' }) do define(name, 'Magic', '%') end
aliases[normalize('Magic burst dmg.')] = aliases[normalize('Magic burst damage')]
aliases[normalize('Magic burst dmg. II')] = aliases[normalize('Magic burst damage II')]
aliases[normalize('Skillchain dmg.')] = aliases[normalize('Skillchain damage')]
aliases[normalize('Enhancing magic effect duration')] = aliases[normalize('Enhancing magic duration')]
aliases[normalize('Enfeebling magic effect duration')] = aliases[normalize('Enfeebling magic duration')]
aliases[normalize('Enh. mag. eff. dur.')] = aliases[normalize('Enhancing magic duration')]
for _, name in ipairs({ 'Cure spellcasting time', 'Song spellcasting time', 'Summoning magic casting time',
    'Blue magic spellcasting time', 'Drain and Aspir spell casting time' }) do define(name, 'Magic', '%', -1) end
for _, name in ipairs({ 'Drain and Aspir potency', 'Song effect duration' }) do define(name, 'Magic', '%') end
define('Ninjutsu magic attack bonus', 'Magic')
define('All songs', 'Magic')
define('Regen potency', 'Magic')
define('Refresh potency', 'Magic')
define('Quick Draw damage', 'Magic')
for _, name in ipairs({ 'Phalanx', 'Phalanx received', 'Stoneskin', 'Cursna', 'Cursna received',
    'Enfeebling magic effect', 'Magic burst accuracy' }) do define(name, 'Magic') end
define('Quick Magic', 'Magic', '%')
define('Blue magic recast delay', 'Magic', '%', -1)
define('Chain Affinity', 'Abilities')
define('Efflux: TP Bonus', 'Abilities', '', 1, { 'Efflux TP Bonus' })
define('Shield block rate', 'Defense', '%')
define('Blood Pact damage', 'Pet', '%')
define('Blood Pact delay', 'Pet', '', -1)
define('Blood Pact delay II', 'Pet', '', -1)
aliases[normalize('Blood Pact ability delay')] = aliases[normalize('Blood Pact delay')]
aliases[normalize('Blood Pact ability delay II')] = aliases[normalize('Blood Pact delay II')]
define('Waltz potency', 'Utility', '%')
define('Waltz potency received', 'Utility', '%')
define('Waltz delay', 'Utility', '', -1)
define('Phantom Roll', 'Utility')
define('Phantom Roll effect duration', 'Utility')
for _, entry in ipairs({ {'Damage taken', {'DT'}}, {'Physical damage taken', {'Phys. dmg. taken', 'PDT'}},
    {'Magic damage taken', {'Magic dmg. taken', 'MDT'}}, {'Breath damage taken', {'Breath dmg. taken'}},
    {'Damage taken II', {}}, {'Physical damage taken II', {}}, {'Magic damage taken II', {}} }) do
    define(entry[1], 'Defense', '%', -1, entry[2])
end
define('Spell interruption rate down', 'Defense', '%', 1, { 'Spell interruption rate' })
define('Status ailment resistance', 'Defense', '', 1, { 'Resistance to all status ailments' })
for _, name in ipairs({ 'Sleep', 'Poison', 'Paralyze', 'Blind', 'Silence', 'Petrify', 'Virus',
    'Stun', 'Amnesia', 'Bind', 'Slow', 'Gravity', 'Charm', 'Curse', 'Death', 'Terror' }) do
    define('Resist ' .. name, 'Defense')
end
define('Enmity', 'Utility', '', 0)
define('Enemy critical hit rate', 'Defense', '%', -1)
for _, name in ipairs({ 'Regen', 'Refresh', 'Regain', 'Occult Acumen', 'Treasure Hunter' }) do define(name, 'Utility') end
define('Movement speed', 'Utility', '%')
for _, name in ipairs({ 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water', 'Light', 'Dark' }) do
    define(name .. ' resistance', 'Defense', '', 1, { name })
end
for _, name in ipairs({ 'Divine magic', 'Healing magic', 'Enhancing magic', 'Enfeebling magic', 'Elemental magic',
    'Dark magic', 'Summoning magic', 'Ninjutsu', 'Blue magic', 'Singing', 'Wind instrument', 'String instrument',
    'Geomancy', 'Handbell' }) do define(name .. ' skill', 'Skills') end
for _, name in ipairs({ 'Hand-to-hand', 'Dagger', 'Sword', 'Great sword', 'Axe', 'Great axe', 'Scythe',
    'Polearm', 'Katana', 'Great katana', 'Club', 'Staff', 'Archery', 'Marksmanship', 'Throwing',
    'Parrying', 'Magic accuracy' }) do define(name .. ' skill', 'Skills', '', 1, nil, true) end
for _, name in ipairs({ 'Shield', 'Guard', 'Evasion', 'Fishing' }) do define(name .. ' skill', 'Skills') end
define('Weapon damage', 'Weapons', '', 1, { 'DMG' }, true)
define('Weapon delay', 'Weapons', '', 0, { 'Delay' }, true)
local weaponSlots = { Main = true, Sub = true, Range = true, Ammo = true }
local owners = { pet = 'Pet', avatar = 'Avatar', automaton = 'Automaton', wyvern = 'Wyvern',
    luopan = 'Luopan', ['song effects'] = 'Song effects', player = '', master = '', you = '' }
local numericStat = "([%a][%a%s%.'\"/()%-]-)%s*([+%-:])%s*([+%-]?)%s*(%d+%.?%d*)%s*(%%?)"

local function context_start(line)
    local lower = line:lower()
    local owner = lower:match('^(.-):')
    return (owner and (owners[owner] ~= nil or (not owner:find('%d') and not aliases[normalize(owner)])))
        or lower:match('^set:') or lower:match('^latent') or lower:match('^unity')
        or lower:match('^occasionally') or lower:match('^occ%.') or lower:match('^augments ')
        or lower:match('^enhances ') or lower:match('^grants ')
        or lower:match('^while .-:') or lower:match('^during .-:') or lower:match('^when .-:')
end

-- Resource newlines wrap words and sentences as well as separate bonuses.
-- Join continuations before interpreting their numbers, so qualifiers stay attached.
local function description_lines(text)
    local lines, pending = {}, nil
    text = text:gsub('\226\136\146', '-'):gsub('\r', '')
    text = text:gsub('(%S)[ \t]+(%a+):', function(previous, owner)
        return previous .. (owners[owner:lower()] ~= nil and '\n' or ' ') .. owner .. ':'
    end)
    local function flush()
        if pending then lines[#lines + 1], pending = pending, nil end
    end
    for line in (text .. '\n'):gmatch('(.-)\n') do
        line = line:match('^%s*(.-)%s*$')
        if line == '' then
            flush(); lines[#lines + 1] = ''
        else
            local continuation = false
            if pending and not context_start(line) then
                local hasNumber = line:find('[+%-:]%s*[+%-]?%s*%d') or line:find('%d+%.?%d*%%')
                local tail = pending:match('([%a%.%s\"]+)$')
                local head = line:match('^([%a%.%s\"]-)[+%-:]')
                continuation = not hasNumber or line:match('^[+%-:]') or line:match('^%d')
                    or pending:match('[:+%-]%s*$')
                    or (tail and head and aliases[normalize(tail .. head)] ~= nil)
            end
            if continuation then pending = pending .. ' ' .. line
            else flush(); pending = line end
        end
    end
    flush()
    return lines
end

function stats.Format(value, unit)
    if value == 0 then value = 0 end
    local number = math.floor(value) == value and string.format('%.0f', value)
        or string.format('%.2f', value):gsub('0+$', ''):gsub('%.$', '')
    return (value > 0 and '+' or '') .. number .. (unit or '')
end

local function sorted(values)
    local rows = {}
    for _, row in pairs(values) do
        row.value = math.floor(row.value * 100 + 0.5) / 100
        if row.value ~= 0 then row.text = stats.Format(row.value, row.unit); rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b)
        if a.group ~= b.group then return groups[a.group] < groups[b.group] end
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    return rows
end

function stats.Build(items, coverage)
    coverage = coverage or {}
    local model = { values = {}, rows = {}, notes = {}, noteGroups = {}, pieces = #items, unchanged = coverage.unchanged or 0,
        rules = coverage.rules or 0, code = coverage.code or 0, baseOnly = 0, pending = coverage.pending }
    local noted, noteGroups = {}, {}
    local function note(item, line, reason)
        local key = item.slot .. '\0' .. line .. '\0' .. reason
        if noted[key] then return end
        noted[key] = true
        local entry = { slot = item.slot, item = item.name, text = line, reason = reason }
        model.notes[#model.notes + 1] = entry
        local groupKey = item.slot .. '\0' .. item.name
        local group = noteGroups[groupKey]
        if not group then
            group = { slot = item.slot, item = item.name, entries = {} }
            noteGroups[groupKey] = group
            model.noteGroups[#model.noteGroups + 1] = group
        end
        group.entries[#group.entries + 1] = entry
    end
    local function parse(item, text)
        local scope, conditional = '', false
        for _, line in ipairs(description_lines(text)) do
            if line == '' then scope, conditional = '', false
            else
                local lower = line:lower()
                if lower:match('^set:') or lower:match('^latent') or lower:match('^unity') or lower:match('^daytime:')
                    or lower:match('^nighttime:') or lower:match('^weather:') or lower:match('^day:')
                    or lower:match('^while ') or lower:match('^during ') or lower:match('^after ') or lower:match('^when ')
                    or lower:match('^additional effect:') or lower:match('^augments ')
                    or lower:match('^enchantment:') or lower:match('^aftermath:') then conditional = true end
                local inlineConditional = lower:find(' while ', 1, true) or lower:find(' during ', 1, true)
                    or lower:find(' when ', 1, true) or lower:find('daytime', 1, true) or lower:find('nighttime', 1, true)
                    or lower:find(' if ', 1, true) or lower:find(' with ', 1, true) or lower:find(' under ', 1, true)
                    or lower:find(' set:', 1, true) or lower:find('latent effect', 1, true)
                local original = line
                local owner, rest = line:match('^(.-):%s*(.*)$')
                if owner and owners[owner:lower()] ~= nil then
                    scope, line = owners[owner:lower()], rest
                elseif owner and not owner:find('%d') and not aliases[normalize(owner)] then
                    conditional = true
                end
                if conditional or inlineConditional or line:find('~', 1, true) or line:find('%d%s*%-%s*%d')
                    or lower:find('occasionally', 1, true) or lower:find('occ%.') then
                    note(item, original, 'Conditional or variable effect')
                else
                    line = line:gsub('([Ss]pell interruption rate down)%s*(%d+%.?%d*%%)', '%1+%2')
                    local recognized, fragments, cursor = false, {}, 1
                    local function fragment(value)
                        if value:find('[%w]') then fragments[#fragments + 1] = value:match('^%s*(.-)%s*$') end
                    end
                    while true do
                        local first, last, name, sign, innerSign, number, percent = line:find(numericStat, cursor)
                        if not first then fragment(line:sub(cursor)); break end
                        fragment(line:sub(cursor, first - 1))
                        local keyName = normalize(name)
                        local definition = aliases[keyName]
                        if definition then
                            local value = tonumber(number) * ((sign == '-' or innerSign == '-') and -1 or 1)
                            if keyName == 'spellinterruptionrate' then value = -value end
                            local unit = percent ~= '' and '%' or definition.unit
                            local group, label = definition.group, definition.name
                            if scope ~= '' then group, label = scope == 'Song effects' and 'Magic' or 'Pet', scope .. ': ' .. label
                            elseif definition.weapon and weaponSlots[item.slot] then group, label = 'Weapons', item.slot .. ': ' .. label
                            elseif definition.group == 'Weapons' then definition = nil end
                            if definition then
                                local key = label .. '\0' .. unit
                                local row = model.values[key]
                                if not row then
                                    row = { key = key, name = label, group = group, unit = unit, value = 0,
                                        order = definition.order, direction = definition.direction }
                                    model.values[key] = row
                                end
                                row.value = row.value + value
                                recognized = true
                            else fragment(line:sub(first, last)) end
                        else fragment(line:sub(first, last)) end
                        cursor = last + 1
                    end
                    if not recognized then note(item, original, 'Other or unrecognized effect')
                    elseif #fragments > 0 then note(item, table.concat(fragments, '; '), 'Other or unrecognized effect') end
                end
            end
        end
    end
    for _, item in ipairs(items) do
        if item.description and item.description ~= '' then parse(item, item.description)
        else note(item, 'Base description unavailable', 'Unknown base stats') end
        if item.unknownAugments then
            model.baseOnly = model.baseOnly + 1
            note(item, 'Exact augment bonuses are unavailable or ambiguous', 'Base stats only')
        else
            for _, augment in ipairs(item.augments or {}) do parse(item, augment) end
        end
    end
    model.rows = sorted(model.values)
    model.coverage = string.format('%d items | %d unchanged slots | %d rules', model.pieces, model.unchanged, model.rules)
    return model
end

function stats.Compare(left, right)
    local rows, seen = {}, {}
    for _, source in ipairs({ left.values, right.values }) do
        for key, entry in pairs(source) do
            if not seen[key] then
                seen[key] = true
                local a, b = left.values[key], right.values[key]
                local before, after = a and a.value or 0, b and b.value or 0
                local delta = math.floor((after - before) * 100 + 0.5) / 100
                local row = { key = key, name = entry.name, group = entry.group, order = entry.order,
                    unit = entry.unit, direction = entry.direction, value = delta,
                    before = stats.Format(before, entry.unit), after = stats.Format(after, entry.unit),
                    delta = delta, deltaText = stats.Format(delta, entry.unit) }
                rows[#rows + 1] = row
            end
        end
    end
    table.sort(rows, function(a,b)
        if a.group ~= b.group then return groups[a.group] < groups[b.group] end
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    local warnings, byText = {}, {}
    for side, model in ipairs({ left, right }) do
        for _, message in ipairs(model.layerWarnings or {}) do
            local entry = byText[message]
            if not entry then entry = { text = message, sides = 0 }; byText[message] = entry; warnings[#warnings + 1] = entry end
            local flag = side == 1 and 1 or 2
            if entry.sides ~= 3 and entry.sides ~= flag then entry.sides = entry.sides + flag end
        end
    end
    return { rows = rows, left = left, right = right, warnings = warnings }
end
models.Stats = stats
end

return models
