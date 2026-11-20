-- /gcgear: the gear you have on, 4x4 in the game's equipment-window order (as atom0s' equipmon): icons, the ammo
-- count, a red X on a slot the game has encumbered. A slot's border says what keeps it: red your /lock, amber the TP
-- hold, purple Aminon, Hoxne, /proc, an item use (/gce) or a hold (/capacity...); a pink corner: it still needs RP.
-- Hover a slot: the item, the set that put it on, who holds it. The bar (/gcbar) ends with the same slots as a small
-- map (gcgear.DrawMap); hovered, it shows this grid. Colours: the bar's colour preset (gcdisplay.Theme).
local gcgear = {}

local ffi = require('ffi')
local okD3d, d3d8 = pcall(require, 'd3d8')
if not okD3d then d3d8 = nil end

local inc, disp = nil, nil -- gcinclude, gcdisplay (Bind)

-- Saved per character in config\addons\luashitacast\gcbar\<Name>_gear.txt as "x,y,on,scale,map" (x,y 'auto' until
-- dragged). The window starts off; the bar's map starts on.
local cfg = { on = false, map = true, x = nil, y = nil, scale = 1 }
local placed, savedX, savedY = false, nil, nil -- the window put where cfg says (again after pos, reset or scale)

-- The game's equipment slots (0 Main .. 15 Back; LAC's slot numbers are these + 1), in the equipment window's order.
local ORDER = { 0, 1, 2, 3, 4, 9, 11, 12, 5, 6, 13, 14, 15, 10, 7, 8 }
local SLOT_NAME = { [0] = 'Main', 'Sub', 'Range', 'Ammo', 'Head', 'Body', 'Hands', 'Legs', 'Feet', 'Neck', 'Waist',
    'Ear1', 'Ear2', 'Ring1', 'Ring2', 'Back' }
-- id/count/extra: what is worn (id 0: nothing); item: its name; stack: its stack size; rank/cap/rp: rank progress
local cells = {}
for i, s in ipairs(ORDER) do cells[i] = { game = s, slot = s + 1, name = SLOT_NAME[s], id = 0, count = 0 } end

local function xy(a, b) -- ImGui vectors come back as two numbers or as a table, by Ashita version
    if (type(a) == 'table') then return tonumber(a[1] or a.x), tonumber(a[2] or a.y) end
    return tonumber(a), tonumber(b)
end
local function textw(t)
    local w = imgui.CalcTextSize(t)
    if (type(w) == 'table') then w = w[1] or w.x end
    return tonumber(w) or 0
end
-- Scratch points, size and colour for the draw calls (ImGui copies each argument and keeps none).
local VA, VB, SIZE, CC = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0, 0, 1 }
local function va(x, y) VA[1], VA[2] = x, y; return VA end
local function vb(x, y) VB[1], VB[2] = x, y; return VB end
local function size(w, h) SIZE[1], SIZE[2] = w, h; return SIZE end
local function u32(c, a) CC[1], CC[2], CC[3], CC[4] = c[1], c[2], c[3], a or c[4] or 1; return imgui.GetColorU32(CC) end

-- Colours. The window, hover text and map squares are the bar's; the four meanings take the preset's shade
-- (gctheme keys), kept apart as /gcedit keeps its own.
local COL_BG, COL_EDGE = { 0.04, 0.045, 0.06, 0.70 }, { 1.0, 1.0, 1.0, 0.10 }
local COL_TIP_BG = { 0.04, 0.045, 0.06, 0.94 }
local COL_HEAD, COL_KEY, COL_DIM = { 0.93, 0.93, 0.96, 1.0 }, { 0.62, 0.68, 0.80, 1.0 }, { 0.55, 0.55, 0.61, 0.90 }
local SOCKET = { 0.27, 0.32, 0.41, 0.55 } -- a slot's square; on the map, an empty slot
local WORN = { 0.62, 0.66, 0.74, 0.85 } -- the map: gear on, nothing holding it
local SHADE, OUTLINE, WHITE = { 0, 0, 0, 0.45 }, { 0, 0, 0, 0.90 }, { 1, 1, 1, 1 }
local MEANINGS = { 'lock', 'hold', 'feature', 'rp' }
local OWN = { lock = { 1.00, 0.35, 0.35 }, hold = { 1.00, 0.72, 0.25 }, feature = { 0.65, 0.40, 1.00 },
    rp = { 1.00, 0.48, 0.72 } }
