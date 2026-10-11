--[[----------------------------------------------------------------------------
    XPLedger - Pet effects
    Small particle system around the murloc: confetti, sparkles, bubbles and
    the pixel art icons stored in the last row of the sprite sheets (hearts,
    music notes, stars, "!" and "Z").

    Positions and speeds are in sprite pixels from the bottom left corner of
    the pet, so the effects scale with it.
------------------------------------------------------------------------------]]

local _, ns = ...

local PetEffects = {}
ns.PetEffects = PetEffects

local Theme = ns.Theme
local PetSprite = ns.PetSprite

local MAX_PARTICLES = 60
local SPARKLE_TEXTURE = "Interface\\Cooldown\\star4"
local ICON_SIZE = 8

-- Icon index in the sheet (see ICONS in tools/pet/murloc-art.js).
local ICONS = { heart = 0, note = 1, star = 2, exclaim = 3, zee = 4 }

local CONFETTI_COLORS = {
    { 0.31, 0.76, 0.97 }, { 0.96, 0.78, 0.30 }, { 1, 0.44, 0.71 }, { 0.57, 0.83, 0.42 }, { 0.89, 0.41, 0.24 },
}

-- Particles spawned while an effect is active: `burst` when it starts, then
-- `rate` per second.
PetEffects.EMITTERS = {
    party = { kind = "confetti", rate = 14, burst = 24 },
    happy = { kind = "sparkle", rate = 5, burst = 6 },
    evolve = { kind = "sparkle", rate = 14, burst = 20 },
    victory = { kind = "sparkle", rate = 3, burst = 8 },
    swim = { kind = "bubble", rate = 1.8, burst = 2 },
    sleep = { kind = "zee", rate = 0.7, burst = 1 },
    dance = { kind = "note", rate = 2, burst = 1 },
    love = { kind = "heart", rate = 3, burst = 2 },
    quest = { kind = "exclaim", rate = 0, burst = 1 },
    revive = { kind = "star", rate = 1.5, burst = 2 },
}

local function Random(low, high)
    return low + math.random() * (high - low)
end

local Effects = {}
Effects.__index = Effects

--- Creates the particle system of a pet frame. `getPixel` returns the size
--- of a sprite pixel in screen pixels.
function PetEffects.Create(frame, getPixel)
    return setmetatable({ frame = frame, getPixel = getPixel, particles = {}, pool = {}, credit = 0 }, Effects)
end

--- Starts the effect of a state or reaction (nil stops spawning).
function Effects:SetEmitter(name)
    self.emitter = name and PetEffects.EMITTERS[name]
    self.credit = 0
    if self.emitter and self.frame:IsShown() then
        for _ = 1, self.emitter.burst or 0 do
            self:Spawn(self.emitter.kind)
        end
    end
end

function Effects:Acquire(kind)
    local texture = table.remove(self.pool) or self.frame:CreateTexture(nil, "OVERLAY")
    texture:SetTexCoord(0, 1, 0, 1)
    if kind == "sparkle" then
        texture:SetTexture(SPARKLE_TEXTURE)
        texture:SetBlendMode("ADD")
    elseif ICONS[kind] then
        local index = ICONS[kind]
        local perRow = PetSprite.SIZE / ICON_SIZE
        local sheetWidth = PetSprite.SIZE * PetSprite.COLUMNS
        local sheetHeight = PetSprite.SIZE * PetSprite.ROWS
        local left = (index % perRow) * ICON_SIZE
        local top = (PetSprite.ROWS - 1) * PetSprite.SIZE + math.floor(index / perRow) * ICON_SIZE
        texture:SetTexture(PetSprite.TEXTURE_PATH .. 1, nil, nil, "NEAREST")
        texture:SetTexCoord(left / sheetWidth, (left + ICON_SIZE) / sheetWidth,
            top / sheetHeight, (top + ICON_SIZE) / sheetHeight)
        texture:SetBlendMode("BLEND")
    else
        texture:SetTexture(Theme.WHITE)
        texture:SetBlendMode("BLEND")
    end
    texture:SetVertexColor(1, 1, 1, 1)
    return texture
