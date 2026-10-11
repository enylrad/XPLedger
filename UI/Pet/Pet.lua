--[[----------------------------------------------------------------------------
    XPLedger - Pet
    Optional pixel art murloc that keeps the player company, reacts to what
    happens in game and can show the experience bar.

    States (highest priority first):
      dead / ghost  the player is dead (a ghost after releasing the spirit)
      reactions     a few seconds after an event, see REACTIONS: achievement
                    (party), new growth stage (evolve), back to life (revive),
                    level up (happy), end of a fight (victory or relief),
                    quest turned in, fish caught, emotes, jumps, idle fidgets
      panic / fight in combat (panic below LOW_HEALTH, where health is readable)
      fish          fishing
      swim          swimming or underwater
      sleep         away from keyboard
      rest          in an inn or a city
      excited       the level bar is almost full
      idle

    Growth stages follow the player level relative to the level cap, so they
    work on every flavor:
      1 hatchling  below a third of the cap
      2 grown      up to the cap
      3 veteran    at the cap (iron helmet and gilded spear)

    Settings (settings.pet): enabled, asked, locked, scale, position, bar,
    textMode, badge, clickAction ("poke" or "panel"), summaryTooltip,
    showAtMaxLevel (unlike the shortcut, the pet stays at the level cap).

      Left-click   say hello, or open the main window (clickAction)
      Right-click  lock / unlock the position
      Drag         move (when unlocked, or in Edit Mode on Retail)
------------------------------------------------------------------------------]]

local _, ns = ...

local Pet = ns:NewModule("Pet")
local Theme = ns.Theme
local Compat = ns.Compat
local PetSprite = ns.PetSprite

local DEFAULT_POSITION = { "CENTER", "CENTER", 0, -150 }

local POLL_INTERVAL = 0.25    -- seconds between checks of the player's situation
local INTRO_DELAY = 3         -- seconds after login before asking about the pet
local DEMO_STEP = 2           -- seconds per state in /xpl pet demo
local OUTCOME_DELAY = 1       -- wait for the kill experience after a fight
local LOW_HEALTH = 0.3        -- panic below this health fraction
local EXCITED_PROGRESS = 0.9  -- nervous when the level bar is this full
local IDLE_DELAY = 20         -- seconds idle before the first fidget
local IDLE_MIN, IDLE_MAX = 15, 30

-- Temporary reactions. A reaction does not interrupt another one with a
-- higher priority. `effect` overrides the particles of the state, `lift` is
-- the height of a jump in sprite pixels.
local REACTIONS = {
    party = { state = "party", duration = 6, priority = 5 },
    evolve = { state = "evolve", duration = 4, priority = 5 },
    revive = { state = "revive", duration = 3, priority = 4 },
    happy = { state = "happy", duration = 3.5, priority = 3 },
    victory = { state = "victory", duration = 2.4, priority = 3 },
    relief = { state = "relief", duration = 2.7, priority = 3 },
    quest = { state = "happy", duration = 1.5, priority = 2, effect = "quest" },
    catch = { state = "eat", duration = 3, priority = 2 },
    dance = { state = "dance", duration = 6, priority = 2 },
    wave = { state = "wave", duration = 2.5, priority = 2 },
    cheer = { state = "happy", duration = 2.5, priority = 2 },
    roar = { state = "victory", duration = 2, priority = 2 },
    nap = { state = "sleep", duration = 6, priority = 2 },
    love = { state = "happy", duration = 2.5, priority = 2, effect = "love" },
    yawn = { state = "yawn", duration = 2.2, priority = 2 },
    eat = { state = "eat", duration = 3, priority = 2 },
    poke = { state = "happy", duration = 1.2, priority = 1 },
    jump = { state = "jump", duration = 0.6, priority = 1, lift = 7 },
    -- Fidgets while idle.
    idleYawn = { state = "yawn", duration = 2.2, priority = 0 },
    idleJuggle = { state = "juggle", duration = 4, priority = 0 },
    idleScratch = { state = "scratch", duration = 2.4, priority = 0 },
    idleEat = { state = "eat", duration = 3, priority = 0 },
}

local IDLE_FIDGETS = { "idleYawn", "idleJuggle", "idleScratch", "idleEat" }

