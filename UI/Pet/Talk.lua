--[[----------------------------------------------------------------------------
    XPLedger - Pet talk
    What the companion says, as text in its speech bubble (there is no audio).
    Every species has its own way of talking, registered by the
    Locales\PetPhrases_<locale>.lua files in ns.PetPhrases[locale][species]:

      events  one line (or a list to pick from) per event: hello, level (%d),
              achievement, dead, revive, catch, excited, poke, and annoyed:
              the lines said IN ORDER when the player keeps clicking the pet,
              from mildly bothered to fed up (it starts over at the end).
              A species with a rage form (PetSprite.RAGE_FORMS) turns into
              it instead of starting over, roaring a `transform` line, and
              says a `calm` line once it is back to normal
      cheer   cheering lines grouped by what the player is doing (CONTEXTS)

    The murloc is an optimist that speaks mostly in murloc; Nihil, the Void
    hatchling, is sweet and cheerfully gloomy (the Void will swallow it all,
    but first: your next level).

    Cheers are optional (settings.pet.cheer): every cheerSeconds seconds, a
    bit earlier or later, the pet says a line that fits the moment.

    The pet has its own language setting (settings.pet.locale): "auto"
    follows the addon's language, a locale code forces that one.

    A species may also have an unfiltered voice, <species>_harsh (Nihil has
    one: void_harsh), with the same keys and harsher lines. It is used when
    settings.pet.harsh is on; a key it lacks falls back to the usual voice.

    Adding a new pet
    ----------------
    Every pet has a personality, and everything it says must be written for
    it: the murloc gurgles in murloc, Nihil is a sweet pessimist. A new pet
    needs, in EVERY locale file (Locales\PetPhrases_<locale>.lua):
      - every key of `events`, `annoyed` included (about 10 lines, in order
        of growing annoyance, in its own way of getting annoyed);
      - every context of CONTEXTS in `cheer`, about 100 lines in total, and
        the same number in each language;
      - if it has a rage form, `transform` and `calm` (a few lines each):
        what it roars as it turns into a horror and how it comes back to
        itself, both in character.
    Write new lines in the pet's own voice; do not copy or adapt another
    pet's lines, and do not quote other games or franchises (inspiration in
    tone only). Then add its sprite (tools/pet/<species>-art.js and SPECIES
    in tools/pet/build-pets.js), its entry in PetSprite.SPECIES and SHEETS
    (UI\Pet\Sprite.lua), and PET_NAME_<species> and PET_SPECIES_<species> in
    Locales\enUS.lua and esES.lua. An unfiltered voice is optional too: it
    is still the same personality, only crueler, and it mocks how the player
    plays (deaths, slowness, choices), never the person, their real traits
    or any group of people; no swearing. A rage form is optional: its frames
    (RAGE and COLLAPSE, see tools/pet/void-art.js) and an entry in
    PetSprite.RAGE_FORMS.
------------------------------------------------------------------------------]]

local _, ns = ...

local PetTalk = {}
ns.PetTalk = PetTalk
ns.PetPhrases = ns.PetPhrases or {}

local JITTER = 0.2           -- cheers come up to 20% earlier or later
local RETRY_DELAY = 30       -- seconds to wait when the moment is not right
local RECENT_WINDOW = 120    -- seconds a kill, quest or dance stays "recent"
local RESTED_CHANCE = 0.35   -- how often rested experience is the topic
local MEMORY = 10            -- recent lines that are not repeated
local CHEER_DURATION = 5     -- seconds the bubble stays up
local POKE_DURATION = 1.8    -- the same for the short sound on a click
local POKE_CHEER_CHANCE = 0.75 -- a click says a cheer this often (else a sound)
local DEFAULT_INTERVAL = 300 -- seconds between cheers when nothing is set

