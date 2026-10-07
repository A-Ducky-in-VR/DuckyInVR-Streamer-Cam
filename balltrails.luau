-- Streamer Cam ball trail styles drawn with plain world lines.
-- Every style is a pure function of the trail points and the clock: nothing is simulated or
-- remembered here, so a style cannot drift, pile up lines, or break the camera. main.luau keeps
-- the list of recent ball positions and calls Trails.draw once per tick.
--
-- A trail point is { position, life, speed, born }: `life` counts down from the trail duration
-- (so life / duration is 1 at the ball and 0 at the tail end) and `born` is the clock time the
-- point was recorded, which gives every point a value that stays the same from frame to frame.
-- ctx: { line(a, b, r, g, b, thickness), duration, thickness, time, up, colour(speed, fade) }
local Trails = {}

-- Styles this module draws. main.luau routes these names here; anything else keeps its old drawing.
Trails.styles = { "Comet Tail", "Sparkle Stream", "Double Helix", "Rainbow", "Lightning", "Fire" }
-- Names that are new in the menu (Comet Tail and Sparkle Stream were already listed).
Trails.newStyles = { "Double Helix", "Rainbow", "Lightning", "Fire" }
Trails.handles = {}
for _, styleName in ipairs(Trails.styles) do Trails.handles[styleName] = true end

local TAU = math.pi * 2
local MAX_GAP = 2500 -- a jump this long between two points is a ball reset, not a path

local function clamp01(v) return math.clamp(v, 0, 1) end
local function mix(a, b, u) return a + (b - a) * u end
local function hash(n)
	local x = math.sin(n * 12.9898 + 4.1414) * 43758.5453
	return x - math.floor(x)
end
local function norm(v, fallback)
	local length = v:length()
	if length ~= length or length < 0.0001 then return fallback end
	return v * (1 / length)
end

-- Two directions at right angles to `direction`: sideways and "up-ish".
local function frameFor(direction, up)
	local side = norm(direction:cross(up), nil)
	if side == nil then side = norm(direction:cross(Vec3.new(1, 0, 0)), Vec3.new(0, 1, 0)) end
	return side, norm(side:cross(direction), up)
end

local function hsv(h, s, v)
	h = (h - math.floor(h)) * 6
	local i = math.floor(h)
	local f = h - i
	local a, b, c = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	if i == 0 then return v, c, a elseif i == 1 then return b, v, a elseif i == 2 then return a, v, c
	elseif i == 3 then return a, b, v elseif i == 4 then return c, a, v end
	return v, a, b
end