-- Emote tokens (the same in every language) and the reaction they trigger.
local EMOTES = {
    DANCE = "dance",
    WAVE = "wave", HELLO = "wave", BYE = "wave", GREET = "wave",
    CHEER = "cheer", APPLAUD = "cheer", CLAP = "cheer",
    ROAR = "roar", FLEX = "roar", CHARGE = "roar", VICTORY = "roar",
    SLEEP = "nap",
    KISS = "love", LOVE = "love", HUG = "love",
    EAT = "eat",
    YAWN = "yawn", TIRED = "yawn",
}

-- Fishing spells of every expansion (the localized name is also checked).
local FISHING_SPELLS = {
    [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true, [51294] = true,
    [88868] = true, [110410] = true, [131474] = true, [131490] = true, [158743] = true, [271990] = true,
}

-- Every state, in the order of the demo and of the options preview.
Pet.STATES = {
    "idle", "happy", "party", "fight", "victory", "relief", "panic", "dead", "ghost", "revive",
    "swim", "fish", "eat", "sleep", "rest", "dance", "wave", "yawn", "juggle", "scratch", "excited", "jump",
}

Pet.GHOST_TINT = { 0.6, 0.85, 1, 0.55 }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Settings()
    return ns.settings.pet
end

function Pet:IsLocked()
    return Settings().locked
end

local function GetLevel()
    local _, _, level = ns.Tracker:GetSnapshot()
    return level or ns.SafeNumber(UnitLevel("player")) or 1
end

local function Random(low, high)
    return low + math.random() * (high - low)
end

local function IsFishingSpell(spellID)
    spellID = ns.SafeNumber(spellID)
    if not spellID then
        return false
    end
    if FISHING_SPELLS[spellID] then
        return true
    end
    local name = Compat.GetSpellName(spellID)
    local fishing = Compat.GetSpellName(131474) or Compat.GetSpellName(7620)
    return name ~= nil and name == fishing
end

--- Growth stage for a level (1 hatchling, 2 grown, 3 veteran).
function Pet:GetStage(level)
    local maxLevel = Compat.GetMaxLevel()
    if level >= maxLevel then
        return 3
    elseif level < math.max(2, math.floor(maxLevel / 3)) then
        return 1
    end
    return 2
end

--- Size of a sprite pixel in screen pixels.
function Pet:GetPixel()
    return Settings().scale
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

function Pet:Build()
    local frame = CreateFrame("Button", "XPLedgerPet", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    -- The position is stored in our saved variables, not in the layout cache.
    if frame.SetDontSavePosition then
        frame:SetDontSavePosition(true)
    end
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    self.sprite = PetSprite.Create(frame)
    self.effects = ns.PetEffects.Create(frame, function() return self:GetPixel() end)

    -- Level badge in the bottom right corner.
    local badge = CreateFrame("Frame", nil, frame)
    badge:SetPoint("BOTTOMRIGHT", 0, 2)
    badge:SetSize(20, 13)
    badge:SetFrameLevel(frame:GetFrameLevel() + 2)
    local badgeBackground = Theme:CreateTexture(badge, { 0, 0, 0, 0.6 }, "BACKGROUND")
    badgeBackground:SetAllPoints()
    badge.text = Theme:CreateText(badge, "small", "CENTER")
    badge.text:SetPoint("CENTER", 0, 0)
    badge.text:SetTextColor(1, 1, 1)
    frame.badge = badge

    -- Experience bar and text under the murloc.
    frame.xpBar = Theme:CreateXPBar(frame)
    frame.xpBar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 2, -1)
    frame.xpBar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -2, -1)
    frame.xpText = Theme:CreateText(frame, "small", "CENTER")
    frame.xpText:SetTextColor(1, 1, 1)

    -- Speech bubble above the head.
    local speech = CreateFrame("Frame", nil, frame)
    speech:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    speech:SetFrameLevel(frame:GetFrameLevel() + 3)
    if Theme.ApplyBackdrop(speech, { bgFile = Theme.WHITE, edgeFile = Theme.WHITE, edgeSize = 1 }) then
        speech:SetBackdropColor(0.05, 0.07, 0.06, 0.88)
        speech:SetBackdropBorderColor(0.37, 0.68, 0.31, 1)
    end
    speech.text = Theme:CreateText(speech, "normal", "CENTER")
    speech.text:SetPoint("CENTER")
    speech:Hide()
    frame.speech = speech

    -- Edit Mode highlight.
    local selection = CreateFrame("Frame", nil, frame)
    selection:SetAllPoints()
    selection:SetFrameLevel(frame:GetFrameLevel() + 4)
    local selectionFill = Theme:CreateTexture(selection, { 0.25, 0.6, 1, 0.3 }, "OVERLAY")
    selectionFill:SetAllPoints()
    selection.label = Theme:CreateText(selection, "small", "CENTER")
    selection.label:SetPoint("BOTTOM", selection, "TOP", 0, 2)
    selection.label:SetTextColor(0.6, 0.85, 1)
    selection.label:SetText(ns.title)
    selection:Hide()
    frame.selection = selection

    -- Short fade used as feedback when the lock state changes.
    local flash = frame:CreateAnimationGroup()
    local fade = flash:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.12)
    fade:SetOrder(1)
    local back = flash:CreateAnimation("Alpha")
    back:SetFromAlpha(0.35)
    back:SetToAlpha(1)
    back:SetDuration(0.18)
    back:SetOrder(2)
    frame.flash = flash

    self.frame = frame
    self:SetupScripts(frame)