local THEME_KEY = { lock = 'hp_0', hold = 'tp_max', feature = 'item', rp = 'ws' }
local COL = {}
for k, c in pairs(OWN) do COL[k] = { c[1], c[2], c[3], 1.0 } end
local themeMod, themeKey = nil, nil
local function colours()
    local key = ((disp ~= nil) and disp.Theme) or 'goomswap'
    if (key == themeKey) then return end
    themeKey = key
    if (themeMod == nil) then
        local ok, m = pcall(gFunc.LoadFile, 'common\\gctheme.lua')
        themeMod = (ok and (type(m) == 'table')) and m or false
    end
    for _, k in ipairs(MEANINGS) do
        local c = (themeMod and (key ~= 'goomswap')) and themeMod.Color(key, THEME_KEY[k]) or OWN[k]
        COL[k][1], COL[k][2], COL[k][3] = c[1], c[2], c[3]
    end
    if themeMod and (key ~= 'goomswap') then themeMod.KeepApart(COL, MEANINGS, OWN, 25) end
end

-- Item icons: one texture per item id, made as /gcedit makes them (a few a frame), kept until the profile unloads.
local ICONS_PER_FRAME = 4
local textures, budget = {}, ICONS_PER_FRAME
local function icon(id)
    if (id == nil) or (id == 0) or (d3d8 == nil) then return nil end
    local t = textures[id]
    if (t ~= nil) then return t or nil end
    if (budget <= 0) then return nil end
    budget = budget - 1
    textures[id] = false
    local item = AshitaCore:GetResourceManager():GetItemById(id)
    local device = d3d8.get_device()
    if (item == nil) or (item.Bitmap == nil) or (device == nil) then return nil end
    local ptr = ffi.new('IDirect3DTexture8*[1]')
    local bytes = (ashita.interface_version == nil) and item.ImageSize or -1 -- as gcedit (tHotBar)
    if ffi.C.D3DXCreateTextureFromFileInMemoryEx(device, item.Bitmap, bytes, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil,
        ptr) ~= ffi.C.S_OK then
        return nil
    end
    local tex = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]))
    textures[id] = { tex = tex, id = tonumber(ffi.cast('uint32_t', tex)) }
    return textures[id]
end

-- Rank (RP) progress of an equipped item: the editor's decoders (gcaugments), rank and cap only.
local augmentInfo, NO_BUNDLES = nil, {}
local function rank_of(it)
    if (augmentInfo == nil) then
        local ok, m = pcall(gFunc.LoadFile, 'common\\gcaugments.lua')
        augmentInfo = (ok and (type(m) == 'table')) and m or false
    end
    if not augmentInfo then return nil end
    local a = augmentInfo.Read(it, gData.GetAugment)
    local ranked = augmentInfo.Rank.Read(it.Extra, NO_BUNDLES)
    if (ranked ~= nil) then a.rank, a.cap = ranked.rank, ranked.cap end
    local p = augmentInfo.Progress(a)
    if (p == nil) then return nil end
    return { rank = a.rank, cap = (not p.unknown) and (tonumber(a.cap) or ((a.system == 'Delve') and 15)) or nil,
        unfinished = (p.unfinished == true) }
end

