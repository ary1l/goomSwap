-- Colour presets shared with goomui: same names and colours (goomui modules/theme.lua; only the keys used here).
-- GoomSwap follows the preset goomui saved for this character (config/addons/goomui/<Name>_<id>/bar.lua, `theme`);
-- settings.Theme names one instead ('goomswap' = GoomSwap's own colours). Neither: GoomSwap's own colours.
-- Meanings stay fixed: job and weapon-class colours never change; mode, toggle and state colours take the
-- preset's shade for the same meaning (MP blue, HP green, TP...).
local gctheme = {}

gctheme.ORDER = { 'vivid', 'ember', 'ocean', 'synth', 'aurora', 'abyss', 'moss', 'frost', 'royal', 'sakura', 'dusk',
    'citrus', 'nord', 'dracula', 'candy', 'toxic', 'retro', 'matrix', 'sunset', 'mocha', 'duality', 'galaxy',
    'vaporwave', 'desert', 'gems', 'gameboy', 'bloodmoon', 'crystal', 'mono', 'classic' }
gctheme.PRESETS = {
    vivid = { hp_full = { 95, 211, 106 }, hp_50 = { 242, 201, 76 }, hp_25 = { 240, 138, 60 }, hp_0 = { 229, 72, 77 },
        mp = { 76, 156, 255 }, tp = { 140, 124, 240 }, tp_rdy = { 180, 156, 255 }, tp_max = { 255, 207, 74 },
        spell = { 111, 208, 160 }, item = { 196, 156, 255 }, hit = { 90, 168, 255 }, crit = { 255, 207, 74 },
        ws = { 224, 124, 240 }, heal = { 95, 211, 106 }, counter = { 229, 72, 77 }, r3 = { 140, 202, 255 } },
    ember = { hp_full = { 255, 179, 71 }, hp_50 = { 255, 107, 61 }, hp_25 = { 232, 69, 60 }, hp_0 = { 192, 38, 45 },
        mp = { 63, 193, 201 }, tp = { 199, 125, 255 }, tp_rdy = { 224, 163, 255 }, tp_max = { 255, 209, 102 },
        spell = { 255, 159, 67 }, item = { 224, 163, 255 }, hit = { 240, 138, 60 }, crit = { 255, 224, 138 },
        ws = { 255, 110, 199 }, heal = { 120, 214, 120 }, counter = { 192, 38, 45 }, r3 = { 240, 138, 60 } },
    ocean = { hp_full = { 46, 230, 198 }, hp_50 = { 242, 208, 107 }, hp_25 = { 240, 144, 90 }, hp_0 = { 229, 84, 106 },
        mp = { 58, 134, 255 }, tp = { 108, 99, 255 }, tp_rdy = { 157, 140, 255 }, tp_max = { 255, 209, 102 },
        spell = { 46, 196, 182 }, item = { 157, 140, 255 }, hit = { 26, 159, 176 }, crit = { 255, 209, 102 },
        ws = { 157, 140, 255 }, heal = { 46, 230, 198 }, counter = { 229, 84, 106 }, r3 = { 63, 208, 217 } },
    synth = { hp_full = { 57, 255, 136 }, hp_50 = { 255, 225, 77 }, hp_25 = { 255, 138, 61 }, hp_0 = { 255, 61, 110 },
        mp = { 0, 212, 255 }, tp = { 200, 60, 170 }, tp_rdy = { 255, 79, 216 }, tp_max = { 255, 240, 77 },
        spell = { 0, 212, 255 }, item = { 255, 79, 216 }, hit = { 0, 212, 255 }, crit = { 255, 240, 77 },
        ws = { 255, 79, 216 }, heal = { 57, 255, 136 }, counter = { 255, 61, 110 }, r3 = { 194, 61, 255 } },
    aurora = { hp_full = { 79, 240, 181 }, hp_50 = { 242, 208, 107 }, hp_25 = { 240, 144, 90 }, hp_0 = { 229, 84, 106 },
        mp = { 90, 160, 255 }, tp = { 138, 108, 255 }, tp_rdy = { 184, 156, 255 }, tp_max = { 255, 211, 107 },
        spell = { 79, 209, 232 }, item = { 184, 156, 255 }, hit = { 47, 184, 160 }, crit = { 255, 211, 107 },
        ws = { 199, 125, 255 }, heal = { 79, 240, 181 }, counter = { 229, 72, 77 }, r3 = { 79, 209, 232 } },
    abyss = { hp_full = { 89, 195, 195 }, hp_50 = { 233, 196, 106 }, hp_25 = { 244, 132, 95 }, hp_0 = { 247, 37, 133 },
        mp = { 67, 97, 238 }, tp = { 114, 9, 183 }, tp_rdy = { 181, 23, 158 }, tp_max = { 247, 37, 133 },
        spell = { 76, 201, 240 }, item = { 181, 23, 158 }, hit = { 67, 97, 238 }, crit = { 247, 37, 133 },
        ws = { 181, 23, 158 }, heal = { 89, 195, 195 }, counter = { 229, 72, 77 }, r3 = { 76, 201, 240 } },
    moss = { hp_full = { 156, 191, 90 }, hp_50 = { 224, 195, 90 }, hp_25 = { 217, 135, 74 }, hp_0 = { 196, 84, 74 },
        mp = { 111, 159, 160 }, tp = { 168, 148, 106 }, tp_rdy = { 210, 182, 122 }, tp_max = { 240, 210, 122 },
        spell = { 156, 191, 90 }, item = { 210, 182, 122 }, hit = { 143, 191, 95 }, crit = { 240, 210, 122 },
        ws = { 210, 182, 122 }, heal = { 156, 191, 90 }, counter = { 229, 72, 77 }, r3 = { 143, 191, 95 } },
    frost = { hp_full = { 223, 246, 255 }, hp_50 = { 242, 208, 107 }, hp_25 = { 240, 144, 90 }, hp_0 = { 229, 84, 106 },
        mp = { 127, 184, 255 }, tp = { 154, 166, 224 }, tp_rdy = { 220, 226, 255 }, tp_max = { 255, 233, 168 },
        spell = { 168, 224, 255 }, item = { 220, 226, 255 }, hit = { 160, 208, 255 }, crit = { 255, 233, 168 },
        ws = { 220, 226, 255 }, heal = { 191, 240, 216 }, counter = { 229, 72, 77 }, r3 = { 160, 208, 255 } },
    royal = { hp_full = { 212, 175, 55 }, hp_50 = { 224, 154, 60 }, hp_25 = { 217, 102, 60 }, hp_0 = { 192, 57, 43 },
        mp = { 122, 106, 224 }, tp = { 155, 89, 182 }, tp_rdy = { 195, 155, 211 }, tp_max = { 241, 196, 15 },
        spell = { 212, 175, 55 }, item = { 195, 155, 211 }, hit = { 155, 89, 182 }, crit = { 241, 196, 15 },
        ws = { 212, 175, 55 }, heal = { 127, 209, 127 }, counter = { 229, 72, 77 }, r3 = { 155, 89, 182 } },
    sakura = { hp_full = { 255, 158, 199 }, hp_50 = { 255, 210, 127 }, hp_25 = { 255, 154, 90 }, hp_0 = { 229, 72, 77 },
        mp = { 143, 211, 255 }, tp = { 200, 162, 255 }, tp_rdy = { 226, 198, 255 }, tp_max = { 255, 241, 168 },
        spell = { 255, 158, 199 }, item = { 226, 198, 255 }, hit = { 255, 143, 191 }, crit = { 255, 241, 168 },
        ws = { 226, 198, 255 }, heal = { 159, 224, 176 }, counter = { 229, 72, 77 }, r3 = { 255, 143, 191 } },
    dusk = { hp_full = { 246, 193, 119 }, hp_50 = { 234, 154, 151 }, hp_25 = { 224, 113, 122 },
        hp_0 = { 235, 111, 146 }, mp = { 156, 207, 216 }, tp = { 166, 139, 214 }, tp_rdy = { 196, 167, 231 },
        tp_max = { 246, 193, 119 }, spell = { 235, 188, 186 }, item = { 196, 167, 231 }, hit = { 156, 207, 216 },
        crit = { 246, 193, 119 }, ws = { 196, 167, 231 }, heal = { 156, 207, 216 }, counter = { 229, 72, 77 },
        r3 = { 196, 167, 231 } },
    citrus = { hp_full = { 163, 230, 53 }, hp_50 = { 250, 204, 21 }, hp_25 = { 251, 146, 60 }, hp_0 = { 239, 68, 68 },
        mp = { 34, 211, 238 }, tp = { 236, 72, 153 }, tp_rdy = { 244, 114, 182 }, tp_max = { 253, 224, 71 },
        spell = { 163, 230, 53 }, item = { 244, 114, 182 }, hit = { 132, 204, 22 }, crit = { 253, 224, 71 },
        ws = { 244, 114, 182 }, heal = { 163, 230, 53 }, counter = { 229, 72, 77 }, r3 = { 250, 204, 21 } },
    nord = { hp_full = { 163, 190, 140 }, hp_50 = { 235, 203, 139 }, hp_25 = { 208, 135, 112 }, hp_0 = { 191, 97, 106 },
        mp = { 129, 161, 193 }, tp = { 157, 132, 184 }, tp_rdy = { 180, 142, 173 }, tp_max = { 235, 203, 139 },
        spell = { 136, 192, 208 }, item = { 180, 142, 173 }, hit = { 129, 161, 193 }, crit = { 235, 203, 139 },
        ws = { 180, 142, 173 }, heal = { 163, 190, 140 }, counter = { 229, 72, 77 }, r3 = { 136, 192, 208 } },
    dracula = { hp_full = { 80, 250, 123 }, hp_50 = { 241, 250, 140 }, hp_25 = { 255, 184, 108 },
        hp_0 = { 255, 85, 85 }, mp = { 139, 233, 253 }, tp = { 189, 147, 249 }, tp_rdy = { 255, 121, 198 },
        tp_max = { 241, 250, 140 }, spell = { 139, 233, 253 }, item = { 255, 121, 198 }, hit = { 189, 147, 249 },
        crit = { 241, 250, 140 }, ws = { 255, 121, 198 }, heal = { 80, 250, 123 }, counter = { 255, 85, 85 },
        r3 = { 189, 147, 249 } },
    candy = { hp_full = { 123, 223, 242 }, hp_50 = { 255, 243, 176 }, hp_25 = { 255, 180, 162 },
        hp_0 = { 255, 107, 129 }, mp = { 162, 210, 255 }, tp = { 242, 181, 212 }, tp_rdy = { 255, 175, 204 },
        tp_max = { 255, 243, 176 }, spell = { 178, 247, 239 }, item = { 255, 175, 204 }, hit = { 189, 224, 254 },
        crit = { 255, 243, 176 }, ws = { 255, 175, 204 }, heal = { 178, 247, 239 }, counter = { 229, 72, 77 },
        r3 = { 162, 210, 255 } },
    toxic = { hp_full = { 198, 255, 0 }, hp_50 = { 255, 214, 10 }, hp_25 = { 255, 140, 0 }, hp_0 = { 255, 0, 110 },
        mp = { 123, 44, 191 }, tp = { 255, 0, 110 }, tp_rdy = { 255, 77, 148 }, tp_max = { 255, 190, 11 },
        spell = { 198, 255, 0 }, item = { 255, 77, 148 }, hit = { 157, 78, 221 }, crit = { 255, 190, 11 },
        ws = { 255, 0, 110 }, heal = { 198, 255, 0 }, counter = { 229, 72, 77 }, r3 = { 157, 78, 221 } },
    retro = { hp_full = { 255, 176, 0 }, hp_50 = { 255, 140, 0 }, hp_25 = { 255, 106, 0 }, hp_0 = { 229, 72, 77 },
        mp = { 204, 138, 0 }, tp = { 153, 102, 0 }, tp_rdy = { 255, 204, 102 }, tp_max = { 255, 240, 179 },
        spell = { 255, 176, 0 }, item = { 255, 204, 102 }, hit = { 255, 176, 0 }, crit = { 255, 240, 179 },
        ws = { 255, 204, 102 }, heal = { 255, 204, 102 }, counter = { 229, 72, 77 }, r3 = { 204, 138, 0 } },
    matrix = { hp_full = { 0, 255, 65 }, hp_50 = { 184, 240, 0 }, hp_25 = { 255, 160, 0 }, hp_0 = { 229, 72, 77 },
        mp = { 0, 179, 44 }, tp = { 0, 143, 17 }, tp_rdy = { 92, 255, 138 }, tp_max = { 208, 255, 216 },
        spell = { 0, 255, 65 }, item = { 92, 255, 138 }, hit = { 0, 200, 55 }, crit = { 208, 255, 216 },
        ws = { 92, 255, 138 }, heal = { 92, 255, 138 }, counter = { 229, 72, 77 }, r3 = { 0, 200, 55 } },
    sunset = { hp_full = { 255, 207, 107 }, hp_50 = { 255, 150, 113 }, hp_25 = { 255, 111, 145 },
        hp_0 = { 201, 24, 74 }, mp = { 132, 94, 194 }, tp = { 214, 93, 177 }, tp_rdy = { 255, 111, 145 },
        tp_max = { 255, 199, 95 }, spell = { 255, 150, 113 }, item = { 214, 93, 177 }, hit = { 214, 93, 177 },
        crit = { 255, 199, 95 }, ws = { 255, 111, 145 }, heal = { 255, 207, 107 }, counter = { 229, 72, 77 },
        r3 = { 255, 111, 145 } },
    mocha = { hp_full = { 212, 163, 115 }, hp_50 = { 224, 178, 82 }, hp_25 = { 200, 118, 60 }, hp_0 = { 164, 50, 43 },
        mp = { 233, 216, 166 }, tp = { 141, 110, 99 }, tp_rdy = { 188, 138, 95 }, tp_max = { 255, 209, 102 },
        spell = { 212, 163, 115 }, item = { 188, 138, 95 }, hit = { 161, 136, 127 }, crit = { 255, 209, 102 },
        ws = { 188, 138, 95 }, heal = { 212, 163, 115 }, counter = { 229, 72, 77 }, r3 = { 141, 110, 99 } },
    duality = { hp_full = { 76, 201, 240 }, hp_50 = { 249, 199, 79 }, hp_25 = { 248, 150, 30 }, hp_0 = { 249, 65, 68 },
        mp = { 67, 97, 238 }, tp = { 243, 114, 44 }, tp_rdy = { 248, 150, 30 }, tp_max = { 249, 199, 79 },
        spell = { 76, 201, 240 }, item = { 243, 114, 44 }, hit = { 76, 201, 240 }, crit = { 249, 199, 79 },
        ws = { 249, 65, 68 }, heal = { 76, 201, 240 }, counter = { 229, 72, 77 }, r3 = { 249, 199, 79 } },
    galaxy = { hp_full = { 224, 170, 255 }, hp_50 = { 255, 214, 165 }, hp_25 = { 255, 158, 125 },
        hp_0 = { 255, 77, 109 }, mp = { 123, 44, 191 }, tp = { 157, 78, 221 }, tp_rdy = { 199, 125, 255 },
        tp_max = { 255, 243, 176 }, spell = { 199, 125, 255 }, item = { 224, 170, 255 }, hit = { 157, 78, 221 },
        crit = { 255, 243, 176 }, ws = { 224, 170, 255 }, heal = { 224, 170, 255 }, counter = { 229, 72, 77 },
        r3 = { 157, 78, 221 } },
    vaporwave = { hp_full = { 255, 113, 206 }, hp_50 = { 255, 251, 150 }, hp_25 = { 255, 184, 108 },
        hp_0 = { 255, 56, 100 }, mp = { 1, 205, 254 }, tp = { 185, 103, 255 }, tp_rdy = { 212, 160, 255 },
        tp_max = { 255, 251, 150 }, spell = { 5, 255, 161 }, item = { 185, 103, 255 }, hit = { 1, 205, 254 },
        crit = { 255, 251, 150 }, ws = { 255, 113, 206 }, heal = { 5, 255, 161 }, counter = { 229, 72, 77 },
        r3 = { 185, 103, 255 } },
    desert = { hp_full = { 233, 196, 106 }, hp_50 = { 244, 162, 97 }, hp_25 = { 231, 111, 81 }, hp_0 = { 181, 23, 46 },
        mp = { 42, 157, 143 }, tp = { 231, 111, 81 }, tp_rdy = { 244, 162, 97 }, tp_max = { 255, 209, 102 },
        spell = { 233, 196, 106 }, item = { 231, 111, 81 }, hit = { 42, 157, 143 }, crit = { 255, 209, 102 },
        ws = { 231, 111, 81 }, heal = { 42, 157, 143 }, counter = { 229, 72, 77 }, r3 = { 233, 196, 106 } },
    gems = { hp_full = { 46, 204, 113 }, hp_50 = { 255, 215, 0 }, hp_25 = { 255, 140, 0 }, hp_0 = { 224, 17, 95 },
        mp = { 15, 82, 186 }, tp = { 155, 17, 30 }, tp_rdy = { 224, 17, 95 }, tp_max = { 255, 215, 0 },
        spell = { 46, 204, 113 }, item = { 153, 102, 204 }, hit = { 15, 82, 186 }, crit = { 255, 215, 0 },
        ws = { 224, 17, 95 }, heal = { 46, 204, 113 }, counter = { 229, 72, 77 }, r3 = { 224, 17, 95 } },
    gameboy = { hp_full = { 155, 188, 15 }, hp_50 = { 200, 180, 0 }, hp_25 = { 224, 138, 0 }, hp_0 = { 229, 72, 77 },
        mp = { 95, 143, 47 }, tp = { 48, 98, 48 }, tp_rdy = { 139, 172, 15 }, tp_max = { 224, 248, 208 },
        spell = { 155, 188, 15 }, item = { 139, 172, 15 }, hit = { 139, 172, 15 }, crit = { 224, 248, 208 },
        ws = { 155, 188, 15 }, heal = { 155, 188, 15 }, counter = { 229, 72, 77 }, r3 = { 139, 172, 15 } },
    bloodmoon = { hp_full = { 217, 217, 217 }, hp_50 = { 224, 159, 62 }, hp_25 = { 208, 0, 0 }, hp_0 = { 139, 0, 0 },
        mp = { 74, 78, 105 }, tp = { 157, 2, 8 }, tp_rdy = { 208, 0, 0 }, tp_max = { 253, 240, 213 },
        spell = { 192, 192, 192 }, item = { 157, 2, 8 }, hit = { 157, 2, 8 }, crit = { 253, 240, 213 },
        ws = { 208, 0, 0 }, heal = { 192, 192, 192 }, counter = { 255, 77, 77 }, r3 = { 157, 2, 8 } },
    crystal = { hp_full = { 155, 232, 255 }, hp_50 = { 242, 226, 122 }, hp_25 = { 245, 162, 93 },
        hp_0 = { 232, 74, 74 }, mp = { 91, 140, 255 }, tp = { 169, 139, 255 }, tp_rdy = { 217, 184, 255 },
        tp_max = { 255, 241, 184 }, spell = { 155, 232, 255 }, item = { 217, 184, 255 }, hit = { 91, 200, 255 },
        crit = { 255, 241, 184 }, ws = { 217, 184, 255 }, heal = { 126, 224, 138 }, counter = { 229, 72, 77 },
        r3 = { 232, 197, 71 } },
    mono = { hp_full = { 232, 232, 232 }, hp_50 = { 242, 201, 76 }, hp_25 = { 240, 138, 60 }, hp_0 = { 229, 72, 77 },
        mp = { 159, 180, 200 }, tp = { 138, 138, 138 }, tp_rdy = { 208, 208, 208 }, tp_max = { 255, 210, 74 },
        spell = { 200, 200, 200 }, item = { 160, 160, 160 }, hit = { 170, 170, 170 }, crit = { 255, 210, 74 },
        ws = { 230, 230, 230 }, heal = { 200, 230, 200 }, counter = { 229, 72, 77 }, r3 = { 153, 153, 153 } },
    classic = { hp_full = { 31, 140, 31 }, hp_50 = { 255, 204, 0 }, hp_25 = { 255, 115, 0 }, hp_0 = { 230, 26, 26 },
        mp = { 63, 127, 232 }, tp = { 106, 99, 214 }, tp_rdy = { 150, 140, 255 }, tp_max = { 255, 208, 64 },
        spell = { 89, 158, 255 }, item = { 184, 117, 255 }, hit = { 0, 0, 237 }, crit = { 119, 119, 237 },
        ws = { 184, 117, 255 }, heal = { 102, 255, 7 }, counter = { 237, 0, 0 }, r3 = { 60, 220, 120 } },
}

-- Which preset: the setting, else goomui's saved one (its default 'vivid' when bar.lua names none), else nil.
function gctheme.Resolve(setting, goomuiText)
    if type(setting) == 'string' then
        local name = string.lower(setting)
        return (gctheme.PRESETS[name] ~= nil) and name or nil
    end
    if type(goomuiText) ~= 'string' then return nil end
    local name = string.match(goomuiText, '%[%s*["\']theme["\']%s*%]%s*=%s*["\']([%w_]+)["\']')
    name = string.lower(name or 'vivid')
    return (gctheme.PRESETS[name] ~= nil) and name or nil
end

-- goomui's bar.lua for this character, as text (never run); nil off Ashita or without goomui.
function gctheme.GoomuiText()
    if (gState == nil) or (gState.PlayerName == nil) or (gState.PlayerId == nil) then return nil end
    local path = string.format('%sconfig\\addons\\goomui\\%s_%u\\bar.lua', AshitaCore:GetInstallPath(),
        gState.PlayerName, gState.PlayerId)
    local f = io.open(path, 'r')
    if f == nil then return nil end
    local text = f:read('*a')
    f:close()
    return text
end

-- A preset's colour as ImGui floats, or nil.
function gctheme.Color(name, key, alpha)
    local p = gctheme.PRESETS[name or '']
    local c = p and p[key]
    return c and { c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1.0 } or nil
end

-- Repaint colour tables in place (their holders keep the references): { {target, key}, ... }.
function gctheme.Paint(name, pairs_)
    for _, p in ipairs(pairs_) do
        local c = gctheme.Color(name, p[2])
        if c ~= nil then p[1][1], p[1][2], p[1][3] = c[1], c[2], c[3] end
    end
end

-- Background tint: a preset colour mixed into a dark base by amount (0-1), in place.
function gctheme.Tint(target, name, key, base, amount)
    local c = gctheme.Color(name, key)
    if c ~= nil then
        for i = 1, 3 do
            target[i] = base[i] + (c[i] - base[i]) * amount
        end
    end
end

return gctheme