end

function Pet:SetupScripts(frame)
    frame:SetScript("OnDragStart", function(selfFrame)
        if self.editing or not self:IsLocked() then
            selfFrame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        selfFrame.dragStoppedAt = GetTime()
        local point, _, relativePoint, x, y = selfFrame:GetPoint(1)
        Settings().position = { point, relativePoint, ns.Round(x, 1), ns.Round(y, 1) }
    end)
    frame:SetScript("OnClick", function(selfFrame, button)
        -- Ignore the click generated when a drag ends over the frame.
        if selfFrame.dragStoppedAt and GetTime() - selfFrame.dragStoppedAt < 0.2 then
            return
        end
        if button == "RightButton" then
            self:SetLocked(not self:IsLocked())
        elseif Settings().clickAction == "panel" and ns.MainPanel then
            ns.MainPanel:Toggle()
        else
            self:Poke()
        end
    end)
    frame:SetScript("OnEnter", function(selfFrame)
        GameTooltip:SetOwner(selfFrame, "ANCHOR_NONE")
        GameTooltip:SetPoint(self:GetTooltipAnchor())
        self:FillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(selfFrame)
        if GameTooltip:IsOwned(selfFrame) then
            GameTooltip:Hide()
        end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)
end

--- Places the tooltip below or above the pet depending on screen space.
function Pet:GetTooltipAnchor()
    local frame = self.frame
    local _, centerY = frame:GetCenter()
    if centerY and centerY > UIParent:GetHeight() / 2 then
        return "TOP", frame, "BOTTOM", 0, -4
    end
    return "BOTTOM", frame, "TOP", 0, 4
end

function Pet:FillTooltip(tooltip)
    local L = ns.L
    local accent, muted = Theme.colors.accent, Theme.colors.muted
    tooltip:AddLine(L["PET_NAME"], accent[1], accent[2], accent[3])
    tooltip:AddLine(L["PET_STAGE_" .. self.sprite.stage] .. "  ·  " .. L["TOOLTIP_LEVEL"]:format(self.level), 1, 1, 1)
    tooltip:AddLine(L["PET_STATE_" .. (self.state or "idle")], 0.6, 0.85, 1)
    if Settings().summaryTooltip then
        tooltip:AddLine(" ")
        ns.SummaryTooltip:Fill(tooltip, false)
    end
    tooltip:AddLine(" ")
    local clickHint = Settings().clickAction == "panel" and "TOOLTIP_HINT_CLICK" or "PET_HINT_CLICK"
    tooltip:AddLine(L[clickHint], muted[1], muted[2], muted[3])
    tooltip:AddLine(self:IsLocked() and L["TOOLTIP_HINT_UNLOCK"] or L["TOOLTIP_HINT_LOCK"], muted[1], muted[2], muted[3])
    if not self:IsLocked() then
        tooltip:AddLine(L["TOOLTIP_HINT_DRAG"], muted[1], muted[2], muted[3])
    end
end

function Pet:RefreshTooltip()
    if self.frame and GameTooltip:IsOwned(self.frame) then
        GameTooltip:ClearLines()
        self:FillTooltip(GameTooltip)
        GameTooltip:Show()
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

