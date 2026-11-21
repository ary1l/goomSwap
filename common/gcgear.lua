-- /gcgear: the gear you have on, 4x4 in the game's equipment-window order (as atom0s' equipmon): icons, the ammo
-- count, a red X on a slot the game has encumbered. A padlock (bottom left) says what keeps it: red your /lock, purple
-- Aminon, Hoxne, /proc, an item use (/gce) or a hold (/capacity...); an amber dot (bottom right): the TP hold (weapon
-- commands still swap); a pink corner: it still needs RP; '!' (top left): a swap that didn't go on. No borders: some
-- item icons have their own coloured frame.
-- Hover a slot: the item, the set that put it on, who holds it. Colours: the bar's colour preset (gcdisplay.Theme).
-- Every box also shares its slots (luashitacast\hud\<Name>.gear): in the /gchud drop, hover a box's name for its
-- grid (gcgear.AltTip).
local gcgear = {}

local imgui = require('imgui')
local ffi = require('ffi')
local okD3d, d3d8 = pcall(require, 'd3d8')
if not okD3d then d3d8 = nil end

local inc, disp = nil, nil -- gcinclude, gcdisplay (Bind)

-- Saved per character in config\addons\luashitacast\gcbar\<Name>_gear.txt as "x,y,on,scale,alpha,bg" (x,y 'auto'
-- until dragged). The window starts off and bare (bg off: icons only, as equipmon without its backgrounds); alpha:
-- the icons' opacity (the marks stay solid).
local cfg = { on = false, x = nil, y = nil, scale = 1, alpha = 1, bg = false }
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
local function key_down(k) -- 'KeyCtrl', 'KeyShift', 'KeyAlt': ImGui's io
    local ok, io = pcall(imgui.GetIO)
    return ok and (io ~= nil) and (io[k] == true)
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

-- Colours. The window and hover text are the bar's; the four meanings take the preset's shade
-- (gctheme keys), kept apart as /gcedit keeps its own.
local COL_BG, COL_EDGE = { 0.04, 0.045, 0.06, 0.70 }, { 1.0, 1.0, 1.0, 0.10 }
local COL_TIP_BG = { 0.04, 0.045, 0.06, 0.94 }
local COL_HEAD, COL_KEY, COL_DIM = { 0.93, 0.93, 0.96, 1.0 }, { 0.62, 0.68, 0.80, 1.0 }, { 0.55, 0.55, 0.61, 0.90 }
local SOCKET = { 0.27, 0.32, 0.41, 0.55 } -- a slot's square (bg on)
local SOCKET_BARE = { 0.27, 0.32, 0.41, 0.22 } -- the bare window: an empty slot only
local SHADE, OUTLINE, WHITE = { 0, 0, 0, 0.45 }, { 0, 0, 0, 0.90 }, { 1, 1, 1, 1 }
local MEANINGS = { 'lock', 'hold', 'feature', 'rp', 'warn' } -- warn: a swap that didn't go on
local OWN = { lock = { 1.00, 0.35, 0.35 }, hold = { 1.00, 0.72, 0.25 }, feature = { 0.65, 0.40, 1.00 },
    rp = { 1.00, 0.48, 0.72 }, warn = { 1.00, 0.54, 0.24 } }
local THEME_KEY = { lock = 'hp_0', hold = 'tp_max', feature = 'item', rp = 'ws', warn = 'hp_25' }
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

-- The 16 slots, read 4 times a second while the window is drawn (equipmon reads them on equipment
-- packets): a changed item (or its extdata: RP) is looked up again.
local POLL = 0.25
local nextPoll = 0
local check_missed -- below source(): a swap that didn't go on
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
    check_missed(now)
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
local OWNER_TEXT = { user = '/lock', aminon = 'Aminon', hoxne = 'Hoxne', proc = '/proc', enchant = 'item use, /gce' }
local OWNER_OFF = { enchant = '/gce cancel' } -- else gcinclude.LockOwnerFix
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

-- A missed swap: the slot's last swap named another item, nothing holds the slot (lock, hold, encumbrance, LAC's
-- disable) and it is still not on after MISS_AFTER seconds: the '!' mark. LAC's slot words name no item.
local MISS_AFTER = 2
local NOT_ITEMS = { remove = true, displaced = true, ignore = true }
local function free(c)
    if encumbered(c.game) or (holder(c.slot) ~= nil) then return false end
    return not ((gState ~= nil) and (gState.Disabled ~= nil) and (gState.Disabled[c.slot] == true))