-- Choices of time between cheers, in seconds (the options' slider steps).
PetTalk.INTERVALS = { 20, 30, 45, 60, 120, 180, 300, 600, 900, 1200, 1800 }

-- Contexts every species has phrases for, in no particular order.
PetTalk.CONTEXTS = {
    "general", "combat", "danger", "kill", "quest", "dungeon", "resting",
    "swimming", "fishing", "dancing", "flying", "dead", "almost", "rested",
}

local said = {}  -- recent lines, oldest first
local nextCheerAt

local function Settings()
    return ns.settings.pet
end

-- Suffix of a species' unfiltered voice in ns.PetPhrases (see the header).
local HARSH_SUFFIX = "_harsh"

-- Client locales served by another table (as in Core\Locale.lua).
local LOCALE_ALIASES = { esMX = "esES", enGB = "enUS" }

--- Language the pet talks in: its own setting (settings.pet.locale), or the
--- addon's language when that is "auto".
function PetTalk:GetLocale()
    local code = Settings().locale
    if not code or code == "auto" then
        return ns.activeLocale
    end
    code = LOCALE_ALIASES[code] or code
    return ns.PetPhrases[code] and code or ns.activeLocale
end

--- Phrase table of a species in the pet's language and the one to fall back
--- on for a missing key: English, or the usual voice when the unfiltered one
--- is in use.
local function GetPhrases(species)
    local phrases = ns.PetPhrases[PetTalk:GetLocale()] or ns.PetPhrases.enUS or {}
    local english = ns.PetPhrases.enUS or {}
    local usual = phrases[species] or english[species] or english.murloc or {}
    if Settings().harsh then
        local voice = species .. HARSH_SUFFIX
        local harsh = phrases[voice] or english[voice]
        if harsh then
            return harsh, usual
        end
    end
    return usual, english[species] or {}
end

--- True when a species has an unfiltered voice in some language.
function PetTalk:HasHarshVoice(species)
    local voice = species .. HARSH_SUFFIX
    for _, phrases in pairs(ns.PetPhrases) do
        if phrases[voice] then
            return true
        end
    end
    return false
end

local function WasSaid(line)
    for _, previous in ipairs(said) do
        if previous == line then
            return true
        end
    end
    return false
end

--- Picks a line from a list, avoiding the last few that were said.
local function Pick(lines)
    if type(lines) == "string" then
        return lines
    end
    if type(lines) ~= "table" or #lines == 0 then
        return nil
    end
    local candidates = {}
    for _, line in ipairs(lines) do
        if not WasSaid(line) then
            candidates[#candidates + 1] = line
        end
    end
    if #candidates == 0 then
        candidates = lines
    end
    local line = candidates[math.random(1, #candidates)]
    said[#said + 1] = line
    if #said > MEMORY then
        table.remove(said, 1)
    end
    return line
end

--- Line of the active species for an event, formatted with the arguments.
function PetTalk:Event(key, ...)
    local own, fallback = GetPhrases(ns.Pet:GetSpecies())
    local lines = (own.events and own.events[key]) or (fallback.events and fallback.events[key])
    local line = Pick(lines)
    if line and select("#", ...) > 0 then
        line = line:format(...)
    end
    return line
end

local function IsRecent(pet, action, now)
    local at = pet.recent and pet.recent[action]
    return at ~= nil and now - at <= RECENT_WINDOW
end

--- What the player is doing right now, as one of CONTEXTS.
function PetTalk:GetContext()
    local pet = ns.Pet
    local now = GetTime()
    if pet.dead or pet.ghost then
        return "dead"
    elseif pet.inCombat then
        return pet.lowHealth and "danger" or "combat"
    end
    -- The most recent of the remembered actions wins.
    local latest, latestAt
    for _, action in ipairs({ "kill", "quest", "dancing" }) do
        if IsRecent(pet, action, now) and (not latestAt or pet.recent[action] > latestAt) then
            latest, latestAt = action, pet.recent[action]
        end
    end
    if latest then
        return latest
    elseif pet.fishing then
        return "fishing"
    elseif pet.underwater then
        return "swimming"
    elseif ns.Compat.IsFlying() then
        return "flying"
    elseif ns.Compat.GetActivityContext() ~= "world" then
        return "dungeon"
    elseif pet.resting then
        return "resting"
    elseif pet.excited then
        return "almost"
    end
    local rested = ns.SafeNumber(ns.Compat.GetRestedExperience())
    if rested and rested > 0 and math.random() < RESTED_CHANCE then
        return "rested"
    end
    return "general"
end

--- A cheering line for the current moment (or for `context`).
function PetTalk:GetCheer(context)
    context = context or self:GetContext()
    local own, fallback = GetPhrases(ns.Pet:GetSpecies())
    local cheer, fallbackCheer = own.cheer or {}, fallback.cheer or {}
    local lines = cheer[context] or fallbackCheer[context]
    if type(lines) ~= "table" or #lines == 0 then
        lines = cheer.general or fallbackCheer.general
    end
    return Pick(lines)
end

--- Says a cheering line right away (also used by the options' test button).
function PetTalk:Cheer()
    local pet = ns.Pet
    if not (pet.frame and pet.frame:IsShown()) then
        return false
    end
    pet:Say(self:GetCheer(), CHEER_DURATION)
    return true
end

--- Line number `step` of the annoyed lines (clicked over and over), in order
--- and starting over after the last one.
local function GetAnnoyedLines()
    local own, fallback = GetPhrases(ns.Pet:GetSpecies())
    local lines = own.events and own.events.annoyed
    if type(lines) ~= "table" or #lines == 0 then
        lines = fallback.events and fallback.events.annoyed
    end
    if type(lines) ~= "table" or #lines == 0 then
        return nil
    end
    return lines
end

function PetTalk:GetAnnoyedLine(step)
    local lines = GetAnnoyedLines()
    if not lines then
        return self:Event("poke")
    end
    return lines[(step - 1) % #lines + 1]
end

--- How many annoyed lines the pet has before it starts over (or, with a
--- rage form, transforms).
function PetTalk:GetAnnoyedCount()
    local lines = GetAnnoyedLines()
    return lines and #lines or 0
end

--- What the pet says when clicked: usually a cheer for the moment, now and
--- then just its usual sound. Returns the line and how long to show it.
function PetTalk:GetPokeLine()
    if math.random() < POKE_CHEER_CHANCE then
        return self:GetCheer(), CHEER_DURATION
    end
    return self:Event("poke"), POKE_DURATION
end

--- Seconds between cheers (settings.pet.cheerSeconds, at least the first
--- of INTERVALS).
function PetTalk:GetInterval()
    return math.max(PetTalk.INTERVALS[1], tonumber(Settings().cheerSeconds) or DEFAULT_INTERVAL)
end

--- Plans the next cheer from now.
function PetTalk:Reschedule()
    local seconds = self:GetInterval() * (1 - JITTER + math.random() * JITTER * 2)
    nextCheerAt = GetTime() + seconds
end

--- Called by the pet's poll: says a cheer when it is time.
function PetTalk:Update()
    if not Settings().cheer then
        nextCheerAt = nil
        return
    end
    local now = GetTime()
    if not nextCheerAt then
        self:Reschedule()
        return
    end
    if now < nextCheerAt then
        return
    end
    local pet = ns.Pet
    local busy = pet.demo or pet.afk or pet.frame.speech:IsShown()
    if busy or not pet.frame:IsShown() then
        nextCheerAt = now + math.min(RETRY_DELAY, self:GetInterval() / 2)
        return
    end
    self:Cheer()
    self:Reschedule()
end