-- The 16 slots, read 4 times a second while the window or the bar's map is drawn (equipmon reads them on equipment
-- packets): a changed item (or its extdata: RP) is looked up again.
local POLL = 0.25
local nextPoll = 0
local function poll()
    local now = os.clock()
    if (now < nextPoll) then return end
    nextPoll = now + POLL
    local inv, res = AshitaCore:GetMemoryManager():GetInventory(), AshitaCore:GetResourceManager()
    for _, c in ipairs(cells) do
        local e = inv:GetEquippedItem(c.game)
        local index = (e ~= nil) and bit.band(e.Index, 0x00FF) or 0
        local it = (index ~= 0) and inv:GetContainerItem(bit.band(e.Index, 0xFF00) / 256, index) or nil
        local id = ((it ~= nil) and (it.Count > 0) and (it.Id ~= 0) and (it.Id ~= 65535)) and it.Id or 0
        local extra = (id ~= 0) and it.Extra or nil
        if (type(extra) ~= 'string') then extra = nil end
        if (id ~= c.id) or (extra ~= c.extra) then
            c.id, c.extra = id, extra
            local r = (id ~= 0) and res:GetItemById(id) or nil
            c.item = ((r ~= nil) and (r.Name ~= nil)) and r.Name[1] or nil
            c.stack = (r ~= nil) and (tonumber(r.StackSize) or 1) or 1
            local ok, rp = false, nil
            if (id ~= 0) then ok, rp = pcall(rank_of, it) end
            c.rp = ok and rp or nil
        end
        c.count = (id ~= 0) and it.Count or 0
    end
end

-- Encumbrance: 0x001B's uint32 at 0x60, one bit per equipment slot (XiPackets 0x001B 'encumbrance'; bit = slot, as
-- equipmon reads it). A global, so it outlives /lac reload (the packet comes on zoning and job changes).
local function encumbered(game)
    return bit.band(tonumber(GcEncumbrance) or 0, bit.lshift(1, game)) ~= 0