--- Picks the state to show. Returns the state and the active reaction, if
--- any. `ignoreReactions` gives the state underneath the reactions.
function Pet:ResolveState(ignoreReactions)
    if self.demo then
        return self.demo.state
    end
    if self.dead then
        return "dead"
    elseif self.ghost then
        return "ghost"
    end
    if not ignoreReactions then
        local reaction = self.reaction
        if reaction then
            if GetTime() < reaction.untilTime then
                return reaction.state, reaction
            end
            self.reaction = nil
        end
    end
    if self.inCombat or self.pendingOutcome then
        return self.lowHealth and "panic" or "fight"
    elseif self.fishing then
        return "fish"
    elseif self.underwater then
        return "swim"
    elseif self.afk then
        return "sleep"
    elseif self.resting then
        return "rest"
    elseif self.excited then
        return "excited"
    end
    return "idle"
end

--- Applies the resolved state. `force` restarts the animation and replays
--- the entry effects even when the state did not change.
function Pet:UpdateState(force)
    local state, reaction = self:ResolveState()
    local effect = reaction and reaction.effect or state
    if state == self.state and effect == self.effect and not force then
        return
    end
    self.state, self.effect = state, effect
    self.sprite:SetAnimation(state, force)
    self.sprite.glow:SetAlpha(0)
    if state == "ghost" then
        self.sprite:SetTint(unpack(Pet.GHOST_TINT))
    else
        self.sprite:SetTint()
    end
    self.effects:SetEmitter(effect)
end

--- Starts a temporary reaction (see REACTIONS). Returns true when it plays.
function Pet:React(name)
    local definition = REACTIONS[name]
    if (self.dead or self.ghost) and name ~= "revive" then
        return false
    end
    local now = GetTime()
    local current = self.reaction
    if current and now < current.untilTime and definition.priority < current.priority then
        return false
    end
    self.reaction = {
        name = name,
        state = definition.state,
        effect = definition.effect,
        priority = definition.priority,
        lift = definition.lift,
        startedAt = now,
        untilTime = now + definition.duration,
    }
    self:UpdateState(true)
    return true
end

--- Shows a short text in the speech bubble.
function Pet:Say(text, duration)
    local speech = self.frame.speech
    speech.text:SetText(text)
    speech:SetSize(speech.text:GetStringWidth() + 14, speech.text:GetStringHeight() + 10)
    speech.hideAt = GetTime() + (duration or 2.5)
    speech:Show()
end

function Pet:Poke()
    self:React("poke")
    self:Say(ns.L["PET_SPEECH_" .. math.random(1, 4)], 1.8)
end

--------------------------------------------------------------------------------
-- Player situation
--------------------------------------------------------------------------------

--- Follows death, release and resurrection.
function Pet:UpdateLife(silent)
    local dead, ghost = Compat.IsDead(), Compat.IsGhost()
    if dead == self.dead and ghost == self.ghost then
        return
    end
    local wasDown = self.dead or self.ghost
    self.dead, self.ghost = dead, ghost
    if (dead or ghost) and not wasDown then
        self.reaction, self.pendingOutcome, self.inCombat = nil, nil, false
        if not silent then
            self:Say(ns.L["PET_SPEECH_DEAD"], 2.5)
        end
    elseif wasDown and not dead and not ghost and not silent then
        self:React("revive")
        self:Say(ns.L["PET_SPEECH_REVIVE"], 3)
    end
    self:UpdateState()
end

function Pet:OnCombatStart()
    self.inCombat = true
    self.combatKills = 0
    self.pendingOutcome = nil
    self:UpdateState()
end

--- Combat is over: it is a victory if something died, a relief otherwise.
--- The kill experience arrives a moment later, so the verdict waits a bit.
function Pet:OnCombatEnd()
    self.inCombat, self.lowHealth = false, false
    if not (self.dead or self.ghost or Compat.IsDead()) then
        self.pendingOutcome = {
            at = GetTime() + OUTCOME_DELAY,
            won = (self.combatKills or 0) > 0 or Compat.IsTargetDead(),
        }
    end
    self:UpdateState()
end

function Pet:ResolveOutcome(won)
    local pending = self.pendingOutcome
    if not pending then
        return
    end
    self.pendingOutcome = nil
    if not self:React((won or pending.won) and "victory" or "relief") then
        self:UpdateState()
    end
end

function Pet:OnExperienceGained(gain)
    if gain.source == "mob" then
        if self.inCombat then
            self.combatKills = (self.combatKills or 0) + 1
        elseif self.pendingOutcome then
            self:ResolveOutcome(true)
        end
    elseif gain.source == "quest" then
        self:React("quest")
    end
    self:UpdateExperience()