-- At most `maxSegments` segments, always ending on the newest point (the ball itself).
local function sample(trail, maxSegments)
	local count = #trail
	local stride = math.max(1, math.ceil((count - 1) / maxSegments))
	local reversed = {}
	local i = count
	while i >= 1 do
		reversed[#reversed + 1] = trail[i]
		i -= stride
	end
	local picked = {}
	for j = #reversed, 1, -1 do picked[#picked + 1] = reversed[j] end
	return picked
end

local function joined(a, c)
	local gap = (c.position - a.position):length()
	return gap == gap and gap <= MAX_GAP
end

-- A number that belongs to one trail point and never changes while that point exists.
local function key(point, index) return (point.born or index * 0.02) end

-- Direction of travel at point i (from its neighbours).
local function travel(points, i, up)
	local before = points[math.max(i - 1, 1)]
	local after = points[math.min(i + 1, #points)]
	return norm(after.position - before.position, up)
end

local draw = {}

-- COMET TAIL: fat white-hot head that tapers to a thin tail, shedding sparks that drift outward.
draw["Comet Tail"] = function(trail, ctx)
	local points = sample(trail, 64)
	for i = 2, #points do
		local a, c = points[i - 1], points[i]
		if joined(a, c) then
			local f = clamp01(c.life / ctx.duration)
			local r, g, b = ctx.colour(c.speed, math.max(f, 0.2))
			local width = ctx.thickness * (0.3 + 2.6 * f ^ 1.7)
			ctx.line(a.position, c.position, r, g, b, width)
			if f > 0.55 then ctx.line(a.position, c.position, 1, 1, 1, width * 0.38 * ((f - 0.55) / 0.45)) end
			local seed = key(c, i) * 977
			if f > 0.1 and f < 0.92 and hash(seed + 2) < 0.34 then
				local side, lift = frameFor(norm(c.position - a.position, ctx.up), ctx.up)
				local angle = hash(seed) * TAU
				local outward = (side * math.cos(angle)) + (lift * math.sin(angle))
				local start = c.position + (outward * ((8 + 46 * (1 - f)) * (0.5 + hash(seed + 1))))
				ctx.line(start, start + (outward * (4 + 10 * f)), r, g, b, ctx.thickness * 0.6 * f)
			end
		end
	end
end

-- SPARKLE STREAM: a thin thread with twinkling four-point stars scattered round it.
draw["Sparkle Stream"] = function(trail, ctx)
	local points = sample(trail, 50)
	local twinkleFrame = math.floor(ctx.time * 10)
	for i = 2, #points do
		local a, c = points[i - 1], points[i]
		if joined(a, c) then
			local f = clamp01(c.life / ctx.duration)
			local r, g, b = ctx.colour(c.speed, math.max(f, 0.25))
			ctx.line(a.position, c.position, r, g, b, ctx.thickness * (0.3 + 0.5 * f))
			local seed = key(c, i) * 613
			if hash(seed) < 0.5 and hash(seed + 7 + twinkleFrame * 3) > 0.35 then
				local side, lift = frameFor(norm(c.position - a.position, ctx.up), ctx.up)
				local angle = hash(seed + 1) * TAU
				local centre = c.position + (((side * math.cos(angle)) + (lift * math.sin(angle))) * (6 + 30 * (1 - f) * hash(seed + 2)))
				local size = (3 + 6 * hash(seed + 3)) * (0.4 + 0.6 * f)
				local sr, sg, sb = mix(r, 1, 0.6), mix(g, 1, 0.6), mix(b, 1, 0.6)
				ctx.line(centre - (side * size), centre + (side * size), sr, sg, sb, ctx.thickness * 0.5 * f)
				ctx.line(centre - (lift * size), centre + (lift * size), sr, sg, sb, ctx.thickness * 0.5 * f)
			end
		end
	end
end

-- DOUBLE HELIX: two strands wound round the ball's path, with rungs between them, opening out
-- as the trail ages.
draw["Double Helix"] = function(trail, ctx)
	local points = sample(trail, 56)
	local previousA, previousB, previousStep = nil, nil, nil
	for i = 1, #points do
		local c = points[i]
		local f = clamp01(c.life / ctx.duration)
		local side, lift = frameFor(travel(points, i, ctx.up), ctx.up)
		local phase = key(c, i) * 18
		local radius = (6 + 10 * (1 - f)) * math.max(ctx.thickness / 4, 0.5)
		local offset = ((side * math.cos(phase)) + (lift * math.sin(phase))) * radius
		local strandA, strandB = c.position + offset, c.position - offset
		local step = math.floor(phase / (math.pi / 2))
		if i > 1 and previousA ~= nil and joined(points[i - 1], c) then
			local r, g, b = ctx.colour(c.speed, math.max(f, 0.25))
			local width = ctx.thickness * (0.35 + 0.8 * f)
			ctx.line(previousA, strandA, r, g, b, width)
			ctx.line(previousB, strandB, mix(r, 1, 0.65), mix(g, 1, 0.65), mix(b, 1, 0.65), width)
			if step ~= previousStep then ctx.line(strandA, strandB, r, g, b, width * 0.45) end -- rung
		end
		previousA, previousB, previousStep = strandA, strandB, step
	end
end

-- RAINBOW: the colour runs through the whole spectrum along the trail.
draw["Rainbow"] = function(trail, ctx)
	local points = sample(trail, 110)
	for i = 2, #points do
		local a, c = points[i - 1], points[i]
		if joined(a, c) then
			local f = clamp01(c.life / ctx.duration)
			local glow = math.max(f, 0.3)
			local r, g, b = hsv(key(c, i) * 0.45, 1, 1)
			local width = ctx.thickness * (0.6 + 1.7 * f)
			ctx.line(a.position, c.position, r * glow, g * glow, b * glow, width)
			if f > 0.75 then ctx.line(a.position, c.position, 1, 1, 1, width * 0.3 * ((f - 0.75) / 0.25)) end
		end
	end
end

-- LIGHTNING: a crackling bolt chases the ball. The path re-jags 14 times a second and throws
-- short forks; the end at the ball stays put.
draw["Lightning"] = function(trail, ctx)
	local points = sample(trail, 48)
	local frame = math.floor(ctx.time * 14)
	local count = #points
	local previous = nil
	for i = 1, count do
		local c = points[i]
		local f = clamp01(c.life / ctx.duration)
		local side, lift = frameFor(travel(points, i, ctx.up), ctx.up)
		local seed = key(c, i) * 1000 + frame * 7
		local reach = if i == count then 0 else (5 + 13 * (1 - f))
		local position = c.position + (side * ((hash(seed) - 0.5) * 2 * reach)) + (lift * ((hash(seed + 1) - 0.5) * 2 * reach))
		if previous ~= nil and joined(points[i - 1], c) then
			local r, g, b = ctx.colour(c.speed, math.max(f, 0.3))
			local power = 0.35 + 0.65 * f
			ctx.line(previous, position, r, g, b, ctx.thickness * 1.5 * power)
			ctx.line(previous, position, 1, 1, 1, ctx.thickness * 0.45 * power)
			if hash(seed + 2) < 0.14 then -- fork
				local angle = hash(seed + 3) * TAU
				local outward = (side * math.cos(angle)) + (lift * math.sin(angle))
				local elbow = position + (outward * (10 + 12 * hash(seed + 4)))
				ctx.line(position, elbow, r, g, b, ctx.thickness * 0.7 * power)
				ctx.line(elbow, elbow + (outward * (6 + 10 * hash(seed + 5))) + (side * ((hash(seed + 6) - 0.5) * 14)), r, g, b, ctx.thickness * 0.45 * power)
			end
		end
		previous = position
	end
end

-- FIRE: white-hot at the ball, cooling through yellow, orange and red to dark smoke, with
-- flames licking upward and a few embers rising off the old part of the trail.
local function fireColour(f)
	if f > 0.8 then local u = (f - 0.8) / 0.2 return 1, mix(0.78, 0.96, u), mix(0.25, 0.70, u) end
	if f > 0.5 then local u = (f - 0.5) / 0.3 return 1, mix(0.42, 0.78, u), mix(0.05, 0.25, u) end
	if f > 0.2 then local u = (f - 0.2) / 0.3 return mix(0.80, 1, u), mix(0.10, 0.42, u), mix(0.02, 0.05, u) end
	local u = f / 0.2
	return mix(0.22, 0.80, u), mix(0.03, 0.10, u), 0.02
end

draw["Fire"] = function(trail, ctx)
	local points = sample(trail, 56)
	local frame = math.floor(ctx.time * 12)
	for i = 2, #points do
		local a, c = points[i - 1], points[i]
		if joined(a, c) then
			local f = clamp01(c.life / ctx.duration)
			local r, g, b = fireColour(f)
			ctx.line(a.position, c.position, r, g, b, ctx.thickness * (0.5 + 2.3 * f))
			local seed = key(c, i) * 113
			local side = frameFor(norm(c.position - a.position, ctx.up), ctx.up)
			if f > 0.12 then -- flame tongue
				local flick = hash(seed + frame * 5)
				local hr, hg, hb = fireColour(math.min(f + 0.2, 1))
				local tip = c.position + (ctx.up * ((8 + 34 * flick) * (0.3 + f))) + (side * ((hash(seed + 1 + frame) - 0.5) * 12))
				ctx.line(c.position, tip, hr, hg, hb, ctx.thickness * 0.8 * f)
			end
			if f < 0.7 and hash(seed + 2) < 0.25 then -- ember
				local ember = c.position + (ctx.up * (70 * (1 - f))) + (side * (math.sin(ctx.time * 3 + seed) * 8))
				ctx.line(ember, ember + (ctx.up * 5), 1, 0.5, 0.1, ctx.thickness * 0.5 * (0.3 + f))
			end
		end
	end
end

-- Draws the trail in the named style. Returns false when the style is not one of this module's.
function Trails.draw(style, trail, ctx)
	local renderer = draw[style]
	if renderer == nil then return false end
	if trail == nil or #trail < 2 then return true end
	renderer(trail, ctx)
	return true
end

return Trails
