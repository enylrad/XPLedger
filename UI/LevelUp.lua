--[[----------------------------------------------------------------------------
    XPLedger - Level up summary
    A banner in the middle of the screen shown on every level up (WoW Forever
    only for now), drawn like the game's own announcements rather than as a
    tooltip box:

        ───────────── gold line ─────────────
                       Level 20!
                  (glowing round portrait)
                       Character
          ── Stats gained ──   ── abilities ──   ── zones ──
        ───────────── gold line ─────────────

    The background is a dark band that fades out to both sides, so the world
    stays visible. It pops in, fades out on its own, waits while the mouse is
    over it and closes on click. /xpl levelup shows it as a preview.

    It does not follow the interface skin on purpose: it is an in-world
    announcement, not a window.
------------------------------------------------------------------------------]]

local _, ns = ...

local LevelUp = ns:NewModule("LevelUp")
local Theme = ns.Theme
local L = ns.L

local WIDTH = 560          -- band width; the text column is narrower
local ROW_WIDTH = 240      -- name on the left edge, value on the right edge
local ROW_HEIGHT = 18
local ROW_ICON_HEIGHT = 24
local OFFSET_Y = 120
local SHOW_SECONDS = 12
local FADE_IN = 0.35
local FADE_OUT = 0.6
local MAX_SPELLS = 6
local ICON_SIZE = 20
local PORTRAIT_SIZE = 84
local RING = 3             -- gold ring thickness around the portrait
local GLOW_SIZE = 190
local BAND_ALPHA = 0.75

local GOLD = { 1, 0.82, 0 }
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HALO_ALPHAS = { 0.35, 0.18, 0.08 } -- innermost first
local HALO_STEP = 6                       -- extra radius per halo circle

local COLOR_GAIN = "|cff1eff00"
local COLOR_DIM = "|cff9d9d9d"
local COLOR_OWN_ZONE = "|cff8fd16f"
local COLOR_CONTESTED = "|cffffd100"

local frame

--------------------------------------------------------------------------------
-- Text builders
--------------------------------------------------------------------------------

local function StatName(index)
    return _G["SPELL_STAT" .. index .. "_NAME"] or ("Stat " .. index)
end

-- Every section is a list of rows: { icon?, left, right? }. The left column
-- holds the name, the right one the number (gain, price, level range), so
-- the values line up whatever the length of the names.

local function GainRow(amount, label)
    return { left = label, right = ("%s+%d|r"):format(COLOR_GAIN, amount) }
end