end

function Pet:OnJump()
    if not self.frame:IsShown() or self.underwater or (IsFlying and IsFlying()) then
        return
    end
    local current = self.reaction
    if current and current.name == "jump" and GetTime() < current.untilTime then
        return
    end
    self:React("jump")
end

function Pet:OnEmote(token)
    token = ns.SafeString(token)
    local reaction = token and EMOTES[token:upper()]
    local now = GetTime()
    -- DoEmote and C_ChatInfo.PerformEmote may both fire for one emote.
    if not reaction or (self.lastEmoteAt and now - self.lastEmoteAt < 0.3) then
        return
    end
    self.lastEmoteAt = now
    self:React(reaction)
end

--- Plays a fidget now and then while nothing happens.
function Pet:UpdateIdleFidgets()
    local now = GetTime()
    if self.demo or self:ResolveState(true) ~= "idle" then
        self.idleSince = nil
        return
    end
    if not self.idleSince then
        self.idleSince = now
        self.nextFidget = now + IDLE_DELAY
    end
    local busy = self.reaction and now < self.reaction.untilTime
    if now >= self.nextFidget and not busy then
        self:React(IDLE_FIDGETS[math.random(1, #IDLE_FIDGETS)])
        self.nextFidget = now + Random(IDLE_MIN, IDLE_MAX)
    end
end

function Pet:Poll()
    self.underwater = Compat.IsUnderwater()
    self:UpdateLife()
    if self.inCombat then
        local health = Compat.GetHealthPercent()
        self.lowHealth = health ~= nil and health < LOW_HEALTH
    end
    if self.pendingOutcome and GetTime() >= self.pendingOutcome.at then
        self:ResolveOutcome(false)
    end
    self:UpdateIdleFidgets()
    self:UpdateState()
end

--------------------------------------------------------------------------------
-- Update loop
--------------------------------------------------------------------------------

function Pet:OnUpdate(elapsed)
    self.sprite:Update(elapsed)
    self.effects:Update(elapsed)
    local now = GetTime()

    if self.state == "evolve" then
        self.sprite.glow:SetAlpha(0.7 * math.abs(math.sin(now * 5)))
    end

    -- Vertical offset of the drawing: jump arc or ghostly floating.
    local offset = 0
    local reaction = self.reaction
    if reaction and reaction.lift and now < reaction.untilTime and self.state == reaction.state then
        local progress = (now - reaction.startedAt) / (reaction.untilTime - reaction.startedAt)
        offset = math.sin(progress * math.pi) * reaction.lift
    elseif self.state == "ghost" then
        offset = 1.5 + math.sin(now * 2.2) * 1.5
    end
    offset = ns.Round(offset * self:GetPixel())
    if offset ~= self.offset then
        self.offset = offset
        self.sprite:SetOffset(0, offset)
    end

    local speech = self.frame.speech
    if speech:IsShown() and now >= speech.hideAt then
        speech:Hide()
    end

    self.pollElapsed = (self.pollElapsed or 0) + elapsed
    if self.pollElapsed >= POLL_INTERVAL then
        self.pollElapsed = 0
        self:Poll()
    end
end

--------------------------------------------------------------------------------
-- Experience display
--------------------------------------------------------------------------------

--- Updates the bar, the text and the "almost there" nerves. `silent` skips
--- the speech bubble (at login).
function Pet:UpdateExperience(silent)
    local frame = self.frame
    if not frame then
        return
    end
    local settings = Settings()
    local xp, maxXP, level = ns.Tracker:GetSnapshot()
    local capped = Compat.IsExperienceBlocked()
    local progress = (xp and maxXP and maxXP > 0) and xp / maxXP or 0

    local excited = not capped and progress >= EXCITED_PROGRESS
    if excited and level and self.excitedLevel ~= level then
        self.excitedLevel = level
        if not silent and frame:IsShown() then
            self:Say(ns.L["PET_SPEECH_EXCITED"], 3)
        end
    end
    self.excited = excited

    local showBar = settings.bar and not capped
    local showText = settings.textMode ~= "none" and not capped
    frame.xpBar:SetShown(showBar)
    frame.xpText:SetShown(showText)
    if not frame:IsShown() or not (showBar or showText) then
        return
    end
    local estimate = ns.Tracker:GetEstimate()
    if showBar then
        frame.xpBar:SetProgress(ns.Launcher.GetBarValues(estimate))
    end
    if showText then
        frame.xpText:ClearAllPoints()
        frame.xpText:SetPoint("TOP", showBar and frame.xpBar or frame, "BOTTOM", 0, -2)
        frame.xpText:SetText((ns.Launcher.BuildTexts(estimate, settings.textMode)))
    end
end

--------------------------------------------------------------------------------
-- Settings and visibility
--------------------------------------------------------------------------------

function Pet:ApplyPosition()
    local position = Settings().position or DEFAULT_POSITION
    self.frame:ClearAllPoints()
    self.frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
end

function Pet:UpdateVisibility()
    local settings = Settings()
    local wanted = settings.enabled and (settings.showAtMaxLevel or not Compat.IsAtMaxLevel())
    local shown = wanted or self.demo ~= nil
    self.frame:SetShown(shown)
    self.frame.selection:SetShown(shown and self.editing == true)
    if not shown then
        self.effects:Clear()
        self.frame.speech:Hide()
    end
end

function Pet:Refresh()
    local stage = self.demo and self.demo.stage or self.stage
    self.sprite:SetStage(stage)
    local badge = self.frame.badge
    badge:SetShown(Settings().badge)
    badge.text:SetText(self.level)
    badge:SetWidth(math.max(13, badge.text:GetStringWidth() + 6))
    self:UpdateState()
end

--- Follows a new player level. The level messages arrive before the tracker
--- snapshot is updated, so the level is passed in instead of read back.
function Pet:SetLevel(level)
    self.level = level
    self.stage = self:GetStage(level)
    if self.frame then
        self:UpdateVisibility()
        self:Refresh()
    end
end

function Pet:ApplySettings()
    if not self.frame then
        return
    end
    local size = PetSprite.SIZE * Settings().scale
    self.frame:SetSize(size, size)
    self.offset = nil
    self:ApplyPosition()
    self:UpdateVisibility()
    self:Refresh()
    self:UpdateExperience(true)
end

--- Shows or hides the pet permanently (saved setting).
function Pet:SetEnabled(enabled)
    Settings().enabled = enabled and true or false
    Settings().asked = true
    self:UpdateVisibility()
    if enabled then
        self:React("happy")
        self:Say(ns.L["PET_SPEECH_HELLO"], 3)
    else
        ns:Print(ns.L["PET_HIDDEN"])
    end
    ns:SendMessage("XPL_SETTINGS_CHANGED")
end

--- Locks or unlocks the position, with visual and chat feedback.
function Pet:SetLocked(locked)
    Settings().locked = locked and true or false
    if self.frame then
        self.frame.flash:Play()
        self:RefreshTooltip()
    end
    ns:Print(locked and ns.L["PET_LOCKED"] or ns.L["PET_UNLOCKED"])
    ns:SendMessage("XPL_SETTINGS_CHANGED")
end

function Pet:ResetPosition()
    Settings().position = nil
    self:ApplyPosition()
    ns:Print(ns.L["PET_POSITION_RESET"])
end

--------------------------------------------------------------------------------
-- Edit Mode (Retail): the pet can be moved while the layout is being edited.
--------------------------------------------------------------------------------

function Pet:SetEditing(editing)
    self.editing = editing
    self:UpdateVisibility()
end

function Pet:SetupEditMode()
    if not (EventRegistry and EventRegistry.RegisterCallback and EditModeManagerFrame) then
        return
    end
    EventRegistry:RegisterCallback("EditMode.Enter", function() self:SetEditing(true) end, self)
    EventRegistry:RegisterCallback("EditMode.Exit", function() self:SetEditing(false) end, self)
end

--------------------------------------------------------------------------------
-- First run question
--------------------------------------------------------------------------------

StaticPopupDialogs["XPLEDGER_PET_INTRO"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function() Pet:SetEnabled(true) end,
    OnCancel = function()
        Settings().asked = true
        ns:Print(ns.L["PET_INTRO_DECLINED"])
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Pet:AskIfWanted()
    if Settings().asked then
        return
    end
    C_Timer.After(INTRO_DELAY, function()
        if not Settings().asked then
            StaticPopup_Show("XPLEDGER_PET_INTRO", ns.L["PET_INTRO"])
        end
    end)
end

--------------------------------------------------------------------------------
-- Demo: every state of a stage, for testing and showing off
--------------------------------------------------------------------------------

function Pet:Demo(stage)
    if self.demoTicker then
        self.demoTicker:Cancel()
    end
    stage = tonumber(stage)
    if not stage or stage < 1 or stage > 3 then
        stage = self.stage
    end
    local L = ns.L
    local index = 0
    local function Next()
        index = index + 1
        local state = Pet.STATES[index]
        self.demo = state and { stage = stage, state = state } or nil
        if state then
            self:Say(L["PET_STAGE_" .. stage] .. ": " .. L["PET_STATE_" .. state], DEMO_STEP)
        else
            self.demoTicker = nil
        end
        self:UpdateVisibility()
        self:Refresh()
    end
    Next()
    self.demoTicker = C_Timer.NewTicker(DEMO_STEP, Next, #Pet.STATES)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Pet:OnLevelUp(newLevel)
    local L = ns.L
    local previousStage = self.stage
    self:SetLevel(newLevel)
    if self.stage ~= previousStage then
        self:React("evolve")
        self:Say(L["PET_SPEECH_EVOLVE"], 3.5)
    else
        self:React("happy")
        self:Say(L["PET_SPEECH_LEVEL"]:format(newLevel), 3)
    end
end

function Pet:RegisterEvents()
    ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() self:OnCombatStart() end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:OnCombatEnd() end)
    for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        ns:RegisterEvent(event, function() self:UpdateLife() end)
    end
    ns:RegisterEvent("PLAYER_FLAGS_CHANGED", function(_, unit)
        if unit == "player" then
            self.afk = Compat.IsAFK()
            self:UpdateState()
        end
    end)
    ns:RegisterEvent("PLAYER_UPDATE_RESTING", function()
        self.resting = Compat.IsResting()
        self:UpdateState()
    end)
    ns:RegisterEvent("ACHIEVEMENT_EARNED", function()
        if self:React("party") then
            self:Say(ns.L["PET_SPEECH_ACHIEVEMENT"], 3.5)
        end
    end)
    ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, _, spellID)
        if unit == "player" and IsFishingSpell(spellID) then
            self.fishing = true
            self:UpdateState()
        end
    end)
    ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit)
        if unit == "player" and self.fishing then
            self.fishing = false
            self:UpdateState()
        end
    end)
    ns:RegisterEvent("LOOT_OPENED", function()
        if IsFishingLoot and IsFishingLoot() and self:React("catch") then
            self:Say(ns.L["PET_SPEECH_CATCH"], 2.5)
        end
    end)

    -- Jumps and emotes have no events: follow the functions that perform them.
    if JumpOrAscendStart then
        hooksecurefunc("JumpOrAscendStart", function() self:OnJump() end)
    end
    if C_ChatInfo and C_ChatInfo.PerformEmote then
        hooksecurefunc(C_ChatInfo, "PerformEmote", function(token) self:OnEmote(token) end)
    end
    if DoEmote then
        hooksecurefunc("DoEmote", function(token) self:OnEmote(token) end)
    end

    ns:RegisterMessage("XPL_LEVEL_UP", function(_, _, newLevel) self:OnLevelUp(newLevel) end)
    -- Boosts and level squishes: follow the new level without celebrating.
    ns:RegisterMessage("XPL_LEVEL_CHANGED", function(_, _, newLevel) self:SetLevel(newLevel) end)
    ns:RegisterMessage("XPL_XP_GAINED", function(_, gain) self:OnExperienceGained(gain) end)
    ns:RegisterMessage("XPL_STATE_CHANGED", function() self:UpdateExperience() end)
    ns:RegisterMessage("XPL_LOCALE_CHANGED", function() self:UpdateExperience(true) end)
    ns:RegisterMessage("XPL_TICK", function()
        if self.frame:IsShown() then
            self:UpdateExperience()
            if Settings().summaryTooltip then
                self:RefreshTooltip()
            end
        end
    end)
    ns:RegisterMessage("XPL_SETTINGS_CHANGED", function() self:ApplySettings() end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Pet:OnLogin()
    self:SetLevel(GetLevel())
    self.inCombat = Compat.InCombat()
    self.underwater = Compat.IsUnderwater()
    self.afk = Compat.IsAFK()
    self.resting = Compat.IsResting()
    self:Build()
    self:UpdateLife(true)
    self:ApplySettings()
    self:SetupEditMode()
    self:RegisterEvents()
    self:AskIfWanted()
end