end
local function on_packet(e)
    if (e.id ~= 0x001B) then return end
    local data = e.data_modified or e.data
    if (type(data) ~= 'string') or (#data < 0x64) then return end
    GcEncumbrance = struct.unpack('L', data, 0x60 + 1)
end

-- What keeps a slot (LAC number): 'lock' (/lock), 'feature' (another owner: Aminon, Hoxne...), 'hold' (TP hold).
local function holder(slot)
    if (inc == nil) then return nil end
    local owners = inc.LockedSlots[slot]
    if (owners ~= nil) and (next(owners) ~= nil) then return owners.user and 'lock' or 'feature' end
    if (inc.HeldSlots[slot] ~= nil) then return 'hold' end
    return nil
end
local OWNER_TEXT = { user = '/lock', aminon = 'Aminon', hoxne = 'Hoxne', proc = '/proc',
    enchant = 'an item use (/gce)' }
local function owner_text(o)
    local key = string.match(o, '^hold:(.+)$')
    return OWNER_TEXT[o] or ((key ~= nil) and ('/' .. key)) or o
end

-- The set that put the worn item on: the slot's last kept write in GoomSwap's swaps (gcaction keeps GcWornBy), else
-- the other slot of the pair (Ear1/Ear2, Ring1/Ring2) when it named this item. Returns the write and whether it is
-- what is worn.
local PARTNER = { [12] = 13, [13] = 12, [14] = 15, [15] = 14 }
local function source(c)
    local by = (type(GcWornBy) == 'table') and GcWornBy or {}
    local want = (c.item ~= nil) and string.lower(c.item) or 'remove'
    local w = by[c.slot]
    if (w ~= nil) and (string.lower(tostring(w.name)) == want) then return w, true end
    local p = (PARTNER[c.slot] ~= nil) and by[PARTNER[c.slot]] or nil
    if (p ~= nil) and (c.item ~= nil) and (string.lower(tostring(p.name)) == want) then return p, true end
    return w, false
end

local function line(text, col)
    imgui.PushStyleColor(ImGuiCol_Text, col)
    imgui.TextUnformatted(text)
    imgui.PopStyleColor()
end
-- Hover text for a slot: the item, its RP, the set that put it on, and whatever holds the slot.
local function details(c)
    local count = ((c.item ~= nil) and ((c.stack or 1) > 1)) and (' x' .. tostring(c.count)) or ''
    line(c.name .. ': ' .. (c.item or 'empty') .. count, COL_HEAD)
    if (c.rp ~= nil) and (c.rp.rank ~= nil) then
        local r = 'R' .. c.rp.rank .. ((c.rp.cap ~= nil) and ('/' .. c.rp.cap) or '')
        if c.rp.unfinished then line('Needs RP: ' .. r, COL.rp) else line(r, COL_KEY) end
    end
    local w, worn = source(c)
    if (w ~= nil) and worn then
        line(((c.item ~= nil) and 'From ' or 'Emptied by ') .. tostring(w.by) .. ' (' .. tostring(w.key) .. ')',
            COL_KEY)
    elseif (w ~= nil) then
        line('Last swap asked for ' .. tostring(w.name) .. ' (' .. tostring(w.by) .. ', ' .. tostring(w.key) .. ')',
            COL_DIM)
    elseif (c.item ~= nil) then
        line('No GoomSwap swap seen for it yet', COL_DIM)
    end
    if (inc ~= nil) then
        for o in pairs(inc.LockedSlots[c.slot] or {}) do
            line('Locked: ' .. owner_text(o) .. ' (' .. tostring(inc.LockOwnerFix(o, c.slot)) .. ')',
                (o == 'user') and COL.lock or COL.feature)
        end
        if (inc.HeldSlots[c.slot] ~= nil) then
            if inc.TPHoldActive() then
                line('Held for TP: ' .. tostring(AshitaCore:GetMemoryManager():GetParty():GetMemberTP(0))
                    .. ' TP, WeaponTPGuard ' .. tostring(inc.settings.WeaponTPGuard), COL.hold)
            elseif inc.AftermathUp() then
                line('Held for Aftermath (AftermathHold)', COL.hold)
            else
                line('Held for TP', COL.hold)
            end
        end
    end
    if encumbered(c.game) then line('Encumbered: the game has locked this slot', COL.lock) end
end

-- One slot's marks over its icon: encumbrance X, holder border, RP corner, ammo count; hot: outlined (the map's).
local function marks(dl, c, x, y, cell, hot)
    local x2, y2 = x + cell, y + cell
    if encumbered(c.game) then -- equipmon's mark: the slot dimmed, a red X
        dl:AddRectFilled(va(x, y), vb(x2, y2), u32(SHADE), 3)
        local m, th = math.floor(cell * 0.22), math.max(2, cell / 12)
        dl:AddLine(va(x + m, y + m), vb(x2 - m, y2 - m), u32(COL.lock), th)
        dl:AddLine(va(x2 - m, y + m), vb(x + m, y2 - m), u32(COL.lock), th)
    end
    local h = holder(c.slot)
    if (h ~= nil) then dl:AddRect(va(x + 1, y + 1), vb(x2 - 1, y2 - 1), u32(COL[h]), 3, 0, 2) end
    if (c.rp ~= nil) and c.rp.unfinished then -- a quarter circle in the top right corner
        local r = math.max(4, math.floor(cell * 0.30))
        if (dl.PushClipRect ~= nil) and (dl.PopClipRect ~= nil) then
            dl:PushClipRect(va(x, y), vb(x2, y2), true)
            dl:AddCircleFilled(va(x2, y), r, u32(COL.rp), 12)
            dl:PopClipRect()
        else
            dl:AddRectFilled(va(x2 - r, y), vb(x2, y + r), u32(COL.rp), 0)
        end
    end
    if (c.item ~= nil) and ((c.stack or 1) > 1) then -- the ammo count, bottom right, outlined
        local text = tostring(c.count)
        local tx, ty = x2 - textw(text) - 2, y2 - imgui.GetTextLineHeight() + 1
        local dark = u32(OUTLINE)
        dl:AddText(va(tx - 1, ty), dark, text); dl:AddText(va(tx + 1, ty), dark, text)
        dl:AddText(va(tx, ty - 1), dark, text); dl:AddText(va(tx, ty + 1), dark, text)
        dl:AddText(va(tx, ty), u32(WHITE), text)
    end
    if hot then dl:AddRect(va(x, y), vb(x2, y2), u32(WHITE), 3, 0, 1) end