local function StatRows(result)
    local rows = {}
    if result.health then
        rows[#rows + 1] = GainRow(result.health, _G.HEALTH or L["LEVELUP_HEALTH"])
    end
    if result.power then
        local powerName = result.powerToken and _G[result.powerToken] or nil
        rows[#rows + 1] = GainRow(result.power, powerName or L["LEVELUP_POWER"])
    end
    for i = 1, 5 do
        local gain = result.stats and result.stats[i]
        if gain then
            rows[#rows + 1] = GainRow(gain, StatName(i))
        end
    end
    if result.talents then
        rows[#rows + 1] = GainRow(result.talents, L["LEVELUP_TALENT_POINTS"])
    end
    return rows
end

--- Money with coin icons. Retail moved the helper into C_CurrencyInfo.
local function CoinText(copper)
    local format = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString
    return format and format(copper) or nil
end

local function SpellRows(spells)
    local rows = {}
    for i = 1, math.min(#spells, MAX_SPELLS) do
        local spell = spells[i]
        local name = spell.name
        -- Only real ranks ("Rank 2" in any language); other subtexts such
        -- as "Shapeshift" add nothing here.
        if spell.rank and spell.rank:find("%d") then
            name = ("%s %s(%s)|r"):format(name, COLOR_DIM, spell.rank)
        end
        rows[#rows + 1] = {
            icon = spell.icon or false,
            left = name,
            right = spell.cost and spell.cost > 0 and CoinText(spell.cost) or nil,
        }
    end
    if #spells > MAX_SPELLS then
        rows[#rows + 1] = { left = COLOR_DIM .. L["LEVELUP_MORE"]:format(#spells - MAX_SPELLS) .. "|r" }
    end
    return rows
end

local function ZoneRows(zones)
    local rows = {}
    for _, zone in ipairs(zones) do
        local color = zone.faction and COLOR_OWN_ZONE or COLOR_CONTESTED
        rows[#rows + 1] = {
            left = color .. zone.name .. "|r",
            right = ("%s%d-%d|r"):format(COLOR_DIM, zone.min, zone.max),
        }
    end
    return rows
end

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------

--- Font string with the game font, an outline and a soft shadow, so it reads
--- over any scenery.
local function CreateFont(parent, size, color, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(Theme.FONT, size, "OUTLINE")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.8)
    text:SetJustifyH("CENTER")
    if color then
        text:SetTextColor(color[1], color[2], color[3])
    end
    return text
end

--- Horizontal gradient of one color between two alphas (modern and legacy API).
local function SetFade(texture, color, alphaLeft, alphaRight)
    texture:SetTexture(Theme.WHITE)
    local r, g, b = color[1], color[2], color[3]
    if CreateColor and texture.SetGradient then
        local ok = pcall(texture.SetGradient, texture, "HORIZONTAL",
            CreateColor(r, g, b, alphaLeft), CreateColor(r, g, b, alphaRight))
        if ok then
            return
        end
    end
    if texture.SetGradientAlpha then
        texture:SetGradientAlpha("HORIZONTAL", r, g, b, alphaLeft, r, g, b, alphaRight)
    else
        texture:SetVertexColor(r, g, b, math.max(alphaLeft, alphaRight) / 2)
    end
end

--- A line (or band) that is solid in the middle and fades out to both ends.
local function CreateFadedStrip(parent, color, alpha, width, height, layer)
    local left = parent:CreateTexture(nil, layer or "ARTWORK")
    local right = parent:CreateTexture(nil, layer or "ARTWORK")
    SetFade(left, color, 0, alpha)
    SetFade(right, color, alpha, 0)
    left:SetSize(width / 2, height)
    right:SetSize(width / 2, height)
    local strip = { left = left, right = right }
    function strip:SetPoint(point, relativeTo, relativePoint, x, y)
        left:ClearAllPoints()
        right:ClearAllPoints()
        left:SetPoint("RIGHT", relativeTo, relativePoint, x, y)
        right:SetPoint("LEFT", relativeTo, relativePoint, x, y)
    end
    function strip:SetHeight(value)
        left:SetHeight(value)
        right:SetHeight(value)
    end
    return strip
end

local function AddCircleMask(parent, texture)
    if not parent.CreateMaskTexture then
        return
    end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

local function CreateCircle(parent, size, color, layer, sublevel)
    local circle = parent:CreateTexture(nil, layer, nil, sublevel)
    circle:SetTexture(Theme.WHITE)
    circle:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    circle:SetSize(size, size)
    AddCircleMask(parent, circle)
    return circle
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

--- Section: a gold heading between two short faded lines, then rows of two
--- aligned columns (created on demand and reused).
local function CreateSection(parent, headingKey)
    local section = { parent = parent, rows = {} }
    section.heading = CreateFont(parent, 13, GOLD)
    Theme:SetLocalizedText(section.heading, headingKey)
    section.leftLine = parent:CreateTexture(nil, "ARTWORK")
    section.rightLine = parent:CreateTexture(nil, "ARTWORK")
    SetFade(section.leftLine, GOLD, 0, 0.7)
    SetFade(section.rightLine, GOLD, 0.7, 0)
    section.leftLine:SetSize(70, 1)
    section.rightLine:SetSize(70, 1)
    section.leftLine:SetPoint("RIGHT", section.heading, "LEFT", -8, 0)
    section.rightLine:SetPoint("LEFT", section.heading, "RIGHT", 8, 0)
    return section
end

local function GetRow(section, index)
    local row = section.rows[index]
    if row then
        return row
    end
    local parent = section.parent
    row = {}
    row.icon = parent:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.right = CreateFont(parent, 13, { 1, 1, 1 })
    row.right:SetJustifyH("RIGHT")
    row.left = CreateFont(parent, 13, { 1, 1, 1 })
    row.left:SetJustifyH("LEFT")
    row.left:SetWordWrap(false)
    section.rows[index] = row
    return row
end

local function HideRow(row)
    row.icon:Hide()
    row.left:Hide()
    row.right:Hide()
end

--- Places a section below `y` and returns the next free y. Without rows the
--- section is hidden and takes no space: the banner never shows filler.
local function LayoutSection(section, rows, y)
    rows = rows or {}
    local shown = #rows > 0
    section.heading:SetShown(shown)
    section.leftLine:SetShown(shown)
    section.rightLine:SetShown(shown)
    for i = #rows + 1, #section.rows do
        HideRow(section.rows[i])
    end
    if not shown then
        return y
    end

    section.heading:ClearAllPoints()
    section.heading:SetPoint("TOP", frame, "TOP", 0, y)
    y = y - section.heading:GetStringHeight() - 6

    -- Rows with icons are taller; when one row has an icon slot, every row
    -- of the section keeps it so the names start in the same column.
    local withIcons = false
    for _, data in ipairs(rows) do
        if data.icon ~= nil then
            withIcons = true
        end
    end
    local height = withIcons and ROW_ICON_HEIGHT or ROW_HEIGHT
    local left = -ROW_WIDTH / 2

    for i, data in ipairs(rows) do
        local row = GetRow(section, i)
        local middle = y - height / 2
        local textLeft = left
        if withIcons then
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", frame, "TOP", left, middle)
            row.icon:SetTexture(data.icon or nil)
            row.icon:SetShown(data.icon and true or false)
            textLeft = left + ICON_SIZE + 6
        else
            row.icon:Hide()
        end

        row.right:SetText(data.right or "")
        row.right:SetShown(data.right ~= nil)
        row.right:ClearAllPoints()
        row.right:SetPoint("RIGHT", frame, "TOP", ROW_WIDTH / 2, middle)

        row.left:SetText(data.left)
        row.left:Show()
        row.left:ClearAllPoints()
        row.left:SetPoint("LEFT", frame, "TOP", textLeft, middle)
        -- Long names are cut before they reach the value.
        local room = ROW_WIDTH / 2 - textLeft - (data.right and row.right:GetStringWidth() + 12 or 0)
        row.left:SetWidth(math.min(row.left:GetStringWidth() + 2, room))

        y = y - height
    end
    return y - 12
end

local function CreatePortrait(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(GLOW_SIZE, GLOW_SIZE)

    -- Soft golden halo: stacked translucent circles, larger ones fainter,
    -- gently pulsing. Built from the circle mask only, so it looks the same
    -- in every client.
    local halo = CreateFrame("Frame", nil, holder)
    halo:SetAllPoints()
    for i, alpha in ipairs(HALO_ALPHAS) do
        local circle = CreateCircle(halo, PORTRAIT_SIZE + RING * 2 + i * HALO_STEP * 2,
            { GOLD[1], GOLD[2], GOLD[3], alpha }, "BACKGROUND", -i)
        circle:SetPoint("CENTER")
        circle:SetBlendMode("ADD")
    end
    local pulse = halo:CreateAnimationGroup()
    local dim = pulse:CreateAnimation("Alpha")
    dim:SetFromAlpha(1)
    dim:SetToAlpha(0.45)
    dim:SetDuration(1.4)
    dim:SetSmoothing("IN_OUT")
    pulse:SetLooping("BOUNCE")
    holder.spin = pulse

    -- Ring and portrait live in their own frame above the halo: the halo is
    -- additive light and must never be drawn over the face.
    local face = CreateFrame("Frame", nil, holder)
    face:SetAllPoints()
    halo:SetFrameLevel(holder:GetFrameLevel())
    face:SetFrameLevel(holder:GetFrameLevel() + 2)

    local ring = CreateCircle(face, PORTRAIT_SIZE + RING * 2, { GOLD[1], GOLD[2], GOLD[3], 1 }, "ARTWORK", 0)
    ring:SetPoint("CENTER")
    local inner = CreateCircle(face, PORTRAIT_SIZE, { 0, 0, 0, 1 }, "ARTWORK", 1)
    inner:SetPoint("CENTER")

    local portrait = face:CreateTexture(nil, "ARTWORK", nil, 2)
    portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    portrait:SetPoint("CENTER")
    AddCircleMask(face, portrait)
    holder.portrait = portrait
    return holder
end

local function BuildAnimations()
    local show = frame:CreateAnimationGroup()
    local fadeIn = show:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(FADE_IN)
    -- The level number lands with a small pop.
    local titleShow = frame.title:CreateAnimationGroup()
    local pop = titleShow:CreateAnimation("Scale")
    if pop.SetScaleFrom then
        pop:SetScaleFrom(1.6, 1.6)
        pop:SetScaleTo(1, 1)
    elseif pop.SetFromScale then
        pop:SetFromScale(1.6, 1.6)
        pop:SetToScale(1, 1)
    end
    pop:SetDuration(FADE_IN)
    pop:SetSmoothing("OUT")
    frame.showAnim, frame.titleAnim = show, titleShow

    local hide = frame:CreateAnimationGroup()
    local fadeOut = hide:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(FADE_OUT)
    if hide.SetToFinalAlpha then
        hide:SetToFinalAlpha(true) -- no flash back to full alpha before hiding
    end
    hide:SetScript("OnFinished", function()
        frame:Hide()
    end)
    frame.hideAnim = hide
end

local function OnUpdate(self, elapsed)
    if self.hideAnim:IsPlaying() or self:IsMouseOver() then
        return
    end
    self.remaining = self.remaining - elapsed
    if self.remaining <= 0 then
        self.hideAnim:Play()
    end
end

local function CreateFrameOnce()
    frame = CreateFrame("Frame", "XPLedgerLevelUpFrame", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetPoint("TOP", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()

    -- Dark band behind everything, fading out to the sides.
    frame.band = CreateFadedStrip(frame, { 0, 0, 0 }, BAND_ALPHA, WIDTH, 10, "BACKGROUND")
    frame.topLine = CreateFadedStrip(frame, GOLD, 0.9, WIDTH - 40, 2, "BORDER")
    frame.bottomLine = CreateFadedStrip(frame, GOLD, 0.9, WIDTH - 40, 2, "BORDER")

    frame.title = CreateFont(frame, 34, GOLD)
    frame.portrait = CreatePortrait(frame)
    frame.name = CreateFont(frame, 15)

    frame.stats = CreateSection(frame, "LEVELUP_STATS")
    frame.spells = CreateSection(frame, "LEVELUP_SPELLS")
    frame.zones = CreateSection(frame, "LEVELUP_ZONES")

    frame.hint = CreateFont(frame, 10, { 0.6, 0.6, 0.6 })
    Theme:SetLocalizedText(frame.hint, "LEVELUP_HINT")

    BuildAnimations()
    frame:SetScript("OnMouseUp", function(self)
        self.hideAnim:Stop()
        self:Hide()
    end)
    frame:SetScript("OnUpdate", OnUpdate)
    frame:SetScript("OnHide", function(self)
        self.portrait.spin:Stop()
    end)
end

--- Lays out every element from the top down and sizes the frame to fit.
local function Layout(level, result, demo)
    local y = -18
    frame.topLine:SetPoint("CENTER", frame, "TOP", 0, -2)

    frame.title:SetText(L["LEVELUP_TITLE"]:format(level))
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOP", frame, "TOP", 0, y)
    y = y - frame.title:GetStringHeight() - 14 -- room for the halo

    local parts = ns.settings.levelUpParts
    frame.portrait:SetShown(parts.portrait)
    frame.name:SetShown(parts.portrait)
    if parts.portrait then
        -- The halo is larger than the portrait: center the portrait, let the
        -- halo spill over the title and the name.
        SetPortraitTexture(frame.portrait.portrait, "player")
        frame.portrait:ClearAllPoints()
        frame.portrait:SetPoint("CENTER", frame, "TOP", 0, y - PORTRAIT_SIZE / 2 - RING)
        y = y - PORTRAIT_SIZE - RING * 2 - 6

        local _, classFile = UnitClass("player")
        local classColor = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
        frame.name:SetText(UnitName("player"))
        if classColor then
            frame.name:SetTextColor(classColor.r, classColor.g, classColor.b)
        end
        frame.name:ClearAllPoints()
        frame.name:SetPoint("TOP", frame, "TOP", 0, y)
        y = y - frame.name:GetStringHeight()
    end
    y = y - 18

    -- A section turned off in the options is skipped like an empty one (its
    -- data is not even gathered).
    local statRows = parts.stats and StatRows(result) or nil
    local spellRows, zoneRows
    if parts.spells then
        spellRows = SpellRows(demo and demo.spells or (ns.Spells and ns.Spells:GetNewForLevel(level)) or {})
    end
    if parts.zones then
        zoneRows = ZoneRows(demo and demo.zones or (ns.Zones and ns.Zones:GetRecommended(level)) or {})
    end
    y = LayoutSection(frame.stats, statRows, y)
    y = LayoutSection(frame.spells, spellRows, y)
    y = LayoutSection(frame.zones, zoneRows, y)

    frame.hint:ClearAllPoints()
    frame.hint:SetPoint("TOP", frame, "TOP", 0, y + 4)
    y = y - frame.hint:GetStringHeight() - 8

    local height = -y
    frame:SetHeight(height)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "CENTER", 0, OFFSET_Y + height / 2)
    frame.band:SetHeight(height)
    frame.band:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.bottomLine:SetPoint("CENTER", frame, "BOTTOM", 0, 2)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Shows the summary for a level. `result` is an XPL_LEVEL_STATS payload and
--- may be nil (preview without a real level up).
function LevelUp:Show(level, result, demo)
    if not frame then
        CreateFrameOnce()
    end
    frame:SetScale(ns.settings.levelUpScale or 1)
    Layout(level, result or {}, demo)

    frame.remaining = SHOW_SECONDS
    frame.hideAnim:Stop()
    frame:SetAlpha(1)
    frame:Show()
    frame.showAnim:Play()
    frame.titleAnim:Play()
    if ns.settings.levelUpParts.portrait then
        frame.portrait.spin:Play()
    end
end

--- Shows the summary for the current level (last real result if it matches).
function LevelUp:Preview()
    local level = UnitLevel("player")
    local last = ns.LevelUpStats and ns.LevelUpStats:GetLast()
    self:Show(level, last and last.level == level and last or nil)
end

--------------------------------------------------------------------------------
-- Demo (/xpl levelup demo): every section filled with sample data
--------------------------------------------------------------------------------

-- A few real abilities per class. Only the ids are stored: names, ranks and
-- icons come from the client, in its own language.
local DEMO_SPELLS = {
    WARRIOR = { 6343, 772, 284, 2687 },
    PALADIN = { 635, 20271, 19740, 498 },
    HUNTER = { 1978, 3044, 1130, 13165 },
    ROGUE = { 1752, 2098, 1784, 53 },
    PRIEST = { 2061, 589, 17, 2050 },
    SHAMAN = { 403, 8042, 331, 324 },
    MAGE = { 116, 2136, 1459, 122 },
    WARLOCK = { 686, 172, 980, 688 },
    DRUID = { 5176, 8921, 774, 5487 },
}
local DEMO_COSTS = { 100, 350, 1200, 0 }
local DEMO_ZONE_LEVEL = 20 -- used when the real level has no zones (level cap)

local function DemoSpells()
    local _, classFile = UnitClass("player")
    local list = {}
    for i, spellID in ipairs(DEMO_SPELLS[classFile] or DEMO_SPELLS.MAGE) do
        local name, icon
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            name, icon = info and info.name, info and info.iconID
        elseif GetSpellInfo then
            local _, _, spellIcon = GetSpellInfo(spellID)
            name, icon = GetSpellInfo(spellID), spellIcon
        end
        local getSubtext = (C_Spell and C_Spell.GetSpellSubtext) or _G.GetSpellSubtext
        local rank = getSubtext and getSubtext(spellID)
        if name then
            list[#list + 1] = { name = name, rank = rank ~= "" and rank or nil, icon = icon, cost = DEMO_COSTS[i] }
        end
    end
    return list
end

local function DemoStats(level)
    local _, powerToken = UnitPowerType("player")
    local hasPower = (ns.SafeNumber(UnitPowerMax("player")) or 0) > 0
    return {
        level = level,
        health = 24,
        power = hasPower and 18 or nil,
        powerToken = ns.SafeString(powerToken),
        talents = 1,
        stats = { 1, nil, 2, 1, nil },
    }
end

--- Shows the summary with sample stats, sample abilities of the player's
--- class and the real zones for the level, to see every part of it.
function LevelUp:Demo()
    local level = UnitLevel("player")
    local zones = ns.Zones and ns.Zones:GetRecommended(level) or {}
    if #zones == 0 and ns.Zones then
        zones = ns.Zones:GetRecommended(DEMO_ZONE_LEVEL)
    end
    self:Show(level, DemoStats(level), { spells = DemoSpells(), zones = zones })
end

--- True when the summary should appear on level up in this client.
function LevelUp:IsActive()
    return ns.Compat.flavor == "forever" and ns.settings.levelUpSplash
end

function LevelUp:OnLogin()
    ns:RegisterMessage("XPL_LEVEL_STATS", function(_, result)
        if self:IsActive() and result and result.level then
            self:Show(result.level, result)
        end
    end)
end
