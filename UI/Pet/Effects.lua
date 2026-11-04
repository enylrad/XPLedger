--[[----------------------------------------------------------------------------
    XPLedger - Pet effects
    Small particle system around the murloc: confetti, sparkles, bubbles and
    the pixel art icons stored in the last row of the sprite sheets (hearts,
    music notes, stars, "!" and "Z"), and the specks of Void of the rage form.

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

-- The Void: black and deep violet specks (no flashes, nothing bright).
local VOID_COLORS = { { 0.1, 0.04, 0.2 }, { 0.18, 0.09, 0.36 }, { 0.27, 0.15, 0.5 }, { 0.43, 0.34, 0.69 } }
-- Where the ball of Void sits while the pet transforms, in sprite pixels.
local BALL_X, BALL_Y = 16, 8

-- Bursts of the transformation (see Effects:Burst): how many particles.
PetEffects.BURSTS = { implode = 22, bang = 34, pop = 12 }

local CONFETTI_COLORS = {
    { 0.31, 0.76, 0.97 }, { 0.96, 0.78, 0.30 }, { 1, 0.44, 0.71 }, { 0.57, 0.83, 0.42 }, { 0.89, 0.41, 0.24 },
}

-- Particles spawned while an effect is active: `burst` when it starts, then
-- `rate` per second.
PetEffects.EMITTERS = {
    party = { kind = "confetti", rate = 14, burst = 24 },
    happy = { kind = "sparkle", rate = 5, burst = 6 },
    victory = { kind = "sparkle", rate = 3, burst = 8 },
    swim = { kind = "bubble", rate = 1.8, burst = 2 },
    sleep = { kind = "zee", rate = 0.7, burst = 1 },
    dance = { kind = "note", rate = 2, burst = 1 },
    love = { kind = "heart", rate = 3, burst = 2 },
    quest = { kind = "exclaim", rate = 0, burst = 1 },
    revive = { kind = "star", rate = 1.5, burst = 2 },
    rage = { kind = "mote", rate = 12, burst = 0 },
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
        texture:SetTexture(PetSprite.GetTexture("murloc"), nil, nil, "NEAREST")
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

--- Spawns a one-off burst of PetEffects.BURSTS: the Void sucked into the
--- ball (implode), thrown out of it (bang) or a small puff (pop).
function Effects:Burst(kind)
    if not self.frame:IsShown() then
        return
    end
    for _ = 1, PetEffects.BURSTS[kind] or 0 do
        self:Spawn(kind)
    end
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
    elseif kind == "mote" or kind == "implode" or kind == "bang" or kind == "pop" then
        -- Specks of Void (WHITE texture, tinted black and deep violet).
        local color = VOID_COLORS[math.random(1, #VOID_COLORS)]
        region:SetVertexColor(color[1], color[2], color[3], 1)
        p.size = math.random(1, 2)
        local angle = Random(0, 6.28)
        if kind == "mote" then
            -- Drifting up all around the horror (twice the pet's size).
            p.x, p.y = Random(-12, 44), Random(2, 44)
            p.vy = Random(5, 12)
            p.wobble = 1.5
            p.life = Random(0.9, 1.5)
        elseif kind == "implode" then
            -- From a ring around the ball straight into it.
            local distance = Random(14, 22)
            p.life = Random(0.45, 0.7)
            p.x, p.y = BALL_X + math.cos(angle) * distance, BALL_Y + 8 + math.sin(angle) * distance
            p.vx = (BALL_X - p.x) / p.life
            p.vy = (BALL_Y - p.y) / p.life
        else
            -- Out of the ball in every direction, fast, then slowing down.
            local speed = kind == "bang" and Random(40, 80) or Random(15, 30)
            p.x, p.y = BALL_X, BALL_Y
            p.vx, p.vy = math.cos(angle) * speed, math.sin(angle) * speed + 10
            p.drag = 3
            p.life = Random(0.5, 0.9)
            if kind == "bang" then
                p.size = math.random(1, 3)
            end
        end
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
    -- Runs every frame while the pet is shown: the list is compacted in
    -- place, so nothing is allocated (and there is no work at all when no
    -- particle is alive).
    local particles = self.particles
    local count = #particles
    if count == 0 then
        return
    end
    local alive = 0
    for i = 1, count do
        local p = particles[i]
        particles[i] = nil
        p.age = p.age + elapsed
        if p.age >= p.life then
            self:Release(p)
        else
            p.vy = p.vy + (p.gravity or 0) * elapsed
            if p.drag then
                local keep = math.max(0, 1 - p.drag * elapsed)
                p.vx, p.vy = p.vx * keep, p.vy * keep
            end
            p.x = (p.x or 0) + p.vx * elapsed
            p.y = (p.y or 0) + p.vy * elapsed
            self:Place(p)
            alive = alive + 1
            particles[alive] = p
        end
    end
end