end

-- The 4x4 grid at the cursor; hot: a slot to outline (the map's hovered one). Returns the hovered slot's cell.
local function grid_body(cell, gap, hot)
    budget = ICONS_PER_FRAME
    local dl, hovered = imgui.GetWindowDrawList(), nil
    for i, c in ipairs(cells) do
        if (((i - 1) % 4) ~= 0) then imgui.SameLine(0, gap) end
        local x, y = xy(imgui.GetCursorScreenPos())
        if (x ~= nil) then dl:AddRectFilled(va(x, y), vb(x + cell, y + cell), u32(SOCKET), 3) end
        local t = icon(c.id)
        if (t ~= nil) then imgui.Image(t.id, size(cell, cell)) else imgui.Dummy(size(cell, cell)) end
        if (hot == nil) and imgui.IsItemHovered() then hovered = c end
        if (x ~= nil) then marks(dl, c, x, y, cell, hot == i) end
    end
    return hovered
end
local function grid(cell, gap, hot)
    poll()
    colours()
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, va(gap, gap))
    local ok, r = pcall(grid_body, cell, gap, hot) -- an error must not skip the Pop
    imgui.PopStyleVar()
    if not ok then error(r, 0) end
    return r
end
local function sizes(scale)
    return math.floor(32 * scale + 0.5), math.max(1, math.floor(2 * scale + 0.5))
end

local TIP_PAD = { 8, 5 } -- the bar's hover text
local function tooltip(fn, ...)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, TIP_PAD)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 8)
    imgui.PushStyleColor(ImGuiCol_PopupBg, COL_TIP_BG)
    imgui.BeginTooltip()
    local ok, why = pcall(fn, ...)
    imgui.EndTooltip()
    imgui.PopStyleColor()
    imgui.PopStyleVar(2)
    if not ok then error(why, 0) end
end

-- The bar's map, at the cursor (gcdisplay: the end of this box's line), as tall as the line: a square per slot in
-- its holder's colour, else pink (needs RP), light (worn) or dark (empty); an encumbered slot is red. Returns its
-- width. Hovered: the grid, that slot outlined, and its hover text.
local function map_tip(hot)
    local cell, gap = sizes(cfg.scale)
    grid(cell, gap, hot)
    if (hot ~= nil) then details(cells[hot]) end
    if not cfg.on then line('/gcgear: as a window', COL_DIM) end
end
local function map_colour(c)
    if encumbered(c.game) then return COL.lock end
    local h = holder(c.slot)
    if (h ~= nil) then return COL[h] end
    if (c.rp ~= nil) and c.rp.unfinished then return COL.rp end
    return (c.id ~= 0) and WORN or SOCKET
end
local function draw_map(lh)
    poll()
    colours()
    local g = 1
    local cs = math.max(2, math.floor((lh - 3 * g) / 4))
    local w = 4 * cs + 3 * g
    local x, y = xy(imgui.GetCursorScreenPos())
    imgui.Dummy(size(w, lh))
    if (x == nil) or (y == nil) then return w end
    local dl = imgui.GetWindowDrawList()
    local top = y + math.floor((lh - w) / 2)
    for i, c in ipairs(cells) do
        local cx, cy = x + ((i - 1) % 4) * (cs + g), top + math.floor((i - 1) / 4) * (cs + g)
        dl:AddRectFilled(va(cx, cy), vb(cx + cs, cy + cs), u32(map_colour(c)), 0)
    end
    if imgui.IsItemHovered() then
        local mx, my = xy(imgui.GetMousePos())
        local hot = nil
        if (mx ~= nil) and (my ~= nil) then
            local col = math.max(0, math.min(3, math.floor((mx - x) / (cs + g))))
            local row = math.max(0, math.min(3, math.floor((my - top) / (cs + g))))
            hot = row * 4 + col + 1
        end
        tooltip(map_tip, hot)
    end
    return w