end
check_missed = function(now)
    for _, c in ipairs(cells) do
        c.enc, c.holder = encumbered(c.game), holder(c.slot) -- for the marks (an alt's come from its file)
        local w, worn = source(c)
        local want = (w ~= nil) and string.lower(tostring(w.name)) or nil
        if (w ~= nil) and (not worn) and (not NOT_ITEMS[want]) and free(c) then
            if (c.missName ~= want) then c.missName, c.missSince = want, now end
            c.missed, c.missItem = (now - c.missSince) >= MISS_AFTER, tostring(w.name)
        else
            c.missName, c.missSince, c.missed, c.missItem = nil, nil, false, nil
        end
    end
end
-- Where a missed item is: an equip bag (LAC's gSettings.EquipBags), another bag, or none; read on hover, kept 3s.
local BAG_NAME = { [0] = 'Inventory', 'Safe', 'Storage', 'Temporary', 'Locker', 'Satchel', 'Sack', 'Case', 'Wardrobe',
    'Safe 2', 'Wardrobe 2', 'Wardrobe 3', 'Wardrobe 4', 'Wardrobe 5', 'Wardrobe 6', 'Wardrobe 7', 'Wardrobe 8' }
local EQUIP_BAGS = { 0, 8, 10, 11, 12, 13, 14, 15, 16 } -- LAC's default gSettings.EquipBags
local whereCache = {}
local function where(name)
    local l, now = string.lower(name), os.clock()
    local hit = whereCache[l]
    if (hit ~= nil) and (now < hit.until_) then return hit.kind, hit.bag, hit.r end
    local bags = ((gSettings ~= nil) and (type(gSettings.EquipBags) == 'table')) and gSettings.EquipBags or EQUIP_BAGS
    local equip = {}
    for _, b in pairs(bags) do equip[b] = true end
    local inv, res = AshitaCore:GetMemoryManager():GetInventory(), AshitaCore:GetResourceManager()
    local kind, bag, item = 'none', nil, nil
    for b = 0, 16 do
        for i = 1, (gData.GetContainerMax(b) or 0) do
            local it = inv:GetContainerItem(b, i)
            local r = ((it ~= nil) and (it.Id ~= 0) and (it.Id ~= 65535) and ((it.Count or 0) > 0))
                and res:GetItemById(it.Id) or nil
            if (r ~= nil) and (r.Name ~= nil) and (string.lower(tostring(r.Name[1])) == l) then
                if equip[b] then kind, bag, item = 'equip', BAG_NAME[b], r; break end
                if (kind == 'none') then kind, bag, item = 'stored', BAG_NAME[b], r end
            end
        end
        if (kind == 'equip') then break end
    end
    whereCache[l] = { kind = kind, bag = bag, r = item, until_ = now + 3 }
    return kind, bag, item
end
-- Why a missed item isn't on, as far as the bags and the item's jobs/level tell.
local function miss_text(name)
    local kind, bag, r = where(name)
    if (kind == 'none') then return 'Not on: no ' .. name .. ' in your bags' end
    if (kind == 'stored') then return 'Not on: ' .. name .. ' is in ' .. tostring(bag) .. ' (not an equip bag)' end
    local p = AshitaCore:GetMemoryManager():GetPlayer()
    local job, lv = p:GetMainJob(), p:GetMainJobLevel()
    if (r ~= nil) and (tonumber(r.Jobs) ~= nil) and (bit.band(r.Jobs, bit.lshift(1, job)) == 0) then
        return 'Not on: your job can\'t wear ' .. name
    end
    if (r ~= nil) and ((tonumber(r.Level) or 0) > (tonumber(lv) or 99)) then
        return 'Not on: ' .. name .. ' needs level ' .. tostring(r.Level)
    end
    return 'Not on: ' .. name .. ' (in ' .. tostring(bag) .. ')'
end

local function line(text, col)
    imgui.PushStyleColor(ImGuiCol_Text, col)
    imgui.TextUnformatted(text)
    imgui.PopStyleColor()
end
-- A layer label /gcedit can open: a set's own name, not a function (EquipIdle()) or a table path (Sets['x']).
local function editable(by)
    if (type(by) ~= 'string') or (by == '') or (by == '?') then return nil end
    if string.find(by, '[%(%[]') or (string.sub(by, 1, 10) == 'gcinclude.') then return nil end
    return by
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
            line('Locked: ' .. owner_text(o) .. ' (off: ' .. (OWNER_OFF[o] or tostring(inc.LockOwnerFix(o, c.slot)))
                .. ')',
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
    if c.missed and (w ~= nil) then line(miss_text(tostring(w.name)), COL.warn) end
    local set = (w ~= nil) and editable(w.by) or nil
    if (set ~= nil) then line('Right-click: /gcedit ' .. set, COL_DIM) end
    local mine = (inc ~= nil) and (inc.LockedSlots[c.slot] ~= nil) and (inc.LockedSlots[c.slot].user == true)
    line('Ctrl: ' .. (mine and '/unlock' or '/lock') .. '  Alt: take off  Shift: pick gear', COL_DIM)
end

-- A padlock at ox, oy, s px tall, in col, outlined dark so it reads over any icon.
local function padlock(dl, ox, oy, s, col)
    local dark, th = u32(OUTLINE), math.max(1.5, s / 7)
    -- the body, and the shackle above it (its lower edge drawn over by the body)
    local bx1, by1, bx2, by2 = ox, oy + s * 0.45, ox + s * 0.8, oy + s
    local sx1, sy1, sx2, sy2, r = ox + s * 0.18, oy, ox + s * 0.62, oy + s * 0.62, s * 0.25
    dl:AddRect(va(sx1, sy1), vb(sx2, sy2), dark, r, 0, th + 2)
    dl:AddRectFilled(va(bx1 - 1, by1 - 1), vb(bx2 + 1, by2 + 1), dark, 2)
    local fill = u32(col)
    dl:AddRect(va(sx1, sy1), vb(sx2, sy2), fill, r, 0, th)
    dl:AddRectFilled(va(bx1, by1), vb(bx2, by2), fill, 1.5)
    dl:AddCircleFilled(va((bx1 + bx2) / 2, (by1 + by2) / 2), math.max(1, s / 9), dark, 8) -- keyhole
end
-- One slot's marks over its icon: encumbrance X, holder padlock, RP corner, missed '!', ammo count.
local function marks(dl, c, x, y, cell)
    local x2, y2 = x + cell, y + cell
    if c.enc then -- equipmon's mark: the slot dimmed, a red X
        dl:AddRectFilled(va(x, y), vb(x2, y2), u32(SHADE), 3)
        local m, th = math.floor(cell * 0.22), math.max(2, cell / 12)
        dl:AddLine(va(x + m, y + m), vb(x2 - m, y2 - m), u32(COL.lock), th)
        dl:AddLine(va(x2 - m, y + m), vb(x + m, y2 - m), u32(COL.lock), th)
    end
    local h = c.holder
    if (h == 'hold') then -- the TP hold: an amber dot, bottom right (weapons carry no ammo count there)
        local r = math.max(2.5, cell / 10)
        dl:AddCircleFilled(va(x2 - r - 2, y2 - r - 2), r + 1, u32(OUTLINE), 12)
        dl:AddCircleFilled(va(x2 - r - 2, y2 - r - 2), r, u32(COL.hold), 12)
    elseif (h ~= nil) then
        local s = math.max(9, math.floor(cell * 0.36))
        padlock(dl, x + 2, y2 - 2 - s, s, COL[h])
    end
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
    local function outlined(text, tx, ty, col)
        local dark = u32(OUTLINE)
        dl:AddText(va(tx - 1, ty), dark, text); dl:AddText(va(tx + 1, ty), dark, text)
        dl:AddText(va(tx, ty - 1), dark, text); dl:AddText(va(tx, ty + 1), dark, text)
        dl:AddText(va(tx, ty), u32(col), text)
    end
    local ty = y2 - imgui.GetTextLineHeight() + 1
    if (c.item ~= nil) and ((c.stack or 1) > 1) then -- the ammo count, bottom right
        local text = tostring(c.count)
        outlined(text, x2 - textw(text) - 2, ty, WHITE)
    end
    if c.missed then outlined('!', x + 3, y + 1, COL.warn) end -- a missed swap, top left
end

-- An icon at alpha (ImGui's Image takes no tint here: the style's Alpha fades it, popped before the marks).
local function image(id, cell, alpha)
    if (alpha >= 1) or (ImGuiStyleVar_Alpha == nil) then imgui.Image(id, size(cell, cell)); return end
    imgui.PushStyleVar(ImGuiStyleVar_Alpha, alpha)
    local ok, why = pcall(imgui.Image, id, size(cell, cell))
    imgui.PopStyleVar()
    if not ok then error(why, 0) end
end
-- The 4x4 grid of list (this box's cells, or an alt's) at the cursor; alpha: the icons'; bare: no square behind a
-- worn slot. Returns the hovered slot's cell and a click on it.
local function grid_body(list, cell, gap, alpha, bare)
    budget = ICONS_PER_FRAME
    local dl, hovered, click = imgui.GetWindowDrawList(), nil, nil
    for i, c in ipairs(list) do
        if (((i - 1) % 4) ~= 0) then imgui.SameLine(0, gap) end
        local x, y = xy(imgui.GetCursorScreenPos())
        if (x ~= nil) and ((not bare) or (c.id == 0)) then
            dl:AddRectFilled(va(x, y), vb(x + cell, y + cell), u32(bare and SOCKET_BARE or SOCKET), 3)
        end
        local t = icon(c.id)
        if (t ~= nil) then image(t.id, cell, alpha) else imgui.Dummy(size(cell, cell)) end
        if imgui.IsItemHovered() then
            hovered = c
            if imgui.IsItemClicked(1) then click = 'edit'
            elseif imgui.IsItemClicked(0) then
                click = (key_down('KeyCtrl') and 'lock') or (key_down('KeyAlt') and 'off')
                    or (key_down('KeyShift') and 'pick') or nil
            end
        end
        if (x ~= nil) then marks(dl, c, x, y, cell) end
    end
    return hovered, click
end
local function grid(list, cell, gap, alpha, bare)
    colours()
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, va(gap, gap))
    local ok, r, click = pcall(grid_body, list, cell, gap, alpha or 1, bare) -- an error must not skip the Pop
    imgui.PopStyleVar()
    if not ok then error(r, 0) end
    return r, click
end
local function sizes(scale) -- a slot (32px at scale 1, as the game's icons) and the gap between slots
    return math.floor(32 * scale + 0.5), math.max(1, math.floor(scale + 0.5))
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

-- Sharing: every box writes its 16 slots to luashitacast\hud\<Name>.gear (gchud's folder; gchud reads only .txt)
-- when they change, and every 3s, from the engine's tick: "stamp" then per slot "id, count, flags (e encumbered, h
-- TP hold, r needs RP, m missed swap), lock owners, missed item". The box with the drop reads one on hover.
local SHARE_EVERY, SHARE_BEAT = 0.5, 3
local nextShare, lastBody, lastWrite = 0, nil, 0
local function hud_dir() return string.format('%sconfig\\addons\\luashitacast\\hud\\', AshitaCore:GetInstallPath()) end
local function share()
    local now = os.clock()
    if (now < nextShare) then return end
    nextShare = now + SHARE_EVERY
    local name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    if (type(name) ~= 'string') or (name == '') then return end
    poll()
    local parts = {}
    for i, c in ipairs(cells) do
        local owners = {}
        for o in pairs((inc ~= nil) and inc.LockedSlots[c.slot] or {}) do owners[#owners + 1] = o end
        table.sort(owners)
        local flags = (c.enc and 'e' or '') .. (((inc ~= nil) and (inc.HeldSlots[c.slot] ~= nil)) and 'h' or '')
            .. (((c.rp ~= nil) and c.rp.unfinished) and 'r' or '') .. (c.missed and 'm' or '')
        parts[i] = table.concat({ tostring(c.id), tostring(c.count), flags, table.concat(owners, ','),
            c.missed and tostring(c.missItem) or '' }, '\t')
    end
    local body, t = table.concat(parts, '\n'), os.time()
    if (body == lastBody) and ((t - lastWrite) < SHARE_BEAT) then return end
    local d = hud_dir()
    if not ashita.fs.exists(d) then ashita.fs.create_directory(d) end
    local f = io.open(d .. name .. '.gear', 'w')
    if (f == nil) then return end
    f:write(tostring(t) .. '\n' .. body)
    f:close()
    lastBody, lastWrite = body, t
end
gcgear.Tick = share -- gcinclude.Tick (guarded there)

-- Another box's slots, read from its file at most once a second.
local altCache = {}
local function read_alt(name)
    local now = os.clock()
    local hit = altCache[name]
    if (hit ~= nil) and (now < hit.until_) then return hit end
    local e = { until_ = now + 1 }
    altCache[name] = e
    local f = io.open(hud_dir() .. name .. '.gear', 'r')
    if (f == nil) then return e end
    local text = f:read('*a') or ''
    f:close()
    local rows = {}
    for l in string.gmatch(text, '[^\n]+') do rows[#rows + 1] = l end
    e.stamp = tonumber(rows[1])
    local res = AshitaCore:GetResourceManager()
    local list = {}
    for i, s in ipairs(ORDER) do
        local id, count, flags, owners, miss = string.match(rows[i + 1] or '', '^(%d+)\t(%d+)\t(%a*)\t([^\t]*)\t?(.*)$')
        if (id == nil) then return e end
        local c = { game = s, slot = s + 1, name = SLOT_NAME[s], id = tonumber(id) or 0, count = tonumber(count) or 0,
            owners = {} }
        local r = (c.id ~= 0) and res:GetItemById(c.id) or nil
        c.item = ((r ~= nil) and (r.Name ~= nil)) and r.Name[1] or nil
        c.stack = (r ~= nil) and (tonumber(r.StackSize) or 1) or 1
        for o in string.gmatch(owners, '[^,]+') do c.owners[#c.owners + 1] = o end
        local user = false
        for _, o in ipairs(c.owners) do if (o == 'user') then user = true end end
        c.enc = string.find(flags, 'e', 1, true) ~= nil
        c.holder = user and 'lock' or ((#c.owners > 0) and 'feature')
            or (string.find(flags, 'h', 1, true) and 'hold') or nil
        c.rp = string.find(flags, 'r', 1, true) and { unfinished = true } or nil
        c.missed = string.find(flags, 'm', 1, true) ~= nil
        c.missItem = (miss ~= '') and miss or nil
        list[i] = c
    end
    e.cells = list
    return e
end
-- Hover text for another box: its grid, then what holds which slot, and how old the file is.
local STALE = 15 -- s, as gchud
local function alt_tip(name, job, e)
    line(name .. '  ' .. tostring(job or ''), COL_HEAD)
    if (e.cells == nil) then line('No gear shared yet (an older GoomSwap there?)', COL_DIM); return end
    local cell, gap = sizes(cfg.scale)
    grid(e.cells, cell, gap, 1, false)
    local enc, locks, feats, held, rp, missed = 0, {}, {}, {}, {}, {}
    for _, c in ipairs(e.cells) do
        if c.enc then enc = enc + 1 end
        for _, o in ipairs(c.owners) do
            if (o == 'user') then locks[#locks + 1] = c.name
            else feats[#feats + 1] = c.name .. ' (' .. owner_text(o) .. ')' end
        end
        if (c.holder == 'hold') then held[#held + 1] = c.name end
        if (c.rp ~= nil) then rp[#rp + 1] = c.name end
        if c.missed then missed[#missed + 1] = c.name .. ((c.missItem ~= nil) and (' (' .. c.missItem .. ')') or '') end
    end
    if (enc > 0) then line('Encumbered: ' .. enc .. ' slot' .. ((enc == 1) and '' or 's'), COL.lock) end
    if (#locks > 0) then line('/lock: ' .. table.concat(locks, ', '), COL.lock) end
    if (#feats > 0) then line('Locked: ' .. table.concat(feats, ', '), COL.feature) end
    if (#held > 0) then line('Held for TP: ' .. table.concat(held, ', '), COL.hold) end
    if (#rp > 0) then line('Needs RP: ' .. table.concat(rp, ', '), COL.rp) end
    if (#missed > 0) then line('Not on: ' .. table.concat(missed, ', '), COL.warn) end
    local age = math.max(0, os.time() - (e.stamp or 0))
    line(((age > STALE) and 'stale: ' or 'as of ') .. age .. 's ago', COL_DIM)
end
local altOff = false -- an error turns the alt hover off, never the bar
function gcgear.AltTip(name, job) -- gcdisplay: a dropped line's name/job hovered
    if altOff or (type(name) ~= 'string') then return end
    local ok, why = pcall(function() tooltip(alt_tip, name, job, read_alt(name)) end)
    if not ok then
        altOff = true
        if (inc ~= nil) then inc.Err('Gear hover off after an error: ' .. tostring(why)) end
    end
end

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
    f:write(string.format('%s,%s,%s,%s,%s,%s', n(cfg.x), n(cfg.y), cfg.on and 'on' or 'off', tostring(cfg.scale),
        tostring(cfg.alpha), cfg.bg and 'on' or 'off'))
    f:close()
end
local function load_cfg()
    local dir, file = path()
    if (dir == nil) then return end
    local f = io.open(dir .. file, 'r')
    if (f == nil) then return end
    local text = f:read('*a') or ''
    f:close()
    local v = {}
    for part in string.gmatch(text, '[^,\r\n]+') do v[#v + 1] = part end
    if (#v < 4) then return end
    local alpha, bg = v[5], v[6]
    if (#v >= 7) then alpha, bg = v[6], v[7] end -- an older file: the bar map's on/off was 5th
    cfg.x, cfg.y = tonumber(v[1]), tonumber(v[2])
    if (cfg.x == nil) or (cfg.y == nil) then cfg.x, cfg.y = nil, nil end
    cfg.on = (v[3] == 'on')
    cfg.scale = math.max(0.5, math.min(3, tonumber(v[4]) or 1))
    cfg.alpha = math.max(0.2, math.min(1, tonumber(alpha) or 1))
    cfg.bg = (bg == 'on')
end

-- The window: no title bar, dragged anywhere; where it is let go is saved. Hidden with the game's interface, as the
-- bar is (gcdisplay.UiHidden).
local PAD, NO_PAD, CLEAR, FLAGS = { 4, 4 }, { 0, 0 }, { 0, 0, 0, 0 }, nil
-- Put item in c's slot now ('remove': take it off) and keep it there with your /lock, so the next swap doesn't put
-- the set's piece back; /unlock lets sets swap it again. Not over another owner's lock or encumbrance; a TP-held
-- weapon only once it is your /lock (Ctrl+click), so a click never costs your TP by itself.
local function wear(c, item)
    if encumbered(c.game) then inc.Err(c.name .. ' is encumbered'); return end
    local owners = inc.LockedSlots[c.slot] or {}
    for o in pairs(owners) do
        if (o ~= 'user') then
            inc.Err(c.name .. ' is locked by ' .. owner_text(o) .. ' (off: '
                .. (OWNER_OFF[o] or tostring(inc.LockOwnerFix(o, c.slot))) .. ')')
            return
        end
    end
    if (inc.HeldSlots[c.slot] ~= nil) and (owners.user ~= true) then
        inc.Err(c.name .. ' is held for your TP: Ctrl+click (/lock) it first to change it')
        return
    end
    if (owners.user == true) then inc.UnlockSlots({ c.slot }, 'user') end
    inc.HeldSlots[c.slot] = nil -- the unlock may have handed a weapon to the TP hold: force equips skip held slots
    gState.Disabled[c.slot] = false
    gFunc.ForceEquipSet({ [c.name] = item })
    inc.LockSlots({ c.slot }, 'user')
    inc.Say(c.name .. ': ' .. ((item == 'remove') and 'off' or item) .. ', locked (/unlock '
        .. string.lower(c.name) .. ' to let sets swap it)')
end
-- Shift+click: your gear that fits the slot, from the bags LAC equips from, wearable by this job at this level.
local pick = { cell = nil, list = nil }
local function gear_for(c)
    local bags = ((gSettings ~= nil) and (type(gSettings.EquipBags) == 'table')) and gSettings.EquipBags or EQUIP_BAGS
    local inv, res = AshitaCore:GetMemoryManager():GetInventory(), AshitaCore:GetResourceManager()
    local p = AshitaCore:GetMemoryManager():GetPlayer()
    local job, lv, bitSlot = p:GetMainJob(), tonumber(p:GetMainJobLevel()) or 99, bit.lshift(1, c.game)
    local byName, list = {}, {}
    for _, b in pairs(bags) do
        for i = 1, (gData.GetContainerMax(b) or 0) do
            local it = inv:GetContainerItem(b, i)
            local r = ((it ~= nil) and (it.Id ~= 0) and (it.Id ~= 65535) and ((it.Count or 0) > 0))
                and res:GetItemById(it.Id) or nil
            if (r ~= nil) and (r.Name ~= nil) and (type(r.Name[1]) == 'string')
                and (bit.band(tonumber(r.Slots) or 0, bitSlot) ~= 0)
                and (bit.band(tonumber(r.Jobs) or 0, bit.lshift(1, job)) ~= 0)
                and ((tonumber(r.Level) or 0) <= lv) then
                local key = string.lower(r.Name[1])
                local e = byName[key]
                if (e == nil) then
                    e = { name = r.Name[1], id = it.Id, bag = BAG_NAME[b] or tostring(b), n = 0 }
                    byName[key] = e
                    list[#list + 1] = e
                end
                e.n = e.n + 1
            end
        end
    end
    table.sort(list, function (a, b2) return string.lower(a.name) < string.lower(b2.name) end)
    return list
end
-- The list, drawn like the bar's right-click menus: dark and rounded, a soft hover; each row the item's icon, its
-- name, the bag on the right; the worn one outlined and tagged. Opens beside the grid (its right, else its left).
local PICK_ICON, PICK_ROWS, PICK_GAP, PICK_IN, SCROLL_W = 20, 14, 8, 4, 8 -- PICK_IN: the row's inner left margin
local PICK_HINT = 'click: wear it, keeps it (/lock)'
local MENU_PAD, MENU_SPACE = { 8, 6 }, { 6, 2 }
local COL_HOVER, COL_NONE, COL_LINE = { 1, 1, 1, 0.12 }, { 0, 0, 0, 0 }, { 1, 1, 1, 0.12 }
local WORN_FILL, WORN_EDGE = { 0.62, 0.68, 0.80, 0.10 }, { 0.62, 0.68, 0.80, 0.75 }
local SCROLL_GRAB, SCROLL_HOVER = { 1, 1, 1, 0.20 }, { 1, 1, 1, 0.35 }
-- Row width from the texts, and the spot beside the grid window (x, y, width), kept while the list is open.
local function pick_layout(c, wx, wy, ww)
    local nameW, bagW = textw('Take it off'), 0
    for _, e in ipairs(pick.list) do
        e.label = e.name .. ((e.n > 1) and (' x' .. e.n) or '')
        nameW, bagW = math.max(nameW, textw(e.label)), math.max(bagW, textw(e.bag))
    end
    local tagW = textw('worn') + 8
    pick.rowW = math.max(textw(c.name) + textw(PICK_HINT) + 24,
        PICK_IN + PICK_ICON + PICK_GAP + nameW + 16 + tagW + 8 + bagW + 8)
    local w = pick.rowW + 2 * MENU_PAD[1] + ((#pick.list > PICK_ROWS) and (SCROLL_W + 2) or 0)
    local ok, sw = pcall(function() return imgui.GetMainViewport().Size.x end)
    sw = ok and tonumber(sw) or 1920
    local px = wx + ww + 6
    if (px + w > sw) then px = math.max(0, wx - w - 6) end
    pick.pos = { math.floor(px), math.floor(wy) }
end
local function pick_row(dl, c, i, e) -- e: an item of pick.list, or 'off' (take it off)
    local x, y = xy(imgui.GetCursorScreenPos())
    local off = (e == 'off')
    local t = (not off) and icon(e.id) or nil
    imgui.Dummy(size(PICK_IN, PICK_ICON)) -- the margin inside the row's hover (kept inside a scrolling list's edge)
    imgui.SameLine(0, 0)
    if (t ~= nil) then imgui.Image(t.id, size(PICK_ICON, PICK_ICON)) else imgui.Dummy(size(PICK_ICON, PICK_ICON)) end
    imgui.SameLine(0, PICK_GAP)
    local clicked = imgui.Selectable('##gcgp' .. i, false, 0,
        size(pick.rowW - PICK_IN - PICK_ICON - PICK_GAP, PICK_ICON))
    if (x == nil) or (y == nil) then return clicked end
    local x2, y2 = x + pick.rowW, y + PICK_ICON
    local ix = x + PICK_IN -- the icon
    local lh = imgui.GetTextLineHeight()
    local ty, tx = y + math.floor((PICK_ICON - lh) / 2), ix + PICK_ICON + PICK_GAP
    local worn = (not off) and (c.item ~= nil) and (string.lower(c.item) == string.lower(e.name))
    if worn then
        dl:AddRectFilled(va(x, y - 1), vb(x2, y2 + 1), u32(WORN_FILL), 7)
        dl:AddRect(va(x, y - 1), vb(x2, y2 + 1), u32(WORN_EDGE), 7, 0, 1)
    end
    if imgui.IsItemHovered() then dl:AddRectFilled(va(x, y - 1), vb(x2, y2 + 1), u32(COL_HOVER), 7) end
    if off then -- a red X where the icon goes
        local m = 5
        dl:AddLine(va(ix + m, y + m), vb(ix + PICK_ICON - m, y + PICK_ICON - m), u32(COL.lock), 2)
        dl:AddLine(va(ix + PICK_ICON - m, y + m), vb(ix + m, y + PICK_ICON - m), u32(COL.lock), 2)
        dl:AddText(va(tx, ty), u32(COL_DIM), 'Take it off')
        return clicked
    end
    dl:AddText(va(tx, ty), u32(COL_HEAD), e.label)
    local bx = x2 - 8 - textw(e.bag)
    dl:AddText(va(bx, ty), u32(COL_DIM), e.bag)
    if worn then
        local tw = textw('worn')
        local px = bx - 12 - tw - 8
        dl:AddRect(va(px, y + 2), vb(px + tw + 8, y2 - 2), u32(WORN_EDGE), (PICK_ICON - 4) / 2, 0, 1)
        dl:AddText(va(px + 4, ty), u32(COL_KEY), 'worn')
    end
    return clicked
end
local function pick_body()
    local c = pick.cell
    local dl = imgui.GetWindowDrawList()
    local x0, y0 = xy(imgui.GetCursorScreenPos())
    line(c.name, COL_HEAD)
    if (x0 ~= nil) and (y0 ~= nil) then
        dl:AddText(va(x0 + pick.rowW - textw(PICK_HINT), y0), u32(COL_DIM), PICK_HINT)
    end
    imgui.Separator()
    budget = ICONS_PER_FRAME
    local picked = nil
    if (c.id ~= 0) and pick_row(dl, c, 0, 'off') then picked = 'remove' end
    if (#pick.list == 0) then line('Nothing in your equip bags fits it for this job.', COL_DIM) end
    local child = (#pick.list > PICK_ROWS)
    if child then
        imgui.BeginChild('##gcgear_picks', size(pick.rowW + SCROLL_W + 2, PICK_ROWS * (PICK_ICON + MENU_SPACE[2])), 0)
        dl = imgui.GetWindowDrawList()
    end
    for i, e in ipairs(pick.list) do
        if pick_row(dl, c, i, e) then picked = e.name end
    end
    if child then imgui.EndChild() end
    if (picked ~= nil) then
        wear(c, picked)
        imgui.CloseCurrentPopup()
    end
end
local function draw_pick()
    if (pick.cell == nil) then return end
    if (pick.pos ~= nil) then imgui.SetNextWindowPos(va(pick.pos[1], pick.pos[2]), ImGuiCond_Appearing) end
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, MENU_PAD)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, MENU_SPACE)
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, 10)
    imgui.PushStyleVar(ImGuiStyleVar_PopupBorderSize, 1)
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarSize, SCROLL_W)
    imgui.PushStyleColor(ImGuiCol_PopupBg, COL_TIP_BG)
    imgui.PushStyleColor(ImGuiCol_Border, COL_EDGE)
    imgui.PushStyleColor(ImGuiCol_Separator, COL_LINE)
    imgui.PushStyleColor(ImGuiCol_Header, COL_NONE) -- the rows' own hover and worn marks, not the theme's
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, COL_NONE)
    imgui.PushStyleColor(ImGuiCol_HeaderActive, COL_NONE)
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, COL_NONE) -- a thin grey scrollbar, not the theme's
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, SCROLL_GRAB)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, SCROLL_HOVER)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, SCROLL_HOVER)
    local ok, why = true, nil
    if imgui.BeginPopup('##gcgear_pick') then
        ok, why = pcall(pick_body)
        imgui.EndPopup()
    else
        pick.cell, pick.list, pick.pos = nil, nil, nil
    end
    imgui.PopStyleColor(10)
    imgui.PopStyleVar(5)
    if not ok then error(why, 0) end
end
-- Right-click a slot: /gcedit on the set that put it on (or asked for it), that slot selected. Ctrl+click: /lock or
-- /unlock it, as typed (its chat line). Alt+click: take it off; Shift+click: pick other gear (both kept: your /lock).
local function act(c, click)
    if (click == 'edit') then
        local w = source(c)
        local set = (w ~= nil) and editable(w.by) or nil
        if (set == nil) then inc.Say(c.name .. ': no set recorded for it yet'); return end
        inc.EditorCommand(set, c.name)
    elseif (click == 'lock') then
        local mine = (inc.LockedSlots[c.slot] ~= nil) and (inc.LockedSlots[c.slot].user == true)
        local cmd = (mine and 'unlock ' or 'lock ') .. string.lower(c.name)
        AshitaCore:GetChatManager():QueueCommand(-1, '/lac fwd ' .. cmd)
    elseif (click == 'off') then
        if (c.id == 0) then inc.Say(c.name .. ' is empty'); return end
        wear(c, 'remove')
    elseif (click == 'pick') then
        pick.cell, pick.list = c, gear_for(c)
        local wx, wy = xy(imgui.GetWindowPos())
        local ww = xy(imgui.GetWindowSize())
        pick_layout(c, wx or 0, wy or 0, ww or 0)
        imgui.OpenPopup('##gcgear_pick')
    end
end
local function window_body(cell, gap)
    poll()
    local c, click = grid(cells, cell, gap, cfg.alpha, not cfg.bg)
    if (c ~= nil) then tooltip(details, c) end
    if (c ~= nil) and (click ~= nil) and (inc ~= nil) then act(c, click) end
    draw_pick()
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
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, cfg.bg and PAD or NO_PAD)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6)
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, cfg.bg and 1 or 0)
    imgui.PushStyleColor(ImGuiCol_WindowBg, cfg.bg and COL_BG or CLEAR)
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

-- /gcgear [on|off] | pos x y | reset | scale N | alpha N | bg [on|off]
function gcgear.HandleCommand(args)
    local arg = (args[2] ~= nil) and string.lower(args[2]) or nil
    if (arg == 'pos') and (tonumber(args[3]) ~= nil) and (tonumber(args[4]) ~= nil) then
        cfg.x, cfg.y, placed = math.floor(tonumber(args[3])), math.floor(tonumber(args[4])), false
        save_cfg()
        return
    elseif (arg == 'reset') then -- back to the first spot and size
        cfg.x, cfg.y, cfg.scale, cfg.alpha, placed = nil, nil, 1, 1, false
        save_cfg()
        inc.Say('Gear grid: first spot, scale 1, alpha 1')
        return
    elseif (arg == 'alpha') then -- the icons' opacity, 0.2-1 (equipmon's Opacity)
        local n = tonumber(args[3])
        if (n == nil) then
            inc.Say('Gear grid icon alpha: ' .. tostring(cfg.alpha) .. ' (/gcgear alpha 0.2-1)')
            return
        end
        cfg.alpha = math.max(0.2, math.min(1, n))
        save_cfg()
        inc.Say('Gear grid icon alpha: ' .. tostring(cfg.alpha))
        return
    elseif (arg == 'bg') then -- the window's background panel
        local v = (args[3] ~= nil) and string.lower(args[3]) or nil
        if (v == 'on') then cfg.bg = true
        elseif (v == 'off') then cfg.bg = false
        elseif (v == nil) then cfg.bg = not cfg.bg
        else inc.Err('usage: /gcgear bg [on|off]'); return end
        save_cfg()
        inc.Say('Gear grid background: ' .. (cfg.bg and 'On' or 'Off'))
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
        inc.Err('usage: /gcgear [on|off|pos x y|reset|scale N|alpha N|bg on|off]')
        return
    end
    save_cfg()
    inc.Say('Gear grid: ' .. (cfg.on and 'On' or 'Off'))
end

return gcgear
