-- Uses material from Caster Camera by Dennssen (https://github.com/dennssen/CasterCamera),
-- which is under this licence:
--
--   MIT License
--
--   Copyright (c) 2025 dennssen
--
--   Permission is hereby granted, free of charge, to any person obtaining a copy
--   of this software and associated documentation files (the "Software"), to deal
--   in the Software without restriction, including without limitation the rights
--   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--   copies of the Software, and to permit persons to whom the Software is
--   furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in all
--   copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--   SOFTWARE.
--
-- This file is an adapted copy of Caster Camera's particlesystem.luau (2.6.4).
-- Changed for Streamer Cam: the update takes dt so it runs the same at any frame rate; a cap on
-- the number of particles and on their lifespan; colours are copied instead of modified in place;
-- ray casts and draw calls are guarded; lines go through a callback with a draw lifetime.
--
-- Ported from Dennssen Caster Camera 2.6.4 goal explosion particle system.
type Particle = {
	position: Vec3,
	rotation: Quat,
	scale: number,
	velocity: Vec3,
	color: LinearColor,
	variant: string,
	lifespan: number,
	aliveTime: number,
}

type ParticelSystem = {
	vibrance: number,
	particles: { Particle },
	replay: Replay?,
	speed: number,

	Variant: {
		Embers: string,
		Rings: string,
		GoalRing: string,
		Rocket: string,
	},

	createParticle: (
		self: ParticelSystem,
		position: Vec3,
		rotation: Quat,
		scale: number,
		velocity: Vec3,
		color: Color,
		variant: string,
		lifespan: number
	) -> (),

	particleAffect: (self: ParticelSystem, dt: number?) -> (),
	maxParticles: number,
	ringSegments: number,
	collisionEnabled: boolean,
	drawLifetime: number,
	drawLine: ((Vec3, Vec3, number, number, number, number, number) -> ())?,
}

local ParticleSystem: ParticelSystem = {} :: ParticelSystem

ParticleSystem.vibrance = 1
ParticleSystem.particles = {}
ParticleSystem.replay = nil
ParticleSystem.speed = 1
ParticleSystem.maxParticles = 120
ParticleSystem.ringSegments = 32
ParticleSystem.collisionEnabled = false
ParticleSystem.drawLifetime = 0.08
ParticleSystem.drawLine = nil
ParticleSystem.Variant = {
	Embers = "embers",
	Rings = "rings",
	GoalRing = "goalring",
	Rocket = "rocket",
}

function ParticleSystem:createParticle(
	position: Vec3,
	rotation: Quat,
	scale: number,
	velocity: Vec3,
	color: Color,
	variant: string,
	lifespan: number
)
	if #self.particles >= self.maxParticles then return end
	lifespan = math.clamp(lifespan, 1, 150) -- at most 2.5 seconds at the nominal 60 Hz
	local variantExists = false
	for _, value in pairs(self.Variant) do
		if value == variant then
			variantExists = true
		end
	end

	if not variantExists then
		warn(`Bad Variant: {variant}`)
		return
	end

	-- Never modify a caller-owned/shared Color object.
	local r, g, b = color.R * self.vibrance, color.G * self.vibrance, color.B * self.vibrance
	if r + g + b < 0.06 then r, g, b = 0.035, 0.045, 0.07 end
	local particleColor = Color.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1), 1)

	local newParticle: Particle = {
		position = position,
		rotation = rotation,
		scale = scale,
		velocity = velocity,
		color = particleColor,
		variant = variant,
		lifespan = lifespan,
		aliveTime = lifespan,
	}
	table.insert(ParticleSystem.particles, newParticle)
end

-- Spawn lifespans retain the original nominal-60-Hz frame units for compatibility.
-- Updates consume dt * 60, so 120 units lasts approximately two seconds at any FPS.
-- Work after a severe hitch is capped at 0.1 seconds; no unbounded catch-up loop.
function ParticleSystem:particleAffect(dt: number?)
	local elapsed = dt or (1 / 60)
	if elapsed ~= elapsed or elapsed <= 0 or elapsed == math.huge then return end
	local step = math.min(elapsed, 0.1) * 60 * math.max(self.speed, 0)
	local function line(a, b, color, width)
		local draw = self.drawLine or WorldDraw.drawLine
		pcall(draw, a, b, color.R, color.G, color.B, width, self.drawLifetime)
	end
	-- Reverse removal ensures each remaining particle is visited exactly once.
	for i = #self.particles, 1, -1 do
		local particle = self.particles[i]
		local ok = pcall(function()
			if not self.replay or self.replay.isPlaying then
				particle.aliveTime -= step
				if particle.aliveTime <= 0 then return end
				if particle.variant == self.Variant.Embers or particle.variant == self.Variant.Rocket then
					local up = if gravity and gravity.upDirection then gravity.upDirection else Vec3.new(0, 0, 1)
					particle.velocity -= up * (0.8 * step)
					if particle.variant ~= self.Variant.Rocket then particle.velocity *= 0.95 ^ step end
				end
				if self.collisionEnabled and particle.variant == self.Variant.Embers then
					local castOK, hit = pcall(function()
						return camera:castRay(particle.position, particle.position + particle.velocity * step)
					end)
					if castOK and hit and hit.successful and hit.normal then
						particle.velocity -= hit.normal * (2 * particle.velocity:dot(hit.normal))
					end
				end
				particle.position += particle.velocity * step
				if particle.variant ~= self.Variant.Rocket then
					particle.scale *= math.clamp(particle.aliveTime / math.max(particle.lifespan, 0.001), 0, 1) ^ step
				end
			end
			if particle.scale < 0.01 then return end
			if particle.variant == self.Variant.Embers or particle.variant == self.Variant.Rocket then
				line(particle.position, particle.position - particle.velocity, particle.color, particle.scale * 20)
			elseif particle.variant == self.Variant.Rings then
				local r = (1 - particle.aliveTime / particle.lifespan) * 6000
				local resolution = math.clamp(math.floor(self.ringSegments), 8, 90)
				local previous = Vec3.new(r, 0, -40)
				for j = 1, resolution do
					local angle = j * math.pi * 2 / resolution
					local point = Vec3.new(r * math.cos(angle), r * math.sin(angle), -40)
					line(particle.rotation:rotateVector(previous) + particle.position,
						particle.rotation:rotateVector(point) + particle.position, particle.color, particle.scale * 90)
					previous = point
				end
			elseif particle.variant == self.Variant.GoalRing then
				local outline = {
					Vec3.new(0, -248.905, -52.404), Vec3.new(0, -248.905, 109.223),
					Vec3.new(0, -188.979, 172.762), Vec3.new(0, 188.979, 172.762),
					Vec3.new(0, 248.905, 109.223), Vec3.new(0, 248.905, -52.404),
				}
				for j = 1, #outline - 1 do
					line(particle.rotation:rotateVector(outline[j]) + particle.position,
						particle.rotation:rotateVector(outline[j + 1]) + particle.position, particle.color, particle.scale * 15)
				end
			end
		end)
		if not ok or particle.aliveTime <= 0 or particle.scale < 0.01 then table.remove(self.particles, i) end
	end
end

return ParticleSystem