end
function gcgear.DrawMap(lh) -- an error turns the map off, never the bar
    local ok, w = pcall(draw_map, lh)
    if ok then return w end
    cfg.map = false
    if (inc ~= nil) then inc.Err('Gear map off after an error: ' .. tostring(w)) end
    return nil
end
function gcgear.MapOn() return cfg.map == true end

-- Per-character file.
local function path()
    local p = gData.GetPlayer()
    if (p == nil) or (p.Name == nil) or (p.Name == '') then return nil, nil end
    return string.format('%sconfig\\addons\\luashitacast\\gcbar\\', AshitaCore:GetInstallPath()), p.Name .. '_gear.txt'
end
local function save_cfg()
    local dir, file = path()
    if (dir == nil) then return end
    if not ashita.fs.exists(dir) then ashita.fs.create_directory(dir) end
    local f = io.open(dir .. file, 'w')
    if (f == nil) then return end
    local function n(v) return (tonumber(v) ~= nil) and string.format('%d', v) or 'auto' end
    f:write(string.format('%s,%s,%s,%s,%s', n(cfg.x), n(cfg.y), cfg.on and 'on' or 'off', tostring(cfg.scale),
        cfg.map and 'on' or 'off'))
    f:close()
end
local function load_cfg()
    local dir, file = path()
    if (dir == nil) then return end
    local f = io.open(dir .. file, 'r')
    if (f == nil) then return end
    local text = f:read('*a') or ''
    f:close()
    local x, y, on, scale, map = string.match(text, '^(%-?%w+),(%-?%w+),(%a+),([%d%.]+),(%a+)')
    if (x == nil) then return end
    cfg.x, cfg.y = tonumber(x), tonumber(y)
    if (cfg.x == nil) or (cfg.y == nil) then cfg.x, cfg.y = nil, nil end
    cfg.on, cfg.map = (on == 'on'), (map ~= 'off')
    cfg.scale = math.max(0.5, math.min(3, tonumber(scale) or 1))
end

-- The window: no title bar, dragged anywhere; where it is let go is saved. Hidden with the game's interface, as the
-- bar is (gcdisplay.UiHidden).
local PAD, FLAGS = { 4, 4 }, nil
local function window_body(cell, gap)
    local c = grid(cell, gap, nil)
    if (c ~= nil) then tooltip(details, c) end
    local x, y = xy(imgui.GetWindowPos())
    if (x ~= nil) and (y ~= nil) and not imgui.IsMouseDown(0) then
        x, y = math.floor(x + 0.5), math.floor(y + 0.5)
        if (x ~= savedX) or (y ~= savedY) then
            savedX, savedY, cfg.x, cfg.y = x, y, x, y
            save_cfg()
        end
    end
end
local function render()
    if (disp ~= nil) and (disp.UiHidden ~= nil) and disp.UiHidden() then return end
    local cell, gap = sizes(cfg.scale)
    if not placed then
        local x, y = cfg.x, cfg.y
        if (x == nil) or (y == nil) then -- not dragged yet: the right side, a little below the middle
            local ok, sw, sh = pcall(function()
                local s = imgui.GetMainViewport().Size
                return s.x, s.y
            end)
            sw, sh = ok and tonumber(sw) or 1280, ok and tonumber(sh) or 720
            x = math.floor(sw - (4 * cell + 3 * gap + 2 * PAD[1]) - 40)
            y = math.floor(sh * 0.55)
        end
        imgui.SetNextWindowPos(va(x, y), ImGuiCond_Always)
        placed, savedX, savedY = true, x, y
    end
    if (FLAGS == nil) then
        FLAGS = bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoResize)
    end
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, PAD)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6)
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1)
    imgui.PushStyleColor(ImGuiCol_WindowBg, COL_BG)
    imgui.PushStyleColor(ImGuiCol_Border, COL_EDGE)
    local ok, why = true, nil
    if imgui.Begin('GoomSwap gear##gcgear', true, FLAGS) then ok, why = pcall(window_body, cell, gap) end
    imgui.End()
    imgui.PopStyleColor(2)
    imgui.PopStyleVar(3)
    if not ok then error(why, 0) end