end

--- Spawns one particle of the given kind.
function Effects:Spawn(kind)
    if #self.particles >= MAX_PARTICLES then
        return
    end
    local region = self:Acquire(kind)
    local p = { region = region, kind = kind, age = 0, phase = Random(0, 6.28), vx = 0, vy = 0 }
    if kind == "confetti" then
        local color = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
        region:SetVertexColor(color[1], color[2], color[3], 1)
        p.size = 1
        p.x, p.y = Random(4, 28), Random(24, 32)
        p.vx, p.vy = Random(-8, 8), Random(8, 22)
        p.gravity = -40
        p.life = Random(1.2, 1.8)
    elseif kind == "sparkle" then
        region:SetVertexColor(1, 0.85, 0.35, 1)
        p.size = Random(4, 7)
        p.x, p.y = Random(2, 30), Random(4, 26)
        p.vy = Random(4, 10)
        p.life = Random(0.6, 1)
    elseif kind == "bubble" then
        region:SetVertexColor(0.7, 0.9, 1, 0.75)
        p.size = math.random(1, 2)
        p.x, p.y = Random(14, 18), 14
        p.vy = Random(8, 12)
        p.wobble = 1.5
        p.life = Random(1.2, 1.8)
    elseif kind == "zee" then
        p.size = 6
        p.x, p.y = 22, 24
        p.vx, p.vy = 3, 5
        p.life = 2.4
    elseif kind == "note" then
        p.size = 7
        p.x, p.y = Random(4, 28), Random(20, 26)
        p.vx, p.vy = Random(-3, 3), Random(5, 8)
        p.wobble = 1
        p.life = 1.6
    elseif kind == "heart" then
        p.size = 6
        p.x, p.y = Random(10, 22), 24
        p.vx, p.vy = Random(-2, 2), Random(6, 9)
        p.life = 1.4
    elseif kind == "exclaim" then
        p.size = 8
        p.x, p.y = 25, 28
        p.vy = 3
        p.life = 1.4
    elseif kind == "star" then
        -- Orbits above the head.
        p.size = 5
        p.orbit = true
        p.life = Random(1.4, 2)
    end
    region:Show()
    self.particles[#self.particles + 1] = p
    self:Place(p)
end

function Effects:Place(p)
    local pixel = self.getPixel()
    local region = p.region
    local x, y = p.x, p.y
    if p.orbit then
        local angle = p.phase + p.age * 4
        x, y = 16 + math.cos(angle) * 9, 27 + math.sin(angle) * 2.5
    elseif p.wobble then
        x = x + math.sin(p.age * 6 + p.phase) * p.wobble
    end
    region:ClearAllPoints()
    region:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x * pixel, y * pixel)
    region:SetSize(p.size * pixel, p.size * pixel)
    local remaining = 1 - p.age / p.life
    region:SetAlpha(math.min(1, remaining * (p.kind == "confetti" and 3 or 2)))
end

function Effects:Release(p)
    p.region:Hide()
    self.pool[#self.pool + 1] = p.region
end

function Effects:Clear()
    for i = 1, #self.particles do
        self:Release(self.particles[i])
    end
    self.particles = {}
end

function Effects:Update(elapsed)
    local emitter = self.emitter
    if emitter and emitter.rate > 0 then
        self.credit = self.credit + elapsed * emitter.rate
        while self.credit >= 1 do
            self.credit = self.credit - 1
            self:Spawn(emitter.kind)
        end
    end
    local alive = {}
    for i = 1, #self.particles do
        local p = self.particles[i]
        p.age = p.age + elapsed
        if p.age >= p.life then
            self:Release(p)
        else
            p.vy = p.vy + (p.gravity or 0) * elapsed
            p.x = (p.x or 0) + p.vx * elapsed
            p.y = (p.y or 0) + p.vy * elapsed
            self:Place(p)
            alive[#alive + 1] = p
        end
    end
    self.particles = alive
end