end
local function present()
    if not cfg.on then return end
    local t0 = (inc ~= nil) and (inc.Perf ~= nil) and inc.PerfNow() or nil -- /gcperf
    local ok, why = pcall(render)
    if (t0 ~= nil) then inc.PerfAdd('gear', t0) end
    if not ok then
        cfg.on = false
        if (inc ~= nil) then inc.Err('Gear grid off after an error: ' .. tostring(why)) end
    end
end

function gcgear.Bind(gcinclude, gcdisplay)
    inc, disp = gcinclude, gcdisplay
    if (type(disp.SetGear) == 'function') then disp.SetGear(gcgear) end
end

function gcgear.Start()
    pcall(load_cfg)
    placed, themeKey, nextPoll = false, nil, 0
    for _, c in ipairs(cells) do c.id, c.extra, c.item, c.rp, c.count = 0, nil, nil, nil, 0 end
    ashita.events.register('d3d_present', 'gcgear_grid', present)
    ashita.events.register('packet_in', 'gcgear_packet', function (e) pcall(on_packet, e) end)
end

function gcgear.Stop()
    ashita.events.unregister('d3d_present', 'gcgear_grid')
    ashita.events.unregister('packet_in', 'gcgear_packet')
    textures = {}
end

-- /gcgear [on|off] | map [on|off] | pos x y | reset | scale N
function gcgear.HandleCommand(args)
    local arg = (args[2] ~= nil) and string.lower(args[2]) or nil
    if (arg == 'map') then
        local v = (args[3] ~= nil) and string.lower(args[3]) or nil
        if (v == 'on') then cfg.map = true
        elseif (v == 'off') then cfg.map = false
        elseif (v == nil) then cfg.map = not cfg.map
        else inc.Err('usage: /gcgear map [on|off]'); return end
        save_cfg()
        inc.Say('Gear map on the bar: ' .. (cfg.map and 'On' or 'Off'))
        return
    elseif (arg == 'pos') and (tonumber(args[3]) ~= nil) and (tonumber(args[4]) ~= nil) then
        cfg.x, cfg.y, placed = math.floor(tonumber(args[3])), math.floor(tonumber(args[4])), false
        save_cfg()
        return
    elseif (arg == 'reset') then -- back to the first spot and size
        cfg.x, cfg.y, cfg.scale, placed = nil, nil, 1, false
        save_cfg()
        inc.Say('Gear grid: first spot, scale 1')
        return
    elseif (arg == 'scale') then
        local n = tonumber(args[3])
        if (n == nil) then inc.Say('Gear grid scale: ' .. tostring(cfg.scale) .. ' (/gcgear scale 0.5-3)'); return end
        cfg.scale = math.max(0.5, math.min(3, n))
        if (cfg.x == nil) then placed = false end -- not dragged: kept off the right edge at the new size
        save_cfg()
        inc.Say('Gear grid scale: ' .. tostring(cfg.scale))
        return
    elseif (arg == 'on') then cfg.on = true
    elseif (arg == 'off') then cfg.on = false
    elseif (arg == nil) then cfg.on = not cfg.on
    else
        inc.Err('usage: /gcgear [on|off|map on|off|pos x y|reset|scale N]')
        return
    end
    save_cfg()
    inc.Say('Gear grid: ' .. (cfg.on and 'On' or 'Off'))
end

return gcgear
