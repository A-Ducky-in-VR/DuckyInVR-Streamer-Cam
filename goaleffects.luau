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
-- None of his code is copied here. Taken from Caster Camera 2.6.4: the size and shape of the goal
-- mouth (its GoalRing outline), used to place the effects. The effects are written for Streamer Cam.
--
-- Streamer Cam goal effects drawn with plain world lines (no engine particles needed).
-- Every effect is a pure function of its age: nothing is simulated per frame, so an effect
-- looks the same at any frame rate and can never "run away". Each effect is designed to stay
-- inside the per-tick line budget (default 256) instead of relying on lines being dropped.
--
-- An effect entry `p` carries the frozen goal frame: p.center (goal-mouth origin, or the ball
-- spot for ball-centred effects), p.right / p.upDir / p.forward (forward points OUT of the goal,
-- toward the field), p.r/p.g/p.b, p.life, p.maxLife, p.impact (where the ball went in, optional)
-- p.ground (the floor under the ball spot, optional), p.goalOrigin (the goal frame origin when
-- p.center is the ball spot, optional) and p.seed.
-- `line(a, b, r, g, b, thickness)` submits one budgeted line.
--
-- Line thickness is in WORLD units (the same units as positions; a goal mouth is 498 wide).
-- Caster 2.6.4 relies on that: its ball outline is drawn on a plane 10 units from the camera with
-- the thickness scaled down by distance, and its goal rings are 40-80 thick. So a line as thick as
-- it is long is a filled square, and a stack of touching thick lines is a filled shape. Filled
-- shapes here are built that way, in the goal plane (lines face the camera, so a "fill" lying flat
-- on the floor would stand up: floor things are drawn as outlines instead).
local Effects = {}

-- Effects this module draws. main.luau routes these type names here.
Effects.handles = {
	["Crumble"] = true, ["Claw Strike"] = true, ["Dueling Dragons"] = true,
	["Implosion"] = true, ["Ducky Spirit"] = true, ["Juice Box"] = true, ["Lucky Cat"] = true,
	["UFO"] = true, ["Gunslinger"] = true, ["Airstrike"] = true, ["Zero-G Battle"] = true,
	["Caster Shockwave"] = true, -- not in the menu: the extra layer main.luau adds to Caster Burst
	["Fireworks"] = true, ["Lightning Strike"] = true, ["Net Ripple"] = true,
	["Glass Shatter"] = true, ["Tornado"] = true,
	["Slushie"] = true, ["Trash Panda"] = true,
}
-- New effect names, appended to the GUI lists.
Effects.newTypes = { "Fireworks", "Lightning Strike", "Net Ripple", "Glass Shatter", "Tornado", "Juice Box", "Lucky Cat", "UFO", "Gunslinger", "Airstrike", "Zero-G Battle", "Slushie", "Trash Panda" }
-- Shortest lifetime (seconds) at which each animation still reads properly.
Effects.minLife = {
	["Crumble"] = 2.6, ["Claw Strike"] = 1.1, ["Fireworks"] = 2.6, ["Lightning Strike"] = 1.2,
	["Net Ripple"] = 1.7, ["Glass Shatter"] = 1.9, ["Tornado"] = 2.2, ["Dueling Dragons"] = 3.2,
	["Implosion"] = 2.4, ["Ducky Spirit"] = 3.2, ["Juice Box"] = 4.2, ["Caster Shockwave"] = 1.5, ["Lucky Cat"] = 4.0,
	["UFO"] = 5.2, ["Gunslinger"] = 4.6, ["Airstrike"] = 4.2, ["Zero-G Battle"] = 5.0,
	["Slushie"] = 4.8, ["Trash Panda"] = 5.6,
}
-- Drawn at the ball spot instead of on the goal mouth.
Effects.ballCentered = { ["Lightning Strike"] = true, ["Tornado"] = true, ["Implosion"] = true, ["Caster Shockwave"] = true, ["Airstrike"] = true }

-- Goal-mouth outline from Caster's GoalRing, relative to the goal frame origin:
-- 498 wide, from 52 below the origin to 173 above it, with chamfered top corners.
local HALF_W, SHOULDER_X = 248.905, 188.979
local BOTTOM, SHOULDER_Y, TOP = -52.404, 109.223, 172.762
local MID_Y = (BOTTOM + TOP) * 0.5
local TAU = math.pi * 2

local function clamp01(v) return math.clamp(v, 0, 1) end
local function hash(n)
	local x = math.sin(n * 12.9898 + 4.1414) * 43758.5453
	return x - math.floor(x)
end
local function easeOut(u) u = clamp01(u); return 1 - (1 - u) * (1 - u) * (1 - u) end
local function smooth(u) u = clamp01(u); return u * u * (3 - 2 * u) end
local function easeOutBack(u) u = clamp01(u) - 1; return 1 + 2.70158 * u * u * u + 1.70158 * u * u end
local function mix(a, b, u) return a + (b - a) * u end
local function norm(v, fallback)
	local length = v:length()
	if length ~= length or length < 0.0001 then return fallback end
	return v * (1 / length)
end

-- Height of the goal mouth's top edge at horizontal offset x.
local function topAt(x)
	local ax = math.abs(x)
	if ax <= SHOULDER_X then return TOP end
	return mix(TOP, SHOULDER_Y, clamp01((ax - SHOULDER_X) / (HALF_W - SHOULDER_X)))
end

local function colour(p, vibrance, gain)
	local k = (vibrance or 1.35) * (gain or 1)
	return clamp01(p.r * k), clamp01(p.g * k), clamp01(p.b * k)
end

-- Main colour plus the accent colour used for cores, sparks, cracks and highlights.
-- Team / default colours: bright main colour with white-hot accents.
-- A paint colour (Black, Crimson, Gold, custom...): the WHOLE effect is that paint. The main
-- features use exactly the chosen colour, and accents are only a slightly lighter shade of it,
-- never white or gold, so a black explosion is black and a crimson one is crimson.
local function palette(p, ctx, gain)
	if p.painted then
		local r, g, b = clamp01(p.r), clamp01(p.g), clamp01(p.b)
		return r, g, b, mix(r, 1, 0.12), mix(g, 1, 0.12), mix(b, 1, 0.12)
	end
	local r, g, b = colour(p, ctx.vibrance, gain)
	return r, g, b, 1, 1, 1
end

local function outline(p, line, r, g, b, thickness, lift, grow)
	local points = {
		{ -HALF_W, BOTTOM }, { -HALF_W, SHOULDER_Y }, { -SHOULDER_X, TOP },
		{ SHOULDER_X, TOP }, { HALF_W, SHOULDER_Y }, { HALF_W, BOTTOM },
	}
	for i = 1, #points - 1 do
		local a = p.center + (p.right * (points[i][1] * grow)) + (p.upDir * (MID_Y + (points[i][2] - MID_Y) * grow)) + (p.forward * lift)
		local c = p.center + (p.right * (points[i + 1][1] * grow)) + (p.upDir * (MID_Y + (points[i + 1][2] - MID_Y) * grow)) + (p.forward * lift)
		line(a, c, r, g, b, thickness)
	end
end

-- Where the ball went in, in goal-mouth coordinates (x along right, y along up), kept inside the mouth.
local function impactPoint(p, margin)
	local x, y = 0, MID_Y
	if p.impact ~= nil then
		local offset = p.impact - p.center
		x, y = offset:dot(p.right), offset:dot(p.upDir)
	end
	x = math.clamp(x, -HALF_W + margin, HALF_W - margin)
	y = math.clamp(y, BOTTOM + margin, topAt(x) - margin)
	return x, y
end

local draw = {}

-- CRUMBLE ------------------------------------------------------------------------------------
-- A SOLID brick wall seals the whole goal mouth (goal line to crossbar, post to post): you cannot
-- see the net through it. It stands, cracks, then comes down: bricks drop to the goal line,
-- bounce, slide out toward the field and fade.
--   * Every brick is one line as thick as its row is tall and as long as its cell is wide, so
--     bricks touch on all four sides. Alternate bricks are shaded so it still reads as brickwork.
--   * A few full-width slabs sit just behind the bricks while the wall stands, so there is no
--     see-through seam even where rows meet.
--   * The brick grid is sized from the line budget, so the top rows are never cut off by the cap.
draw["Crumble"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.15)
	local age = t * p.maxLife
	local grow = 1.05 -- a touch larger than the mouth so the posts are covered too
	local budget = math.max(24, (ctx.budget or 256) - 36)
	local cols = math.clamp(math.floor(math.sqrt(budget * 1.1)), 5, 18) -- bricks about twice as wide as tall
	local rows = math.clamp(math.floor(budget / (cols + 0.5)), 3, 16)
	local width = HALF_W * 2 * grow
	local cellW = width / cols
	local floorY = MID_Y + (BOTTOM - MID_Y) * grow
	local wallTop = MID_Y + (TOP - MID_Y) * grow
	local cellH = (wallTop - floorY) / rows
	local buildEnd, crackAt, fallAt = 0.25, 0.80, 1.05 -- seconds: the wall is whole from 0.3s and stands until 1.05s
	local endFade = clamp01((1 - t) / 0.18)
	local fill = 1 -- a brick line as thick as its row is tall leaves no gap (thickness is in world units)

	if age < fallAt + 0.35 then
		local frameFade = clamp01((fallAt + 0.35 - age) / 0.35)
		outline(p, line, r, g, b, 7 * frameFade, 6, grow)
	end
	-- Backing slabs: the darker brick shade, right behind the bricks while the wall stands.
	local standing = clamp01((fallAt + 0.12 - age) / 0.12)
	if standing > 0 then
		local slabs = 6
		local slabH = (wallTop - floorY) / slabs
		for i = 0, slabs - 1 do
			if age >= buildEnd * (i / slabs) then
				local y = floorY + (i + 0.5) * slabH
				local mouthY = MID_Y + (y - MID_Y) / grow
				local half = HALF_W
				if mouthY > SHOULDER_Y then half = mix(HALF_W, SHOULDER_X, clamp01((mouthY - SHOULDER_Y) / (TOP - SHOULDER_Y))) end
				half *= grow
				local left = C + (R * -half) + (U * y) + (F * 2)
				line(left, left + (R * (half * 2)), clamp01(r * 0.74), clamp01(g * 0.74), clamp01(b * 0.74), slabH * 1.08 * fill * standing)
			end
		end
	end
	-- Cracks race across the wall just before it gives way.
	if age >= crackAt and age < fallAt + 0.15 then
		local reach = clamp01((age - crackAt) / 0.18)
		for crack = 0, 2 do
			local x0 = (-0.34 + crack * 0.34) * width + (hash(p.seed + crack) - 0.5) * 60
			local previous = nil
			for step = 0, 4 do
				local u = step / 4
				if u <= reach + 0.001 then
					local x = x0 + (hash(p.seed + crack * 17 + step * 3) - 0.5) * 90
					local y = mix(MID_Y + (topAt(x0 / grow) - MID_Y) * grow, floorY, u)
					local point = C + (R * x) + (U * y) + (F * 14)
					if previous ~= nil then line(previous, point, hr, hg, hb, 3.5) end
					previous = point
				end
			end
		end
	end

	for row = 0, rows - 1 do
		local odd = row % 2 == 1 -- running-bond pattern: odd rows are shifted half a brick
		for col = (if odd then -1 else 0), cols - 1 do
			local seed = p.seed + row * 37 + (col + 1) * 91
			local middle = -width * 0.5 + (col + 0.5) * cellW + (if odd then cellW * 0.5 else 0)
			-- clip to the wall, so shifted rows end in half bricks instead of holes
			local left = math.max(middle - cellW * 0.5, -width * 0.5)
			local right = math.min(middle + cellW * 0.5, width * 0.5)
			-- Rows are the same height right across (so shifted rows meet with no seam). At the chamfered
			-- top corners a brick is laid wherever any part of it is under the goal's edge, so the
			-- corners are sealed and simply end in brick steps.
			local edgeY = MID_Y + (math.max(topAt(left / grow), topAt(right / grow)) - MID_Y) * grow
			if right - left > cellW * 0.05 and floorY + row * cellH < edgeY then
				local x = (left + right) * 0.5
				local y = floorY + (row + 0.5) * cellH
				-- build: rows pop in from the goal line up to the crossbar
				local appear = buildEnd * (row / rows) + hash(seed) * 0.03
				if age >= appear then
					local pop = clamp01((age - appear) / 0.05)
					local fall = age - (fallAt + hash(seed + 5) * 0.26 + (row / rows) * 0.10)
					local dx, dy, df, spin = 0, 0, 0, 0
					if fall > 0 then
						local drop = y - floorY
						local landAt = math.sqrt(2 * drop / 1250)
						local air = math.min(fall, landAt)
						local slide = air
						dy = -0.5 * 1250 * air * air
						if fall > landAt then
							local after = fall - landAt
							dy = -drop + 20 * math.exp(-5 * after) * math.abs(math.sin(after * 9))
							slide = landAt + (1 - math.exp(-4 * after)) / 4
						end
						dx = (hash(seed + 11) - 0.5) * 150 * slide
						df = (70 + hash(seed + 23) * 230) * slide
						spin = (hash(seed + 31) - 0.5) * 9 * air
					end
					local half = (right - left) * 0.5 * pop
					local axis = (R * math.cos(spin)) + (U * math.sin(spin))
					local position = C + (R * (x + dx)) + (U * (y + dy)) + (F * (5 + df))
					local shade = if (row + col) % 2 == 0 then 1 else 0.74
					if hash(seed + 41) > 0.93 then shade = 1.3 end
					local thickness = cellH * 1.04 * fill * endFade
					if thickness > 0.2 then
						line(position - (axis * half), position + (axis * half), clamp01(r * shade), clamp01(g * shade), clamp01(b * shade), thickness)
					end
				end
			end
		end
	end
end

-- CLAW STRIKE --------------------------------------------------------------------------------
-- Two cat-claw slashes across the goal: first from the viewer's top-left down to bottom-right,
-- then top-right down to bottom-left. Each slash is three separate claw marks; the middle one is
-- longer. Marks are tapered (thin tips, thick middle) with a slight bow, like a real scratch.
-- "Left/right" is as seen from the field looking at the goal.
draw["Claw Strike"] = function(p, t, fade, line, ctx)
	local R, U, F = p.right, p.upDir, p.forward
	local scale = ctx.scale
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.3)
	local middle = p.center + (U * MID_Y)
	local reach = 300 * scale -- half length of the middle claw
	local spacing = 64 * scale
	-- viewer's left is +right (the goal faces the viewer)
	local slashes = {
		{ start = 0.00, dir = norm((R * -0.80) + (U * -0.60), U * -1), across = norm((R * 0.60) + (U * -0.80), R), lift = 20 },
		{ start = 0.48, dir = norm((R * 0.80) + (U * -0.60), U * -1), across = norm((R * 0.60) + (U * 0.80), R), lift = 27 },
	}
	-- Each slash is on screen for `window` of the effect's life and has completely faded before
	-- the next one starts (0.38 < 0.48), so the two are never visible together.
	local window = 0.38
	local segments = 8
	for index, slash in ipairs(slashes) do
		local local_t = t - slash.start
		if local_t > 0 and local_t < window then
			local rake = easeOut(local_t / 0.12) -- how far the paw has travelled
			local glow = clamp01((window - local_t) / 0.22) -- the wound fades out quickly after the swipe
			local hot = clamp01((0.20 - local_t) / 0.20) -- white-hot core right after the swipe
			for claw = -1, 1 do
				local half = reach * (if claw == 0 then 1 else 0.80)
				-- outer claws trail the middle one a little, like a paw's arc
				local origin = middle + (slash.across * (claw * spacing)) - (slash.dir * (math.abs(claw) * reach * 0.07)) + (F * slash.lift)
				local previous = nil
				for step = 0, segments do
					local u = step / segments
					if u <= rake + 0.0001 then
						local along = (u * 2 - 1) * half
						local bow = (1 - (u * 2 - 1) * (u * 2 - 1)) * reach * 0.06
						local point = origin + (slash.dir * along) + (slash.across * bow)
						if previous ~= nil then
							local mid = (step - 0.5) / segments
							local taper = 0.18 + 0.82 * (math.sin(mid * math.pi) ^ 0.7)
							line(previous, point, r, g, b, 13 * taper * glow)
							if hot > 0.02 then
								line(previous + (F * 2), point + (F * 2), hr, hg, hb, 4.5 * taper * hot)
							end
						end
						previous = point
					end
				end
				-- sparks thrown off the claw tip while it is still moving
				if rake < 0.999 and previous ~= nil then
					for spark = 1, 3 do
						local seed = p.seed + index * 100 + claw * 10 + spark + math.floor(t * 60)
						local fling = (slash.dir * (40 + hash(seed) * 70)) + (slash.across * ((hash(seed + 1) - 0.5) * 90)) + (F * (hash(seed + 2) * 60))
						line(previous, previous + fling, hr, hg, hb, 2.5)
					end
				end
			end
		end
	end
end

-- DUELING DRAGONS ----------------------------------------------------------------------------
-- Two dragons (the scorer's colour against gold, or against ice blue if the scorer's colour is
-- itself close to gold) burst out of the foot of each goal post, chase each other round in a
-- rising spiral in front of the goal, rear back to either side above the crossbar, turn on each
-- other breathing fire, then lunge and meet nose to nose in a burst of sparks.
-- Everything is a function of age: a body is simply where its head was a moment earlier.
--
-- Drawn to look like animals rather than ribbons:
--   * body   a smooth tapering trunk shaded in three bands (dark along the back, the dragon's
--            colour, a pale belly), so it reads as round instead of flat
--   * back   a row of swept-back fins, largest behind the head; a three-pronged tail
--   * legs   four, kicking as it flies. The pair on the far side is in shadow, the near pair
--            ends in claws
--   * head   a wedge that narrows from skull to nose, with a brow ridge, a lower jaw that drops
--            when it roars, a red mouth with teeth, glowing eyes, curved horns, a chin beard and
--            whiskers streaming back over the snout
--   * fire   only while a dragon is facing its rival: an outer flame, an inner flame, a white-hot
--            core and loose embers, in each dragon's own colours, and never longer than the gap
--   * rear   they now curl round to face each other before the lunge (before, they breathed
--            their fire away from each other), and they stop nose to nose instead of overlapping
--   * clash  the dragons burst into the sparks instead of shrinking into a knot: two shock rings
--            and two waves of sparks in both colours
-- With a paint colour chosen the whole thing is that paint (darker and lighter shades of it).
draw["Dueling Dragons"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.4)
	local age = t * p.maxLife
	-- toward the camera: details are lifted a little this way so they sit on top of the body
	local E = F
	if ctx.eye ~= nil then E = norm(ctx.eye - C, F) end

	-- the two dragons' colours: body, shadow, belly, bone, eye, mouth, flame (outer, inner, core)
	local function shades(cr, cg, cb, flameOuter, flameInner)
		-- yellow eyes, or red ones on a body that is itself yellow, gold or orange
		local eye = if cr > 0.8 and cg > 0.5 and cb < 0.45 then { 1.0, 0.22, 0.12 } else { 1.0, 0.92, 0.20 }
		if p.painted then
			local light = { hr, hg, hb }
			return { body = { cr, cg, cb }, dark = { cr * 0.72, cg * 0.72, cb * 0.72 }, belly = light,
				bone = light, eye = light, mouth = { cr * 0.6, cg * 0.6, cb * 0.6 }, fire = { { cr, cg, cb }, light, light } }
		end
		return { body = { cr, cg, cb }, dark = { cr * 0.50, cg * 0.50, cb * 0.50 },
			belly = { mix(cr, 1, 0.62), mix(cg, 1, 0.62), mix(cb, 1, 0.55) },
			bone = { 0.97, 0.93, 0.80 }, eye = eye, mouth = { 0.86, 0.10, 0.10 }, fire = { flameOuter, flameInner, { 1, 1, 0.92 } } }
	end
	local tones = {
		shades(r, g, b, { mix(r, 1, 0.15), mix(g, 1, 0.15), mix(b, 1, 0.15) }, { mix(r, 1, 0.6), mix(g, 1, 0.6), mix(b, 1, 0.6) }),
		shades(1.0, 0.76, 0.12, { 1.0, 0.42, 0.06 }, { 1.0, 0.82, 0.25 }),
	}
	-- a scorer whose own colour is close to gold (orange, yellow) gets an ice-blue rival instead,
	-- so the two can be told apart
	if math.sqrt((r - 1.0) ^ 2 + (g - 0.76) ^ 2 + (b - 0.12) ^ 2) < 0.45 then
		tones[2] = shades(0.25, 0.78, 1.0, { 0.45, 0.85, 1.0 }, { 0.80, 0.95, 1.0 })
	end
	if p.painted then tones[2] = shades(r, g, b) end

	local rearAt, lungeAt, clashAt = 0.52, 0.66, 0.74 -- fractions of the effect's life
	local hs = 1.5 * scale -- head size: the head is drawn in its own units
	local noseReach = 84 * hs -- from the back of the jaw to the tip of the nose
	local axis = C + (F * (250 * scale)) + (U * MID_Y) -- the spiral turns round this point, out in front of the goal
	local low, high = BOTTOM - MID_Y + 15, (TOP - MID_Y) + 70 * scale
	local clashPoint = axis + (U * ((TOP - MID_Y) + 110 * scale))
	local turns = 1.5
	-- the dragons fade in as they leave the posts, and burst apart just after they meet
	local gone = clamp01((t - clashAt) / 0.05)
	local alpha = clamp01(t / 0.05) * (1 - gone)

	-- Where dragon d's head is at life-fraction s.
	local function head(d, s)
		s = clamp01(s)
		local startAngle = if d == 1 then 0 else math.pi
		local side = math.cos(startAngle + TAU * turns) -- which side of the goal it ends up on
		local function circle(u)
			local angle = startAngle + TAU * turns * u
			local radius = mix(250, 170, u) * scale
			return axis + (R * (math.cos(angle) * radius)) + (F * (math.sin(angle) * radius * 0.75)) + (U * mix(low, high, smooth(u)))
		end
		if s <= rearAt then return circle(s / rearAt), side end
		-- rearing back: out to the side, then curling up and round so it ends up facing its rival
		local rearFrom = circle(1)
		local rearOut = axis + (R * (side * 450 * scale)) + (U * ((TOP - MID_Y) + 150 * scale))
		local rearTo = axis + (R * (side * 290 * scale)) + (U * ((TOP - MID_Y) + 150 * scale))
		if s <= lungeAt then
			local w = smooth((s - rearAt) / (lungeAt - rearAt))
			return (rearFrom * ((1 - w) * (1 - w))) + (rearOut * (2 * w * (1 - w))) + (rearTo * (w * w)), side
		end
		local hit = clashPoint + (R * (side * (noseReach - 8 * scale))) -- the noses just meet
		if s <= clashAt then
			local w = (s - lungeAt) / (clashAt - lungeAt)
			return rearTo + ((hit - rearTo) * (w * w)), side
		end
		return hit, side
	end

	local segments, lag = 24, 0.0082
	for d = 1, 2 do
		if alpha <= 0.01 then break end
		local tone = tones[d]
		local body, dark, belly, bone = tone.body, tone.dark, tone.belly, tone.bone
		local H, side = head(d, t)
		local D = norm(H - head(d, t - 0.012), R * -side) -- the way it is facing: the way it is flying
		local N = norm(U - (D * U:dot(D)), F)
		local B = D:cross(N)
		local toRival = D:dot(R) * -side -- above 0 when it is facing the other dragon
		local firing = t > rearAt and t < clashAt and toRival > 0.2
		local jaw = if firing then 0.85 + 0.15 * math.sin(age * 23 + d) else 0.25 + 0.15 * math.sin(age * 7 + d)
		local function part(a, c, colour, thickness) line(a, c, colour[1], colour[2], colour[3], thickness * alpha) end

		-- THE SPINE. Each point is where the head was a moment earlier, with a wave running down it.
		local spine, girths, tangents, ups = { [0] = H - (D * (14 * hs)) }, { [0] = 46 * scale }, {}, {}
		for k = 1, segments do
			spine[k] = head(d, t - k * lag) + (U * (math.sin(k * 0.75 - age * 9) * 20 * scale * math.min(k / 4, 1)))
			girths[k] = mix(46, 6, (k / segments) ^ 0.85) * scale
			local T = norm(spine[k - 1] - spine[k], D) -- along the body, toward the head
			tangents[k], ups[k] = T, norm(U - (T * U:dot(T)), F)
		end

		-- LEGS at the shoulders and the hips. The far pair is drawn first, in shadow.
		local function leg(k, which, near)
			local point, thick, T, up = spine[k], girths[k], tangents[k], ups[k]
			local sideways = T:cross(up) * which
			local kick = math.sin(age * 10 + k + d + which) * 12 * scale
			local hip = point - (up * (thick * 0.25)) + (sideways * (thick * 0.35))
			local knee = hip - (up * (26 * scale)) + (sideways * (8 * scale)) - (T * (10 * scale + kick))
			local foot = knee - (up * (14 * scale)) + (T * (20 * scale))
			part(hip, knee, if near then body else dark, thick * 0.36)
			part(knee, foot, if near then body else dark, thick * 0.24)
			if near then part(foot, foot + (T * (14 * scale)) - (up * (7 * scale)), bone, 4.5 * scale) end
		end
		local function legs(near)
			for _, k in ipairs({ 6, 15 }) do
				local nearSide = if tangents[k]:cross(ups[k]):dot(E) >= 0 then 1 else -1
				leg(k, if near then nearSide else -nearSide, near)
			end
		end
		legs(false)

		-- THE TRUNK. Strokes run a little past each joint so the bends have no notches.
		for k = 1, segments do
			local reach = tangents[k] * (girths[k] * 0.2)
			part(spine[k - 1] + reach, spine[k] - reach, body, (girths[k - 1] + girths[k]) * 0.5)
		end
		-- shading on top of it: dark along the back, pale along the belly, fins standing off the back
		for k = 1, segments - 6 do
			local T, up, thick = tangents[k], ups[k], girths[k]
			local girth = (girths[k - 1] + thick) * 0.5
			local reach = T * (thick * 0.2)
			local lift = E * 3
			if k >= 2 and k <= segments - 7 then
				local over = (up * (girth * 0.37)) + lift
				part(spine[k - 1] + over + reach, spine[k] + over - reach, dark, girth * 0.24)
			end
			local under = (up * (-girth * 0.30)) + lift
			part(spine[k - 1] + under + reach, spine[k] + under - reach, belly, girth * 0.36)
			if k % 3 == 0 then
				local size = (thick * 0.55 + 8 * scale) * (if k <= 6 then 1.3 else 1)
				local root = spine[k] + (up * (thick * 0.46))
				part(root + (T * (size * 0.30)), root + (up * (size * 0.80)) - (T * (size * 0.85)), dark, size * 0.27)
			end
		end
		legs(true)
		do -- three-pronged tail
			local point, T, up = spine[segments], tangents[segments], ups[segments]
			for prong = -1, 1 do
				part(point, point - (T * ((44 - 10 * math.abs(prong)) * scale)) + (up * (prong * 22 * scale)), if prong == 0 then belly else dark, (7 - 2 * math.abs(prong)) * scale)
			end
		end

		-- THE HEAD: a wedge that narrows from the skull to the nose, drawn over the neck
		local function at(forward, up, sideways, out) return H + (D * (forward * hs)) + (N * (up * hs)) + (B * ((sideways or 0) * hs)) + (E * (out or 0)) end
		local tilt = 4 * jaw -- the upper jaw lifts a little as the mouth opens
		local drop = 34 * jaw -- how far the tip of the lower jaw has dropped
		if jaw > 0.4 then -- inside of the mouth, behind both jaws
			part(at(16, -8 - drop * 0.15), at(68, -3 - drop * 0.5), tone.mouth, (10 + 16 * jaw) * hs)
		end
		part(at(-22, 0), at(14, 2), body, 40 * hs) -- skull
		part(at(9, 2), at(40, 3 + tilt), body, 32 * hs) -- muzzle
		part(at(35, 3 + tilt), at(66, 5 + tilt * 2), body, 24 * hs) -- snout
		part(at(61, 5 + tilt * 2), at(84, 7 + tilt * 2.8), body, 17 * hs) -- nose
		part(at(-12, 17, 0, 3), at(28, 13 + tilt * 0.5, 0, 3), dark, 6.5 * hs) -- brow ridge
		part(at(0, -11), at(44, -13 - drop * 0.5), belly, 13 * hs) -- lower jaw
		part(at(40, -13 - drop * 0.5), at(78, -13 - drop), belly, 9 * hs)
		part(at(28, -19 - drop * 0.33), at(10, -36 - drop * 0.33), belly, 4.5 * hs) -- chin beard
		if jaw > 0.5 then -- teeth: a fang and a smaller tooth in each jaw
			part(at(74, -2 + tilt * 2.6, 0, 4), at(75, -14 + tilt * 2.6, 0, 4), bone, 3.6 * hs)
			part(at(56, -6 + tilt * 1.7, 0, 4), at(57, -15 + tilt * 1.7, 0, 4), bone, 3.0 * hs)
			part(at(68, -9 - drop * 0.87, 0, 4), at(69, 2 - drop * 0.87, 0, 4), bone, 3.2 * hs)
			part(at(52, -9 - drop * 0.66, 0, 4), at(53, 0 - drop * 0.66, 0, 4), bone, 2.8 * hs)
		end
		for wing = -1, 1, 2 do -- once for each side of the head
			part(at(12, 8, wing * 13, 5), at(23, 10, wing * 12, 5), tone.eye, (if firing then 9 else 7) * hs) -- eye
			local hornMid = at(-34, 31, wing * 15)
			part(at(-6, 15, wing * 9), hornMid, bone, 6.5 * hs) -- horn: curves back, then levels off
			part(hornMid, at(-60, 36, wing * 18), bone, 3.6 * hs)
			local sway = math.sin(age * 8 + wing + d) * 6
			local bend = at(50, 30 + sway, wing * 14)
			part(at(76, 12 + tilt * 2.5, wing * 6), bend, belly, 3.0 * hs) -- whisker, streaming back over the snout
			part(bend, at(18, 40 - sway, wing * 20), belly, 2.1 * hs)
		end

		-- FIRE, only while it is facing its rival, and no longer than the gap between them
		if firing then
			local mouth = at(80, -4 - drop * 0.4)
			local power = clamp01((toRival - 0.2) / 0.4)
			-- aimed mostly at the spot where they will meet, and reaching just past halfway to it
			local aim = norm((D * 0.45) + (norm(clashPoint - mouth, D) * 0.55), D)
			local room = math.max(0, math.abs((H - clashPoint):dot(R)) - noseReach) * 1.15 + 30 * scale
			local frame = math.floor(age / 0.045)
			for i = 1, 12 do
				local layer = if i <= 4 then 1 elseif i <= 7 then 2 elseif i == 8 then 3 else 4
				local seed = p.seed + d * 500 + i * 13 + frame * 7
				local spread = (if layer == 1 then 90 elseif layer == 2 then 46 elseif layer == 3 then 10 else 130) * scale * power
				local reach = (if layer == 1 then 170 + 110 * hash(seed) elseif layer == 2 then 140 + 70 * hash(seed) elseif layer == 3 then 130 else 200 + 120 * hash(seed)) * scale * power
				reach = math.min(reach, room)
				local tip = mouth + (aim * reach) + (N * ((hash(seed + 1) - 0.5) * spread)) + (B * ((hash(seed + 2) - 0.5) * spread))
				if layer == 1 then -- outer flame: starts a little way out, so the fire widens as it goes
					part(mouth + ((tip - mouth) * 0.12), tip, tone.fire[1], (15 + 9 * hash(seed + 3)) * scale)
				elseif layer == 2 then
					part(mouth, tip, tone.fire[2], 10 * scale)
				elseif layer == 3 then
					part(mouth, tip, tone.fire[3], 6.5 * scale)
				else -- loose embers at the far end
					part(tip - (aim * (24 * scale * power)), tip, tone.fire[2], 5 * scale)
				end
			end
		end
	end

	-- THE CLASH
	if t >= clashAt then
		local q = (t - clashAt) / (1 - clashAt)
		local late = 0.05 / (1 - clashAt) -- how far into the clash the dragons have gone
		if q < 0.14 then -- flash
			local size = (60 + 240 * (q / 0.14)) * scale
			local glow = 1 - q / 0.14
			line(clashPoint - (R * size), clashPoint + (R * size), hr, hg, hb, 20 * glow)
			line(clashPoint - (U * size), clashPoint + (U * size), hr, hg, hb, 20 * glow)
		end
		-- shock rings, facing the field: a bright one at once, and one in the rival's colour behind it
		local function ring(from, length, colour, reach, thickness)
			local w = (q - from) / length
			if w <= 0 or w >= 1 then return end
			local radius = (40 + reach * easeOut(w)) * scale
			local previous = nil
			for i = 0, 18 do
				local angle = i * TAU / 18
				local point = clashPoint + (R * (math.cos(angle) * radius)) + (U * (math.sin(angle) * radius))
				if previous ~= nil then line(previous, point, colour[1], colour[2], colour[3], thickness * (1 - w) ^ 2) end
				previous = point
			end
		end
		ring(0, 0.6, { hr, hg, hb }, 300, 14)
		-- sparks in both dragons' colours: one wave at the hit, a second as the dragons burst apart
		local function sparks(from, count, seedBase, speed, thickness)
			local w = (q - from) / (1 - from)
			if w <= 0 then return end
			local out = easeOut(w / 0.7)
			for i = 1, count do
				local seed = p.seed + seedBase + i * 19
				local angle, lean = hash(seed) * TAU, (hash(seed + 1) - 0.5) * 1.6
				local direction = (R * (math.cos(angle) * math.cos(lean))) + (U * (math.sin(angle) * math.cos(lean))) + (F * math.sin(lean))
				local distance = out * (130 + 230 * hash(seed + 2)) * scale * speed
				local colour = if i % 5 == 0 then tones[1].belly else tones[1 + i % 2].body
				local point = clashPoint + (direction * distance) - (U * (90 * w * w * scale)) -- sparks sag a little as they die
				line(point - (direction * (distance * 0.2)), point, colour[1], colour[2], colour[3], thickness * (1 - w))
			end
		end
		sparks(0, 24, 3000, 1, 10)
		if q >= late then
			ring(late, 0.62, tones[2].body, 380, 12)
			sparks(late, 26, 5000, 1.25, 8)
		end
	end
end

-- IMPLOSION (ball spot) ----------------------------------------------------------------------
-- Everything is dragged into the spot where the ball went in: debris spirals inward faster and
-- faster, three rings close like a fist, the core burns brighter... then a beat of nothing, and
-- it detonates: a flash, shock rings tearing outward across the goal and along the floor, and
-- shards thrown in every direction.
draw["Implosion"] = function(p, t, fade, line, ctx)
	local T, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.5)
	local age = t * p.maxLife
	local collapseEnd, bangAt = 0.52, 0.60
	if t < bangAt then
		local u = clamp01(t / collapseEnd)
		local quiet = if t > collapseEnd then 1 - (t - collapseEnd) / (bangAt - collapseEnd) else 1 -- the held breath
		-- core: a star that grows as matter arrives, then shrinks to a point before the bang
		local reach = (20 + 110 * u + 14 * math.sin(age * 40)) * scale * quiet
		for axis = 1, 3 do
			local direction = if axis == 1 then R elseif axis == 2 then U else norm(R + U, R)
			if axis == 3 and age % 0.1 > 0.05 then direction = norm(R - U, R) end
			line(T - (direction * reach), T + (direction * reach), hr, hg, hb, (6 + 22 * u) * scale * quiet)
		end
		-- three rings closing in, each in its own plane
		local planes = { { R, U }, { R, norm((U * 0.5) + (F * 0.87), U) }, { U, norm((R * 0.5) + (F * 0.87), R) } }
		for index, plane in ipairs(planes) do
			local delay = (index - 1) * 0.16
			local v = clamp01((u - delay) / (1 - delay))
			if v > 0 and v < 1 then
				local radius = 780 * scale * (1 - v * v)
				local spin = age * (1.5 + index)
				local previous = nil
				for i = 0, 20 do
					local angle = i * TAU / 20 + spin
					local point = T + (plane[1] * (math.cos(angle) * radius)) + (plane[2] * (math.sin(angle) * radius))
					if previous ~= nil then line(previous, point, mix(r, hr, v * 0.6), mix(g, hg, v * 0.6), mix(b, hb, v * 0.6), (5 + 24 * v) * scale) end
					previous = point
				end
			end
		end
		-- debris spiralling in (the swirl faces the field)
		for i = 1, 44 do
			local seed = p.seed + i * 23
			local delay = hash(seed + 5) * 0.28
			local v = clamp01((u - delay) / (1 - delay))
			if v > 0 and v < 1 then
				local startRadius = (520 + 560 * hash(seed)) * scale
				local startAngle, tilt = hash(seed + 1) * TAU, (hash(seed + 2) - 0.5) * 1.5
				local function at(w)
					local pull = w * w * w
					local angle = startAngle + w * w * 3.6
					local radius = startRadius * (1 - pull)
					return T + (R * (math.cos(angle) * math.cos(tilt) * radius)) + (U * (math.sin(angle) * math.cos(tilt) * radius)) + (F * (math.sin(tilt) * radius))
				end
				local pull = v * v * v
				line(at(math.max(v - 0.04 - 0.10 * v, 0)), at(v), mix(r, hr, pull * 0.7), mix(g, hg, pull * 0.7), mix(b, hb, pull * 0.7), (6 + 13 * pull) * scale * clamp01(v / 0.08))
			end
		end
		return
	end

	local w = (t - bangAt) / (1 - bangAt)
	local out = easeOut(w)
	if w < 0.18 then -- flash: six long spikes
		local glow = 1 - w / 0.18
		local length = (300 + 1500 * (w / 0.18)) * scale
		for i = 0, 2 do
			local angle = i * math.pi / 3 + 0.3
			local direction = (R * math.cos(angle)) + (U * math.sin(angle))
			line(T - (direction * length), T + (direction * length), hr, hg, hb, 30 * glow * scale)
		end
	end
	-- shock rings: across the goal, along the floor, and a second wave behind the first
	local rings = {
		{ R, U, 1250, 0, 36 },
		{ R, F, 1500, 0, 28 },
		{ R, U, 900, 0.14, 22 },
	}
	for _, ring in ipairs(rings) do
		local v = clamp01((w - ring[4]) / (1 - ring[4]))
		if v > 0 and v < 1 then
			local radius = easeOut(v) * ring[3] * scale
			local previous = nil
			for i = 0, 24 do
				local angle = i * TAU / 24
				local point = T + (ring[1] * (math.cos(angle) * radius)) + (ring[2] * (math.sin(angle) * radius))
				if previous ~= nil then line(previous, point, r, g, b, ring[5] * scale * (1 - v) ^ 2) end
				previous = point
			end
		end
	end
	for i = 1, 40 do -- shards
		local seed = p.seed + 5000 + i * 31
		local angle, tilt = hash(seed) * TAU, (hash(seed + 1) - 0.5) * 2.2
		local direction = (R * (math.cos(angle) * math.cos(tilt))) + (U * (math.sin(angle) * math.cos(tilt))) + (F * math.sin(tilt))
		local distance = out * (420 + 900 * hash(seed + 2)) * scale
		local point = T + (direction * distance) - (U * (160 * w * w * scale))
		local bright = i % 3 == 0
		line(point - (direction * (distance * 0.24)), point, if bright then hr else r, if bright then hg else g, if bright then hb else b, (8 + 12 * hash(seed + 3)) * scale * (1 - w))
	end
end

-- CASTER SHOCKWAVE (ball spot) ---------------------------------------------------------------
-- The extra layer under Caster Burst: a flash, a pillar of light punching up out of the ball
-- spot, heavy shards, then a second pop. Kept under 45 lines a tick, because the Caster embers
-- and rings drawn after it need the rest of the line budget.
draw["Caster Shockwave"] = function(p, t, fade, line, ctx)
	local T, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.5)
	if t < 0.16 then -- flash
		local glow = 1 - t / 0.16
		local length = (200 + 1100 * (t / 0.16)) * scale
		for i = 0, 2 do
			local angle = i * math.pi / 3
			local direction = (R * math.cos(angle)) + (U * math.sin(angle))
			line(T - (direction * length), T + (direction * length), hr, hg, hb, 26 * glow * scale)
		end
	end
	if t < 0.45 then -- pillar of light
		local u = t / 0.45
		local top = T + (U * (1300 * easeOut(u) * scale))
		line(T - (U * (60 * scale)), top, r, g, b, 70 * scale * (1 - u))
		line(T - (U * (60 * scale)), top, hr, hg, hb, 24 * scale * (1 - u))
	end
	if t < 0.55 then -- heavy shards
		local u = t / 0.55
		for i = 1, 14 do
			local seed = p.seed + i * 41
			local angle, tilt = hash(seed) * TAU, (hash(seed + 1) - 0.5) * 2
			local direction = (R * (math.cos(angle) * math.cos(tilt))) + (U * (math.sin(angle) * math.cos(tilt))) + (F * math.sin(tilt))
			local distance = easeOut(u) * (500 + 700 * hash(seed + 2)) * scale
			line(T + (direction * (distance * 0.7)), T + (direction * distance), hr, hg, hb, 18 * scale * (1 - u))
		end
	end
	if t > 0.30 and t < 0.80 then -- second pop
		local u = (t - 0.30) / 0.50
		local radius = easeOut(u) * 560 * scale
		local previous = nil
		for i = 0, 16 do
			local angle = i * TAU / 16
			local point = T + (R * (math.cos(angle) * radius)) + (U * (math.sin(angle) * radius))
			if previous ~= nil then line(previous, point, r, g, b, 26 * scale * (1 - u) ^ 2) end
			previous = point
		end
		for i = 1, 10 do
			local seed = p.seed + 900 + i * 17
			local angle = hash(seed) * TAU
			local direction = (R * math.cos(angle)) + (U * math.sin(angle)) + (F * (hash(seed + 1) - 0.5))
			local distance = easeOut(u) * (260 + 420 * hash(seed + 2)) * scale
			line(T + (direction * (distance * 0.8)), T + (direction * distance), hr, hg, hb, 12 * scale * (1 - u))
		end
	end
end

-- DUCKY SPIRIT -------------------------------------------------------------------------------
-- A giant rubber duck pops up out of the goal and floats in front of it: solid yellow body and
-- head, orange beak, eye with a glint, a wing that flaps. It bobs and rocks on rippling water
-- with bubbles drifting up, quacks three times (beak opens, sound rings fly off), then swells,
-- shakes and bursts into feathers.
-- The duck is built from stacked thick lines, so it is a filled shape, not a wireframe.
draw["Ducky Spirit"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local age = t * p.maxLife
	local body, wing, beak, eye, glint = { 1.0, 0.84, 0.05 }, { 0.96, 0.64, 0.02 }, { 1.0, 0.42, 0.0 }, { 0.03, 0.03, 0.03 }, { 1, 1, 1 }
	local wr, wg, wb = colour(p, ctx.vibrance, 1.1) -- water: the scorer's colour
	if p.painted then
		-- the whole duck (and its water) is the paint; wing, beak and eye are only a shade lighter
		local r, g, b, hr, hg, hb = palette(p, ctx, 1)
		body, wing, beak, eye, glint = { r, g, b }, { hr, hg, hb }, { hr, hg, hb }, { hr, hg, hb }, { hr, hg, hb }
		wr, wg, wb = r, g, b
	end
	local popAt = 0.84
	local unit = 150 * scale -- half the length of the body
	local floatAt = C + (F * (280 * scale)) + (U * (MID_Y + 95 * scale))

	if t < popAt then
		local up = clamp01(t / 0.16)
		local size = unit * math.max(easeOutBack(up), 0.02) * (if t > 0.74 then 1 + 0.22 * smooth((t - 0.74) / (popAt - 0.74)) else 1)
		local rock = math.sin(age * 2.4) * 0.12 + (if t > 0.74 then math.sin(age * 55) * 0.05 else 0)
		local origin = C + (F * (mix(40, 280, up) * scale)) + (U * (MID_Y + mix(-40, 95, smooth(up)) * scale + math.sin(age * 3.2) * 16 * scale))
		local cosR, sinR = math.cos(rock), math.sin(rock)
		-- duck coordinates: x toward the beak, y up, in body half-lengths; depth toward the field
		local function at(x, y, depth)
			return origin + (R * ((x * cosR - y * sinR) * size)) + (U * ((x * sinR + y * cosR) * size)) + (F * ((depth or 0) * size))
		end
		local quack = 0
		for _, moment in { 0.26, 0.44, 0.62 } do
			quack = math.max(quack, clamp01(1 - math.abs(t - moment - 0.02) / 0.04))
			local ring = (t - moment) / 0.11
			if ring > 0 and ring < 1 then -- "quack": arcs flying off the beak
				for k = 0, 2 do
					local radius = 0.22 + 0.55 * ring + k * 0.15
					local previous = nil
					for i = 0, 4 do
						local angle = -0.6 + i * 0.3
						local point = at(1.45 + math.cos(angle) * radius, 0.82 + math.sin(angle) * radius, 0.05)
						if previous ~= nil then line(previous, point, glint[1], glint[2], glint[3], 9 * scale * (1 - ring)) end
						previous = point
					end
				end
			end
		end
		-- body: a filled ellipse with the tail swept up at the back
		local rows = 9
		for i = 0, rows - 1 do
			local v = (i + 0.5) / rows * 2 - 1
			local half = math.sqrt(1 - v * v)
			local back = half + (if v > 0.1 then 0.26 * (v - 0.1) else 0)
			line(at(-back, v * 0.62), at(half, v * 0.62), body[1], body[2], body[3], (1.24 / rows) * size * 1.16)
		end
		line(at(-0.90, 0.26), at(-1.30, 0.66), body[1], body[2], body[3], 0.22 * size) -- tail
		-- head: a filled circle
		rows = 7
		for i = 0, rows - 1 do
			local v = (i + 0.5) / rows * 2 - 1
			local half = math.sqrt(1 - v * v) * 0.44
			line(at(0.60 - half, 0.88 + v * 0.44), at(0.60 + half, 0.88 + v * 0.44), body[1], body[2], body[3], (0.88 / rows) * size * 1.16)
		end
		-- wing: three feathers fanning back from the shoulder, flapping
		local flap = math.sin(age * (if t > 0.74 then 26 else 9)) * 0.30
		for k = 0, 2 do
			line(at(0.24, 0.10 - k * 0.07, 0.10), at(-0.62 + (if k == 1 then -0.08 else 0), 0.20 - k * 0.20 + flap * (0.5 + k * 0.2), 0.10), wing[1], wing[2], wing[3], 0.17 * size)
		end
		-- beak (opens on each quack), eye and glint
		line(at(0.98, 0.87, 0.03), at(1.42, 0.85 + quack * 0.12, 0.03), beak[1], beak[2], beak[3], 0.11 * size)
		line(at(0.98, 0.79, 0.03), at(1.36, 0.75 - quack * 0.18, 0.03), beak[1], beak[2], beak[3], 0.10 * size)
		line(at(0.64, 1.00, 0.12), at(0.76, 1.00, 0.12), eye[1], eye[2], eye[3], 0.12 * size)
		line(at(0.715, 1.035, 0.15), at(0.755, 1.035, 0.15), glint[1], glint[2], glint[3], 0.04 * size)
		-- water rippling out under it, and bubbles drifting up past it
		local floorAt = C + (F * (280 * scale)) + (U * BOTTOM)
		for k = 0, 1 do
			local cycle = age * 0.7 + k * 0.5
			cycle -= math.floor(cycle)
			local radius = (70 + 320 * cycle) * scale * up
			local previous = nil
			for i = 0, 14 do
				local angle = i * TAU / 14
				local point = floorAt + (R * (math.cos(angle) * radius)) + (F * (math.sin(angle) * radius * 0.6))
				if previous ~= nil then line(previous, point, wr, wg, wb, 9 * scale * (1 - cycle)) end
				previous = point
			end
		end
		for i = 1, 12 do
			local seed = p.seed + i * 29
			local cycle = age * (0.30 + 0.25 * hash(seed)) + hash(seed + 1)
			cycle -= math.floor(cycle)
			local width = (12 + 22 * hash(seed + 2)) * scale * (1 - cycle * 0.5) * up
			local point = floatAt + (R * (((hash(seed + 3) - 0.5) * 3.4 * unit) + math.sin(age * 2 + i) * 14 * scale))
				+ (U * ((-0.9 + cycle * 2.9) * unit)) + (F * ((hash(seed + 4) - 0.5) * unit))
			line(point - (R * (width * 0.5)), point + (R * (width * 0.5)), wr, wg, wb, width)
		end
		return
	end

	-- burst into feathers
	local w = (t - popAt) / (1 - popAt)
	local out = easeOut(w)
	local burstAt = floatAt + (U * (0.3 * unit))
	if w < 0.5 then
		local radius = easeOut(w / 0.5) * 560 * scale
		local previous = nil
		for i = 0, 20 do
			local angle = i * TAU / 20
			local point = burstAt + (R * (math.cos(angle) * radius)) + (U * (math.sin(angle) * radius))
			if previous ~= nil then line(previous, point, glint[1], glint[2], glint[3], 22 * scale * (1 - w / 0.5) ^ 2) end
			previous = point
		end
	end
	for i = 1, 40 do
		local seed = p.seed + 700 + i * 37
		local angle, tilt = hash(seed) * TAU, (hash(seed + 1) - 0.5) * 1.8
		local direction = (R * (math.cos(angle) * math.cos(tilt))) + (U * (math.sin(angle) * math.cos(tilt) + 0.25)) + (F * math.sin(tilt))
		local point = burstAt + (direction * (out * (160 + 440 * hash(seed + 2)) * scale)) - (U * (300 * w * w * scale))
		local tumble = hash(seed + 3) * TAU + age * (4 + 6 * hash(seed + 4))
		local along = ((R * math.cos(tumble)) + (U * math.sin(tumble))) * ((22 + 20 * hash(seed + 5)) * scale)
		local tone = if i % 3 == 0 then wing elseif i % 3 == 1 then body else glint
		line(point - along, point + along, tone[1], tone[2], tone[3], 16 * scale * (1 - w))
	end
end

-- JUICE BOX ----------------------------------------------------------------------------------
-- A giant juice box drops onto the field in front of the goal and a bendy straw jabs into the top. It gets a
-- test squeeze (a short squirt), then a hard one: the sides cave in, the box shakes and creases,
-- and juice arcs out of the straw in a big fountain across the front of the goal, splashing into
-- a puddle. The box stays crumpled while the last drips fall. The box is about as wide as half
-- the goal and nearly twice as tall, so it reads from across the arena.
-- Box and label are filled (stacked thick lines); the box has a side and a top so it reads as 3D.
draw["Juice Box"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = math.min(ctx.scale, 1.5)
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.2)
	local age = t * p.maxLife
	local life = p.maxLife
	local dark = if p.painted then 0.74 else 0.55 -- shade for edges, the side face and creases
	local jr, jg, jb = 1.0, 0.60, 0.08 -- orange juice
	if p.painted then
		jr, jg, jb = hr, hg, hb
	elseif p.r > 0.75 and p.g > 0.25 and p.g < 0.75 and p.b < 0.35 then
		jr, jg, jb = 0.66, 0.28, 0.98 -- an orange box gets grape juice so the stream still stands out
	end
	local alpha = clamp01(t / 0.03) * clamp01((1 - t) / 0.12)

	-- how hard it is being squeezed, 0..1
	local first = 0.45 * clamp01(1 - math.abs(t - 0.21) / 0.045)
	local second = if t < 0.30 then 0 elseif t < 0.38 then smooth((t - 0.30) / 0.08) elseif t < 0.72 then 1 else mix(1, 0.8, smooth((t - 0.72) / 0.10))
	local squeeze = math.max(first, second)
	local gripping = t > 0.38 and t < 0.72

	local width, height, depth = 190 * scale, 300 * scale * (1 - 0.10 * squeeze), 110 * scale
	local landed = clamp01(t / 0.09)
	local drop = (1 - landed) ^ 2 * math.abs(math.cos(landed * 4.7)) * 700 * scale -- falls in, one small bounce
	local shake = if gripping then math.sin(age * 47) * 8 * scale else 0
	-- It stands well out on the field (about 4.6 m in front of the goal line at the default scale),
	-- so nothing of the goal, its net or its roof is between the box, the straw and the camera.
	local base = C + (F * (340 * scale)) + (U * (BOTTOM + drop)) + (R * shake)
	local back = ((R * 0.30) - (F * 0.90)) * depth -- from the front face to the back face
	local function halfWidth(v) return width * 0.5 * (1 - 0.5 * squeeze * math.max(math.sin(math.pi * v), 0) ^ 1.4) end
	local function front(x, v, out) return base + (R * x) + (U * (v * height)) + (F * (out or 0)) end

	-- front face, with a label band and a fruit on it
	local rows = 12
	for i = 0, rows - 1 do
		local v = (i + 0.5) / rows
		local half = halfWidth(v)
		local label = v > 0.36 and v < 0.70
		line(front(-half, v), front(half, v), if label then hr else r, if label then hg else g, if label then hb else b, height / rows * 1.14 * alpha)
	end
	for k = 0, 1 do
		local v = 0.47 + k * 0.11
		local half = halfWidth(v) * (if k == 0 then 0.34 else 0.26)
		line(front(-half, v, 3), front(half, v, 3), jr, jg, jb, height * 0.10 * alpha)
	end
	-- right side and top, so it is a box and not a card
	for i = 0, 5 do
		local v = (i + 0.5) / 6
		local edge = front(halfWidth(v), v)
		line(edge, edge + back, clamp01(r * dark), clamp01(g * dark), clamp01(b * dark), height / 6 * 1.14 * alpha)
	end
	for i = 0, 2 do
		local shift = back * ((i + 0.5) / 3)
		line(front(-width * 0.5, 1) + shift, front(width * 0.5, 1) + shift, mix(r, hr, 0.35), mix(g, hg, 0.35), mix(b, hb, 0.35), depth / 3 * 1.14 * alpha)
	end
	-- outline of the front, following the dents
	for sideSign = -1, 1, 2 do
		local previous = nil
		for i = 0, 8 do
			local v = i / 8
			local point = front(sideSign * halfWidth(v), v, 2)
			if previous ~= nil then line(previous, point, clamp01(r * dark), clamp01(g * dark), clamp01(b * dark), 8 * scale * alpha) end
			previous = point
		end
	end
	if squeeze > 0.4 then -- creases
		local deep = (squeeze - 0.4) / 0.6
		local creases = { { -0.55, 0.30, 0.25, 0.44 }, { 0.50, 0.52, -0.20, 0.62 }, { -0.35, 0.78, 0.40, 0.70 } }
		for _, crease in ipairs(creases) do
			line(front(crease[1] * halfWidth(crease[2]), crease[2], 3), front(crease[3] * halfWidth(crease[4]), crease[4], 3), clamp01(r * dark), clamp01(g * dark), clamp01(b * dark), 7 * scale * deep * alpha)
		end
	end
	-- the squeeze itself: two arrowheads pushing the sides in
	if t > 0.16 and t < 0.74 and squeeze > 0.02 then
		for sideSign = -1, 1, 2 do
			local tip = front(sideSign * (halfWidth(0.5) + (22 + 70 * (1 - squeeze)) * scale), 0.5, 4)
			local arm = R * (sideSign * 80 * scale)
			line(tip, tip + arm + (U * (60 * scale)), hr, hg, hb, 18 * scale * alpha)
			line(tip, tip + arm - (U * (60 * scale)), hr, hg, hb, 18 * scale * alpha)
		end
	end

	-- bendy straw: slides in from above, then stays
	-- (it points up and across the goal, so the stream is seen side-on from the field)
	local strawIn = smooth((t - 0.09) / 0.06)
	local nozzle, aim = nil, norm((R * 0.50) + (U * 0.80) + (F * 0.20), U)
	if t > 0.09 then
		local foot = front(width * 0.18, 1) + (back * 0.45) + (U * ((1 - strawIn) * 300 * scale))
		local elbow = foot + (U * (140 * scale))
		nozzle = elbow + (aim * (110 * scale))
		line(foot - (U * (30 * scale * strawIn)), elbow, hr, hg, hb, 24 * scale * alpha)
		line(elbow, nozzle, hr, hg, hb, 24 * scale * alpha)
		for k = 1, 3 do -- stripes
			local stripe = foot + (U * (k * 34 * scale))
			line(stripe - (R * (14 * scale)), stripe + (R * (14 * scale)), r, g, b, 10 * scale * alpha)
		end
	end

	-- juice: one stream per squeeze. A stream is the path of everything squirted between the start
	-- and end of that squeeze, so its front flies out when the squeeze starts and its tail leaves
	-- the straw when the squeeze stops.
	if nozzle ~= nil then
		local gravity = 1500 * scale
		local floorDrop = math.max((nozzle - C):dot(U) - BOTTOM, 10)
		local squirts = { { 0.18 * life, 0.245 * life, 300 * scale }, { 0.32 * life, 0.72 * life, 480 * scale } }
		for index, squirt in ipairs(squirts) do
			local speed = squirt[3]
			local rise = aim:dot(U) * speed
			local flight = (rise + math.sqrt(rise * rise + 2 * gravity * floorDrop)) / gravity -- seconds from straw to floor
			local newest = math.max(age - squirt[2], 0) -- flight time of the juice that left last
			local oldest = math.min(age - squirt[1], flight) -- and of the juice that left first
			local function along(seconds)
				local wobble = 1 + 0.025 * math.sin((age - seconds) * 22)
				return nozzle + (aim * (speed * wobble * seconds)) - (U * (0.5 * gravity * seconds * seconds))
			end
			local landing = nozzle + (aim * (speed * flight)) - (U * (0.5 * gravity * flight * flight))
			if oldest > newest then
				local previous = along(newest)
				for i = 1, 14 do
					local seconds = mix(newest, oldest, i / 14)
					local point = along(seconds)
					line(previous, point, jr, jg, jb, mix(32, 20, seconds / flight) * scale * alpha)
					previous = point
				end
			end
			-- where it lands: droplets hopping away and a spreading puddle
			local landingFor = age - squirt[1] - flight
			if landingFor > 0 then
				local raining = age - squirt[2] < flight
				if raining then
					for i = 1, (if index == 2 then 12 else 5) do
						local seed = p.seed + index * 100 + i * 13
						local cycle = age * 2.2 + hash(seed)
						cycle -= math.floor(cycle)
						local angle = hash(seed + 1) * TAU
						local hop = landing + (((R * math.cos(angle)) + (F * math.sin(angle))) * ((50 + 200 * hash(seed + 2)) * scale * cycle))
							+ (U * (4 * (50 + 110 * hash(seed + 3)) * scale * cycle * (1 - cycle)))
						line(hop, hop + (U * (20 * scale)), jr, jg, jb, 16 * scale * (1 - cycle) * alpha)
					end
				end
				local spread = (if index == 2 then 260 else 90) * scale * clamp01(landingFor / (if index == 2 then 1.1 else 0.3))
				local previous = nil
				for i = 0, 16 do
					local angle = i * TAU / 16
					local point = landing + (R * (math.cos(angle) * spread)) + (F * (math.sin(angle) * spread * 0.7)) + (U * 3)
					if previous ~= nil then line(previous, point, jr, jg, jb, 12 * scale * alpha) end
					previous = point
				end
			end
		end
		if t > 0.72 then -- last drips off the end of the straw
			for k = 0, 1 do
				local cycle = (age - 0.72 * life) * 1.6 + k * 0.5
				cycle -= math.floor(cycle)
				local drip = nozzle - (U * (floorDrop * cycle * cycle))
				line(drip, drip - (U * (26 * scale)), jr, jg, jb, 14 * scale * alpha * (1 - cycle * 0.5))
			end
		end
	end
end

-- LUCKY CAT ----------------------------------------------------------------------------------
-- A big lucky cat (the beckoning cat you see by shop doors) pops up in front of the goal: white,
-- calico patches, red collar with a gold bell, a gold coin held to its chest, and one paw raised
-- that beckons up and down the whole time. Gold coins rain around it and sparkles twinkle in the
-- scorer's colour; it ends with a fountain of coins as the cat ducks back down.
-- Filled like the duck: stacked thick lines, facing the field.
draw["Lucky Cat"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local age = t * p.maxLife
	local white, red, gold, ink, pink = { 0.97, 0.97, 0.94 }, { 0.92, 0.12, 0.12 }, { 1.0, 0.80, 0.14 }, { 0.05, 0.05, 0.06 }, { 1.0, 0.62, 0.72 }
	local patchA, patchB = { 0.95, 0.55, 0.12 }, { 0.16, 0.14, 0.14 }
	local sr, sg, sb = colour(p, ctx.vibrance, 1.2)
	if p.painted then
		-- the whole cat is the paint; collar, bell, coins and face are only a shade lighter
		local r, g, b, hr, hg, hb = palette(p, ctx, 1)
		white, patchA, patchB = { r, g, b }, { r, g, b }, { r, g, b }
		red, gold, ink, pink = { hr, hg, hb }, { hr, hg, hb }, { hr, hg, hb }, { hr, hg, hb }
		sr, sg, sb = r, g, b
	end
	local burstAt, sinkAt = 0.84, 0.90
	local unit = 125 * scale
	local grow = math.max(easeOutBack(t / 0.10), 0.02)
	if t > sinkAt then grow *= 1 - smooth((t - sinkAt) / (1 - sinkAt)) end
	local size = unit * grow
	local origin = C + (F * (340 * scale)) + (U * BOTTOM) -- its feet, on the floor in front of the goal
	local rock = math.sin(age * 2.2) * 0.04
	local cosR, sinR = math.cos(rock), math.sin(rock)
	-- cat coordinates: x to the side, y up from its feet, in units; depth toward the field
	local function at(x, y, depth)
		return origin + (R * ((x * cosR - y * sinR) * size)) + (U * ((x * sinR + y * cosR) * size)) + (F * ((depth or 0) * size))
	end
	local function stroke(x1, y1, x2, y2, depth, tone, width)
		line(at(x1, y1, depth), at(x2, y2, depth), tone[1], tone[2], tone[3], width * size)
	end
	local function blob(cx, cy, rx, ry, rows, depth, tone)
		for i = 0, rows - 1 do
			local v = (i + 0.5) / rows * 2 - 1
			local half = math.sqrt(1 - v * v) * rx
			stroke(cx - half, cy + v * ry, cx + half, cy + v * ry, depth, tone, (2 * ry / rows) * 1.16)
		end
	end

	if grow > 0.03 then
		-- tail, body, feet
		stroke(0.72, 0.36, 1.26, 0.74, -0.05, white, 0.24)
		stroke(1.26, 0.74, 1.14, 1.26, -0.05, white, 0.22)
		blob(0, 0.95, 0.88, 0.95, 9, 0, white)
		blob(-0.45, 0.14, 0.34, 0.16, 2, 0.06, white)
		blob(0.45, 0.14, 0.34, 0.16, 2, 0.06, white)
		-- head, ears, calico patches
		blob(0, 2.28, 0.98, 0.76, 8, 0.02, white)
		for sideSign = -1, 1, 2 do
			for j = 0, 2 do
				local v = (j + 0.5) / 3
				local middle, half = sideSign * (0.60 + 0.10 * v), 0.30 * (1 - v)
				stroke(middle - half, 2.80 + v * 0.55, middle + half, 2.80 + v * 0.55, 0.02, white, 0.55 / 3 * 1.2)
			end
			stroke(sideSign * 0.60, 2.86, sideSign * 0.67, 3.14, 0.05, red, 0.14)
		end
		stroke(-0.72, 2.72, -0.25, 2.72, 0.04, patchA, 0.22)
		stroke(0.30, 2.80, 0.68, 2.80, 0.04, patchB, 0.18)
		-- face: smiling eyes, nose, mouth, whiskers, cheeks
		for sideSign = -1, 1, 2 do
			local eye = sideSign * 0.40
			stroke(eye - 0.16, 2.32, eye, 2.44, 0.08, ink, 0.07)
			stroke(eye, 2.44, eye + 0.16, 2.32, 0.08, ink, 0.07)
			for k = -1, 1 do
				stroke(sideSign * 0.52, 2.12 + k * 0.06, sideSign * 1.14, 2.08 + k * 0.20, 0.08, ink, 0.03)
			end
			stroke(sideSign * 0.56, 2.04, sideSign * 0.70, 2.04, 0.07, pink, 0.13)
			stroke(0, 2.06, sideSign * 0.14, 1.99, 0.08, ink, 0.045)
		end
		stroke(-0.05, 2.17, 0.05, 2.17, 0.09, pink, 0.07)
		stroke(0, 2.14, 0, 2.06, 0.08, ink, 0.045)
		-- collar and bell
		stroke(-0.60, 1.66, 0.60, 1.66, 0.06, red, 0.17)
		stroke(-0.11, 1.50, 0.11, 1.50, 0.10, gold, 0.24)
		stroke(-0.07, 1.45, 0.07, 1.45, 0.12, ink, 0.04)
		-- the coin it holds, and the paw resting on it
		blob(-0.42, 0.95, 0.30, 0.46, 4, 0.10, gold)
		stroke(-0.42, 0.74, -0.42, 1.16, 0.12, ink, 0.04)
		stroke(-0.82, 1.40, -0.52, 1.28, 0.13, white, 0.30)
		-- The beckoning paw. The arm is held out to the side, clear of the head, so the wave reads
		-- from across the arena: the forearm stands straight up beside the ear, then tips forward
		-- and down from the elbow, and comes back up, about 1.4 times a second.
		local beckon = 0.5 - 0.5 * math.cos(age * 8.5)
		local swing = beckon * 1.35 -- radians forward from straight up
		local reach = 1.05
		local pawY, pawDepth = 1.80 + reach * math.cos(swing), 0.14 + reach * math.sin(swing)
		stroke(0.70, 1.42, 1.36, 1.80, 0.10, white, 0.32) -- upper arm
		line(at(1.36, 1.80, 0.12), at(1.36, pawY, pawDepth), white[1], white[2], white[3], 0.34 * size) -- forearm
		line(at(1.12, pawY + 0.06, pawDepth + 0.02), at(1.60, pawY + 0.06, pawDepth + 0.02), white[1], white[2], white[3], 0.46 * size) -- paw
		line(at(1.26, pawY - 0.02, pawDepth + 0.08), at(1.46, pawY - 0.02, pawDepth + 0.08), pink[1], pink[2], pink[3], 0.16 * size) -- pad
		for toe = -1, 1 do
			line(at(1.36 + toe * 0.14, pawY + 0.17, pawDepth + 0.08), at(1.36 + toe * 0.14, pawY + 0.25, pawDepth + 0.08), pink[1], pink[2], pink[3], 0.08 * size)
		end
	end

	if t > 0.10 and t < sinkAt then
		local showing = clamp01((t - 0.10) / 0.04) * clamp01((sinkAt - t) / 0.04)
		-- coins raining down around it, tumbling
		for i = 1, 12 do
			local seed = p.seed + i * 43
			local cycle = age * (0.38 + 0.22 * hash(seed)) + hash(seed + 1)
			cycle -= math.floor(cycle)
			local width = 0.22 * unit * showing
			local spin = math.abs(math.cos(age * 6 + seed))
			local centre = origin + (R * ((hash(seed + 2) - 0.5) * 4.6 * unit)) + (U * ((4.3 - 4.2 * cycle * cycle) * unit)) + (F * ((hash(seed + 3) - 0.5) * 1.6 * unit))
			line(centre - (R * (width * 0.5 * (0.25 + 0.75 * spin))), centre + (R * (width * 0.5 * (0.25 + 0.75 * spin))), gold[1], gold[2], gold[3], width)
		end
		-- sparkles
		local twinkle = math.floor(age * 6)
		for i = 1, 8 do
			local seed = p.seed + 400 + i * 17
			if hash(seed + twinkle * 3) > 0.35 then
				local angle = hash(seed) * TAU
				local reach = (1.7 + 1.1 * hash(seed + 1)) * unit
				local centre = origin + (U * (1.9 * unit)) + (R * (math.cos(angle) * reach)) + (U * (math.sin(angle) * reach * 0.8)) + (F * (0.3 * unit))
				local arm = (0.12 + 0.16 * hash(seed + 2 + twinkle)) * unit
				line(centre - (R * arm), centre + (R * arm), sr, sg, sb, 0.05 * unit * showing)
				line(centre - (U * arm), centre + (U * arm), sr, sg, sb, 0.05 * unit * showing)
			end
		end
	end

	if t >= burstAt then -- a fountain of coins to finish
		local w = (t - burstAt) / (1 - burstAt)
		local out = easeOut(w)
		local from = origin + (U * (2.0 * unit)) + (F * (0.3 * unit))
		if w < 0.6 then
			local radius = easeOut(w / 0.6) * 4.4 * unit
			local previous = nil
			for i = 0, 20 do
				local angle = i * TAU / 20
				local point = from + (R * (math.cos(angle) * radius)) + (U * (math.sin(angle) * radius))
				if previous ~= nil then line(previous, point, gold[1], gold[2], gold[3], 0.22 * unit * (1 - w / 0.6) ^ 2) end
				previous = point
			end
		end
		for i = 1, 36 do
			local seed = p.seed + 900 + i * 29
			local angle, tilt = hash(seed) * TAU, (hash(seed + 1) - 0.5) * 1.6
			local direction = (R * (math.cos(angle) * math.cos(tilt))) + (U * (math.sin(angle) * math.cos(tilt) + 0.45)) + (F * math.sin(tilt))
			local centre = from + (direction * (out * (1.4 + 3.2 * hash(seed + 2)) * unit)) - (U * (2.6 * w * w * unit))
			local width = 0.20 * unit * (1 - w)
			local spin = math.abs(math.cos(age * 7 + seed))
			line(centre - (R * (width * 0.5 * (0.25 + 0.75 * spin))), centre + (R * (width * 0.5 * (0.25 + 0.75 * spin))), gold[1], gold[2], gold[3], width)
		end
	end
end

-- UFO ----------------------------------------------------------------------------------------
-- A flying saucer drops in from high above and stops dead over the goal, where the whole ship is
-- in view. A green beam opens from its belly straight down to where the ball went in. A little
-- cow appears on that spot, lifts off and rides slowly up the beam into the ship, legs kicking;
-- the beam snaps shut, and the saucer tilts and streaks away.
draw["UFO"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local age = t * p.maxLife
	local hull, shade, glass, beam, lamp = { 0.74, 0.77, 0.84 }, { 0.42, 0.45, 0.52 }, { 0.55, 0.92, 1.0 }, { 0.25, 1.0, 0.35 }, { 1.0, 0.90, 0.20 }
	local hide, spots, pink = { 0.97, 0.97, 0.94 }, { 0.07, 0.07, 0.08 }, { 1.0, 0.62, 0.72 } -- the cow
	local tr, tg, tb = colour(p, ctx.vibrance, 1.2) -- scorer's colour: the lamps between the yellow ones
	if p.painted then
		-- the ship, the cow and the beam rings are the paint; beam, lamps, glass and the cow's
		-- spots a shade lighter
		local r, g, b, hr, hg, hb = palette(p, ctx, 1)
		hull, shade, hide = { r, g, b }, { r, g, b }, { r, g, b }
		spots, pink = { hr, hg, hb }, { hr, hg, hb }
		glass, beam, lamp = { hr, hg, hb }, { hr, hg, hb }, { hr, hg, hb }
		tr, tg, tb = r, g, b
	end
	local ringTone = if p.painted then hull else beam
	local arriveEnd, beamOn, liftFrom, liftTo, beamOff, leaveAt = 0.14, 0.22, 0.30, 0.72, 0.80, 0.86
	local unit = 150 * scale
	local hover = C + (F * (200 * scale)) + (U * (TOP + 330 * scale))
	local target = p.impact or (C + (U * MID_Y)) -- where the ball went in

	-- where the ship is, and how far it is banked
	local ship, bank, speeding = hover, 0, nil
	if t < arriveEnd then
		local u = easeOut(t / arriveEnd)
		local from = hover + (U * (2600 * scale)) + (R * (1900 * scale)) - (F * (500 * scale))
		ship, bank, speeding = from + ((hover - from) * u), 0.5 * (1 - u), norm(from - hover, U)
		if u > 0.97 then speeding = nil end
	elseif t > leaveAt then
		local w = (t - leaveAt) / (1 - leaveAt)
		local away = norm((U * 0.45) - (R * 0.85) + (F * 0.2), U)
		ship, bank, speeding = hover + (away * (5200 * scale * w * w)), -0.6 * math.min(w * 4, 1), away * -1
	else
		ship = hover + (U * (math.sin(age * 3) * 10 * scale)) + (R * (math.sin(age * 1.7) * 14 * scale))
		bank = math.sin(age * 2.2) * 0.06
	end
	local cosB, sinB = math.cos(bank), math.sin(bank)
	local function at(x, y, depth)
		return ship + (R * ((x * cosB - y * sinB) * unit)) + (U * ((x * sinB + y * cosB) * unit)) + (F * ((depth or 0) * unit))
	end
	local function stroke(x1, y1, x2, y2, depth, tone, width)
		line(at(x1, y1, depth), at(x2, y2, depth), tone[1], tone[2], tone[3], width * unit)
	end

	local glow = clamp01((t - beamOn) / 0.08) * clamp01((beamOff - t) / 0.08) -- how open the beam is
	-- glass dome
	for i = 0, 3 do
		local v = (i + 0.5) / 4
		stroke(-0.62 * math.sqrt(1 - v * v), 0.12 + v * 0.50, 0.62 * math.sqrt(1 - v * v), 0.12 + v * 0.50, -0.02, glass, 0.50 / 4 * 1.16)
	end
	-- hull: a lens, widest in the middle
	for i = 0, 4 do
		local v = (i + 0.5) / 5 * 2 - 1
		local half = 1.25 * (1 - 0.78 * math.abs(v) ^ 1.6)
		stroke(-half, -0.04 + v * 0.18, half, -0.04 + v * 0.18, 0, if i == 2 then hull else shade, 0.36 / 5 * 1.18)
	end
	stroke(-0.45, -0.27, 0.45, -0.27, 0.01, shade, 0.10)
	stroke(-0.20, -0.36, 0.20, -0.36, 0.02, if glow > 0 then beam else shade, 0.09)
	-- running lamps round the rim
	local chase = math.floor(age * 8)
	for k = -3, 3 do
		local lit = (k + chase) % 3 == 0
		local x = k / 3 * 1.08
		line(at(x - 0.055, -0.04, 0.06), at(x + 0.055, -0.04, 0.06), if lit then lamp[1] else tr, if lit then lamp[2] else tg, if lit then lamp[3] else tb, 0.11 * unit)
	end
	if speeding ~= nil then -- speed streaks behind it on the way in and out
		for i = -2, 2 do
			local start = at(i * 0.45, 0.05)
			line(start + (speeding * (120 * scale)), start + (speeding * ((500 + 160 * math.abs(i)) * scale)), glass[1], glass[2], glass[3], 6 * scale)
		end
	end

	-- the beam, the rings running up it, and the ball it takes
	local emitter = at(0, -0.42)
	if glow > 0 then
		local axis = norm(emitter - target, U)
		local side = norm(R - (axis * R:dot(axis)), R)
		local depth = norm(axis:cross(side), F)
		local wide, narrow = 150 * scale * glow, 0.24 * unit * glow
		-- the bright core stops just above the cow while it is in the beam, so it never covers it
		local cowShown = t > beamOn + 0.02 and t < liftTo + 0.02
		local cowLift = smooth((t - liftFrom) / (liftTo - liftFrom))
		local cowBig = mix(105, 46, cowLift) * scale * clamp01((t - beamOn - 0.02) / 0.05)
		local cowAt = target + ((emitter - target) * cowLift)
		local coreEnd = if cowShown then cowAt + (axis * math.min(cowBig * 0.95, (emitter - cowAt):length())) else target
		line(emitter, coreEnd, beam[1] * 0.8, beam[2] * 0.8, beam[3] * 0.8, narrow * 1.3)
		line(emitter - (side * narrow), target - (side * wide), beam[1], beam[2], beam[3], 7 * scale)
		line(emitter + (side * narrow), target + (side * wide), beam[1], beam[2], beam[3], 7 * scale)
		for k = 0, 3 do
			local cycle = age * 0.9 + k / 4
			cycle -= math.floor(cycle)
			local centre = target + ((emitter - target) * cycle)
			local width = mix(wide, narrow, cycle)
			local previous = nil
			for i = 0, 10 do
				local angle = i * TAU / 10
				local point = centre + (side * (math.cos(angle) * width)) + (depth * (math.sin(angle) * width))
				if previous ~= nil then line(previous, point, ringTone[1], ringTone[2], ringTone[3], 4 * scale * glow) end
				previous = point
			end
		end
		if cowShown then
			-- the cow: side-on, rocking and kicking its legs as it goes up, smaller as it nears the ship
			local big = cowBig
			local rock = math.sin(age * 1.9) * 0.45
			local cosC, sinC = math.cos(rock), math.sin(rock)
			local function cow(x, y, depth)
				return cowAt + (R * ((x * cosC - y * sinC) * big)) + (U * ((x * sinC + y * cosC) * big)) + (F * (((depth or 0) + 0.3) * big))
			end
			local function part(x1, y1, x2, y2, depth, tone, width)
				line(cow(x1, y1, depth), cow(x2, y2, depth), tone[1], tone[2], tone[3], width * big)
			end
			for i = 0, 2 do -- body
				local y = -0.26 + i * 0.26
				part(-0.80, y, 0.72, y, 0, hide, 0.28)
			end
			part(-0.45, 0.08, -0.05, 0.08, 0.04, spots, 0.36) -- spots
			part(0.22, -0.14, 0.50, -0.14, 0.04, spots, 0.26)
			part(0.72, 0.30, 1.16, 0.30, 0.02, hide, 0.40) -- head
			part(1.10, 0.22, 1.30, 0.22, 0.05, pink, 0.24) -- muzzle
			part(0.92, 0.38, 0.98, 0.38, 0.06, spots, 0.07) -- eye
			part(0.74, 0.52, 0.62, 0.66, 0.02, hide, 0.10) -- ear
			part(0.84, 0.52, 0.86, 0.72, 0.03, pink, 0.06) -- horn
			part(1.00, 0.52, 1.04, 0.72, 0.03, pink, 0.06)
			part(-0.80, 0.16, -1.08, -0.10 + math.sin(age * 9) * 0.12, 0, hide, 0.07) -- tail
			part(-0.10, -0.46, 0.14, -0.46, 0.03, pink, 0.16) -- udder
			for leg = 0, 3 do
				local x = -0.62 + leg * 0.40
				local kick = math.sin(age * 11 + leg * 1.7) * 0.22
				part(x, -0.36, x + kick, -0.86, 0.01, hide, 0.13)
				part(x + kick, -0.86, x + kick + 0.03, -0.96, 0.02, spots, 0.14) -- hoof
			end
		end
	end
	if t > liftTo and t < liftTo + 0.06 then -- the cow goes in
		local flash = 1 - (t - liftTo) / 0.06
		for i = 0, 1 do
			local direction = if i == 0 then R else U
			line(emitter - (direction * (0.9 * unit * flash)), emitter + (direction * (0.9 * unit * flash)), lamp[1], lamp[2], lamp[3], 0.10 * unit * flash)
		end
	end
end

-- GUNSLINGER ---------------------------------------------------------------------------------
-- A ten-gallon hat drops in over the goal with a gloved hand either side, each twirling a
-- revolver. Then the bang-bang dance: the hat sways and bobs to the beat while the guns go off
-- left-right, left-right, then both straight up together, each shot with a muzzle flash, a
-- tracer, a smoke ring and a "BANG!". A last twirl, and they drop out of shot.
-- (Lettering is laid out left-to-right as seen from the field, which is the goal's own right-to-left.)
local BANG = {
	{ 0, 0, 0, 1 }, { 0, 1, 0.6, 0.85 }, { 0.6, 0.85, 0, 0.5 }, { 0, 0.5, 0.7, 0.25 }, { 0.7, 0.25, 0, 0 }, -- B
	{ 1, 0, 1.4, 1 }, { 1.4, 1, 1.8, 0 }, { 1.2, 0.45, 1.6, 0.45 }, -- A
	{ 2, 0, 2, 1 }, { 2, 1, 2.7, 0 }, { 2.7, 0, 2.7, 1 }, -- N
	{ 3.75, 0.85, 3.35, 1 }, { 3.35, 1, 3, 0.5 }, { 3, 0.5, 3.35, 0 }, { 3.35, 0, 3.75, 0.2 }, { 3.75, 0.2, 3.75, 0.5 }, { 3.75, 0.5, 3.45, 0.5 }, -- G
	{ 4.2, 1, 4.2, 0.35 }, { 4.2, 0.12, 4.2, 0 }, -- !
}

draw["Gunslinger"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local X = R * -1 -- "to the right" as seen from the field
	local scale = ctx.scale
	local age = t * p.maxLife
	local felt, crown, steel, barrelTone, skin, wood, gold, smoke, ink = { 0.50, 0.30, 0.13 }, { 0.62, 0.38, 0.17 }, { 0.36, 0.38, 0.44 }, { 0.62, 0.65, 0.72 }, { 0.93, 0.76, 0.55 }, { 0.45, 0.24, 0.10 }, { 1.0, 0.85, 0.20 }, { 0.72, 0.72, 0.74 }, { 1.0, 0.95, 0.60 }
	local br, bg, bb = colour(p, ctx.vibrance, 1.25) -- hat band and lettering: the scorer's colour
	if p.painted then
		-- hat, hands, guns, smoke and lettering are the paint; band, badge and flashes a shade lighter
		local r, g, b, hr, hg, hb = palette(p, ctx, 1)
		felt, crown, steel, barrelTone, skin, wood, smoke = { r, g, b }, { r, g, b }, { r, g, b }, { r, g, b }, { r, g, b }, { r, g, b }, { r, g, b }
		gold, ink = { hr, hg, hb }, { hr, hg, hb }
		br, bg, bb = r, g, b
	end
	local danceFrom, danceTo, leaveAt = 0.12, 0.80, 0.90
	local unit = 115 * scale
	local beat = 0.4 -- seconds
	local dancing = math.clamp(age - danceFrom * p.maxLife, 0, (danceTo - danceFrom) * p.maxLife)
	local onStage = t > danceFrom and t < danceTo
	local sway = if onStage then math.sin(dancing * math.pi / (beat * 2)) else 0
	local bob = if onStage then math.abs(math.sin(dancing * math.pi / beat)) * 0.12 else 0
	local drop = (1 - easeOutBack(t / 0.10)) * 3.2 -- falls in from above
	local gone = if t > leaveAt then smooth((t - leaveAt) / (1 - leaveAt)) else 0
	local size = unit * (1 - gone)
	local stage = C + (F * (320 * scale)) + (U * (TOP + 40 * scale)) + (U * ((bob + drop - gone * 2.5) * unit)) + (X * (sway * 0.22 * unit))
	if size < unit * 0.03 then return end

	-- hat (tilts with the sway)
	local tilt = sway * 0.14
	local cosT, sinT = math.cos(tilt), math.sin(tilt)
	local function hat(x, y, depth)
		return stage + (X * ((x * cosT - y * sinT) * size)) + (U * ((x * sinT + y * cosT) * size)) + (F * ((depth or 0) * size))
	end
	local brim = { { -1.55, 0.18 }, { -1.10, -0.02 }, { -0.50, -0.08 }, { 0.50, -0.08 }, { 1.10, -0.02 }, { 1.55, 0.18 } }
	for i = 1, #brim - 1 do
		line(hat(brim[i][1], brim[i][2]), hat(brim[i + 1][1], brim[i + 1][2]), felt[1], felt[2], felt[3], 0.20 * size)
	end
	for i = 0, 4 do
		local v = (i + 0.5) / 5
		local half, y = mix(0.74, 0.58, v), 0.05 + v * 0.90
		if i == 4 then -- the crease along the top
			line(hat(-half, y, 0.02), hat(-0.08, y, 0.02), crown[1], crown[2], crown[3], 0.90 / 5 * 1.16 * size)
			line(hat(0.08, y, 0.02), hat(half, y, 0.02), crown[1], crown[2], crown[3], 0.90 / 5 * 1.16 * size)
		else
			line(hat(-half, y, 0.02), hat(half, y, 0.02), crown[1], crown[2], crown[3], 0.90 / 5 * 1.16 * size)
		end
	end
	line(hat(-0.75, 0.16, 0.05), hat(0.75, 0.16, 0.05), br, bg, bb, 0.16 * size)
	line(hat(-0.12, 0.16, 0.08), hat(0.12, 0.16, 0.08), gold[1], gold[2], gold[3], 0.07 * size)
	line(hat(0, 0.05, 0.08), hat(0, 0.27, 0.08), gold[1], gold[2], gold[3], 0.07 * size)

	-- when each gun last fired: bars of two beats; left then right, and every third bar both
	-- guns twice, pointing straight up
	local bar = beat * 2
	local function lastShot(gun)
		local best, together = nil, false
		for b = math.floor(dancing / bar), math.floor(dancing / bar) - 1, -1 do
			if b >= 0 and best == nil then
				local both = b % 3 == 2
				local times = if both then { 0.2, 0 } elseif gun == 1 then { 0 } else { 0.2 }
				for _, offset in ipairs(times) do
					local when = b * bar + offset
					if when <= dancing and best == nil then best, together = dancing - when, both end
				end
			end
		end
		return best, together
	end
	local upBar = math.floor(dancing / bar) % 3 == 2

	for gun = 1, 2 do
		local sideSign = if gun == 1 then -1 else 1 -- 1 = left as seen from the field
		local since, together = nil, false
		if onStage then since, together = lastShot(gun) end
		local aim = if onStage and upBar then 1.5708 else 1.13 -- radians above "straight out sideways"
		if since ~= nil then aim += 0.6 * math.exp(-since * 14) end -- recoil
		if t < danceFrom then aim += (1 - t / danceFrom) * TAU * 2 end -- twirl on the way in
		if t > danceTo then aim += smooth((t - danceTo) / (leaveAt - danceTo)) * TAU * 2 end -- and before leaving
		local swing = if onStage then math.sin(dancing * math.pi / beat + (if gun == 1 then 0 else math.pi)) * 0.20 else 0
		local hand = stage + (X * (sideSign * 1.75 * size)) + (U * ((-1.00 + swing) * size)) - (X * (sway * 0.22 * unit))
		local direction = (X * (sideSign * math.cos(aim))) + (U * math.sin(aim))
		local across = (X * (sideSign * -math.sin(aim))) + (U * math.cos(aim))
		-- gloved fist
		for i = 0, 2 do
			local y = (i - 1) * 0.14
			line(hand - (X * (0.21 * size)) + (U * (y * size)), hand + (X * (0.21 * size)) + (U * (y * size)), skin[1], skin[2], skin[3], 0.15 * size)
		end
		-- revolver: grip, cylinder, barrel
		local front = F * (0.06 * size)
		line(hand + front, hand + front - (direction * (0.10 * size)) - (across * (0.34 * size)), wood[1], wood[2], wood[3], 0.17 * size)
		line(hand + front + (direction * (0.08 * size)), hand + front + (direction * (0.46 * size)), steel[1], steel[2], steel[3], 0.30 * size)
		local tip = hand + front + (direction * (1.15 * size))
		line(hand + front + (direction * (0.46 * size)), tip, barrelTone[1], barrelTone[2], barrelTone[3], 0.14 * size)
		if since ~= nil then
			if since < 0.10 then -- muzzle flash
				local flash = 1 - since / 0.10
				for i = -2, 2 do
					local spread = (direction * math.cos(i * 0.5)) + (across * math.sin(i * 0.5))
					line(tip, tip + (spread * ((0.35 + 0.25 * (2 - math.abs(i))) * size * flash)), gold[1], gold[2], gold[3], 0.09 * size * flash)
				end
			end
			if since < 0.14 then -- tracer
				local far = since / 0.14 * 1500 * scale
				line(tip + (direction * (far * 0.7)), tip + (direction * far), ink[1], ink[2], ink[3], 5 * scale)
			end
			if since < 0.70 then -- smoke ring drifting up off the muzzle
				local s = since / 0.70
				local centre = tip + (U * (0.9 * size * s)) + (direction * (0.15 * size))
				local radius = (0.12 + 0.45 * s) * size
				local previous = nil
				for i = 0, 6 do
					local angle = i * TAU / 6
					local point = centre + (X * (math.cos(angle) * radius)) + (U * (math.sin(angle) * radius * 0.6))
					if previous ~= nil then line(previous, point, smoke[1], smoke[2], smoke[3], 0.05 * size * (1 - s)) end
					previous = point
				end
			end
			if since < 0.40 and (gun == 1 or not together) then -- BANG!
				local pop = easeOutBack(since / 0.10) * clamp01((0.40 - since) / 0.10)
				local letter = 0.36 * size * pop
				local lean = sideSign * 0.16
				local cosL, sinL = math.cos(lean), math.sin(lean)
				local middle = if together then stage + (U * (1.9 * size)) else tip + (U * (0.75 * size)) + (X * (sideSign * 0.35 * size))
				for _, strokeData in ipairs(BANG) do
					local x1, y1, x2, y2 = strokeData[1] - 2.1, strokeData[2] - 0.5, strokeData[3] - 2.1, strokeData[4] - 0.5
					line(middle + (X * ((x1 * cosL - y1 * sinL) * letter)) + (U * ((x1 * sinL + y1 * cosL) * letter)) + (F * (0.1 * size)),
						middle + (X * ((x2 * cosL - y2 * sinL) * letter)) + (U * ((x2 * sinL + y2 * cosL) * letter)) + (F * (0.1 * size)),
						if p.painted then br else ink[1], if p.painted then bg else ink[2], if p.painted then bb else ink[3], 0.07 * size)
				end
			end
		end
	end
end

-- AIRSTRIKE (ball spot) ----------------------------------------------------------------------
-- A targeting reticle snaps onto the ball itself, wherever it ended up (it may sit partly inside
-- the net: that is fine), closes, blinks faster and locks. The strike it calls in lands level with
-- the ball (same side of the goal, same height) but out in front of the goal line, so the net and
-- the goal never hide the explosions. Three missiles come down out of the sky one after another on smoke trails and hit the
-- mark: each a fireball that swells and burns down from white-hot to smoke, with a shock ring
-- along the floor, a burst of spikes and debris thrown clear. The last one is the biggest.
draw["Airstrike"] = function(p, t, fade, line, ctx)
	local T, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	-- The reticle stays on the ball. The ball usually ends up deep inside the goal, so the missiles
	-- and explosions land at least 320 (x scale) out in front of the goal line, level with it.
	local ballSpot = T
	if p.goalOrigin ~= nil then
		local out = (T - p.goalOrigin):dot(F)
		if out == out and out < 320 * scale then T = T + (F * (320 * scale - out)) end
	end
	local age = t * p.maxLife
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.3)
	local painted = p.painted == true
	-- colour of something burning: 1 = just lit, 0 = burnt out
	local function heat(f)
		if painted then
			if f > 0.6 then return hr, hg, hb end
			return r, g, b
		end
		if f > 0.80 then return 1, 0.95, 0.70 end
		if f > 0.55 then return 1, 0.75, 0.15 end
		if f > 0.30 then return 1, 0.40, 0.05 end
		if f > 0.12 then return 0.75, 0.12, 0.03 end
		return 0.26, 0.23, 0.23
	end
	local markR, markG, markB = 1.0, 0.15, 0.10 -- the reticle is red
	local bodyR, bodyG, bodyB = 0.88, 0.90, 0.94 -- missile body
	local smokeR, smokeG, smokeB = 0.55, 0.55, 0.58
	if painted then
		markR, markG, markB = r, g, b -- a paint colour paints the reticle and the missiles too
		bodyR, bodyG, bodyB = r, g, b
		smokeR, smokeG, smokeB = r, g, b
	end
	local lockAt = 0.26
	local hits = { 0.38, 0.47, 0.56 } -- when each missile lands (fraction of the effect's life)
	local flight = 0.16

	-- reticle: closes on the spot, blinks faster and faster, then locks solid
	if t < hits[1] + 0.04 then
		local closing = smooth(t / lockAt)
		local locked = t >= lockAt
		local blink = age * (4 + 12 * closing)
		local bright = locked or (blink - math.floor(blink)) < 0.6 -- blinking: thin and thick, never gone
		local gone = clamp01((t - hits[1]) / 0.04)
		if gone < 1 then
			local outer = mix(330, 160, closing) * scale
			local turn = age * 1.5
			local width = (if locked then 12 elseif bright then 8 else 3.5) * scale * (1 - gone)
			for i = 0, 19 do -- outer ring, broken into four arcs
				if i % 5 ~= 4 then
					local a1, a2 = i * TAU / 20 + turn, (i + 1) * TAU / 20 + turn
					line(ballSpot + (R * (math.cos(a1) * outer)) + (U * (math.sin(a1) * outer)), ballSpot + (R * (math.cos(a2) * outer)) + (U * (math.sin(a2) * outer)), markR, markG, markB, width)
				end
			end
			local previous = nil
			for i = 0, 12 do -- inner ring
				local angle = i * TAU / 12 - turn
				local point = ballSpot + (R * (math.cos(angle) * outer * 0.42)) + (U * (math.sin(angle) * outer * 0.42))
				if previous ~= nil then line(previous, point, markR, markG, markB, width * 0.7) end
				previous = point
			end
			for i = 0, 3 do -- cross-hair ticks
				local angle = i * TAU / 4
				local direction = (R * math.cos(angle)) + (U * math.sin(angle))
				line(ballSpot + (direction * (outer * 0.58)), ballSpot + (direction * (outer * 1.28)), markR, markG, markB, width)
			end
			line(ballSpot - (R * (9 * scale)), ballSpot + (R * (9 * scale)), markR, markG, markB, 18 * scale * (1 - gone))
		end
	end

	local floorAt = p.ground or (T - (U * 40))
	for index, hitAt in ipairs(hits) do
		local sideSign = if index == 2 then 1 else -1
		local mark = T
		if index == 2 then mark = T + (R * (190 * scale)) + (U * (30 * scale)) end
		if index == 3 then mark = T - (R * (170 * scale)) end
		local under = (mark - floorAt):dot(U)
		if under < 0 then mark = mark - (U * under) end -- never below the floor
		local fromSky = norm((U * 0.75) + (F * 0.60) + (R * (sideSign * 0.45)), U)
		local launch = mark + (fromSky * (3400 * scale))

		-- the missile and its smoke
		local u = (t - (hitAt - flight)) / flight
		if u > 0 and t < hitAt + 0.10 then
			local flying = u < 1
			local along = clamp01(u) ^ 1.5
			local nose = launch + ((mark - launch) * along)
			if flying then
				local tail = nose + (fromSky * (95 * scale))
				line(nose, tail, bodyR, bodyG, bodyB, 20 * scale)
				line(nose - (fromSky * (30 * scale)), nose, markR, markG, markB, 15 * scale)
				local across = norm(fromSky:cross(F), R)
				line(tail - (across * (26 * scale)), tail + (across * (26 * scale)), bodyR, bodyG, bodyB, 9 * scale)
				local burn = (70 + 50 * hash(p.seed + index * 7 + math.floor(age * 30))) * scale
				local fr, fg, fb = heat(0.7)
				line(tail, tail + (fromSky * burn), fr, fg, fb, 13 * scale)
			end
			local linger = if flying then 1 else 1 - (t - hitAt) / 0.10
			for k = 1, 8 do
				local back = along - k * 0.055
				if back > 0 then
					local puff = launch + ((mark - launch) * back) + (U * (k * 5 * scale))
					line(puff, puff + (fromSky * (38 * scale)), smokeR, smokeG, smokeB, (9 + 3 * k) * scale * linger * (1 - k / 10))
				end
			end
		end

		-- the explosion
		local length = if index == 3 then 0.44 else 0.36
		local e = (t - hitAt) / length
		if e >= 0 and e < 1 then
			local reach = (if index == 3 then 370 elseif index == 2 then 280 else 250) * scale
			local swell = easeOut(e / 0.35) * (if e > 0.72 then 1 - 0.5 * (e - 0.72) / 0.28 else 1)
			local radius = reach * swell
			local centre = mark + (U * (140 * e * scale))
			for i = 0, 10 do -- fireball
				local v = (i + 0.5) / 11 * 2 - 1
				local half = math.sqrt(1 - v * v) * radius
				local fr, fg, fb = heat(clamp01((1 - e) * 1.15 - math.abs(v) * 0.25))
				line(centre - (R * half) + (U * (v * radius)), centre + (R * half) + (U * (v * radius)), fr, fg, fb, (2 * radius / 11) * 1.16 * (if e > 0.72 then 1 - 0.75 * (e - 0.72) / 0.28 else 1))
			end
			if e < 0.40 then -- white-hot core
				local core = radius * 0.5 * (1 - e / 0.40)
				for i = 0, 2 do
					local v = (i + 0.5) / 3 * 2 - 1
					local half = math.sqrt(1 - v * v) * core
					local fr, fg, fb = heat(1)
					line(centre - (R * half) + (U * (v * core)) + (F * (12 * scale)), centre + (R * half) + (U * (v * core)) + (F * (12 * scale)), fr, fg, fb, (2 * core / 3) * 1.16)
				end
			end
			if e < 0.30 then -- spikes
				local fr, fg, fb = heat(1)
				for i = 1, 12 do
					local angle = i * TAU / 12 + hash(p.seed + index * 31 + i) * 0.4
					local direction = (R * math.cos(angle)) + (U * math.sin(angle))
					line(centre + (direction * (radius * 0.9)), centre + (direction * (radius * (1.3 + 0.5 * hash(p.seed + index * 53 + i)))), fr, fg, fb, 11 * scale * (1 - e / 0.30))
				end
			end
			if e < 0.50 then -- shock ring along the floor
				local ring = reach * 2.3 * easeOut(e / 0.50)
				local previous = nil
				for i = 0, 16 do
					local angle = i * TAU / 16
					local point = mark + (R * (math.cos(angle) * ring)) + (F * (math.sin(angle) * ring))
					if previous ~= nil then line(previous, point, hr, hg, hb, 13 * scale * (1 - e / 0.50) ^ 2) end
					previous = point
				end
			end
			for i = 1, 10 do -- debris
				local seed = p.seed + index * 200 + i * 17
				local angle, tilt = hash(seed) * TAU, hash(seed + 1) * 1.2
				local direction = (R * (math.cos(angle) * math.cos(tilt))) + (U * (math.sin(tilt) + 0.3)) + (F * (math.sin(angle) * math.cos(tilt)))
				local distance = easeOut(e) * reach * (1.2 + 1.3 * hash(seed + 2))
				local point = mark + (direction * distance) - (U * (520 * e * e * scale))
				local fr, fg, fb = heat(0.65 - e * 0.5)
				line(point - (direction * (distance * 0.14)), point, fr, fg, fb, 9 * scale * (1 - e))
			end
		end
	end
end

-- ZERO-G BATTLE ------------------------------------------------------------------------------
-- The goal is the enemy's gate in a zero-gravity battle room. Its frame lights up, with cubes
-- hanging in the air in front of it and four defenders floating on guard. Five attackers in the
-- scorer's colour dive at it feet first, as if the gate were straight down. Their flashes freeze
-- the defenders one by one (they go white and rigid and drift off). Four attackers touch the four
-- corners of the gate, the fifth goes through the middle, and the gate floods with light.
-- (An original scene on that theme. No names, logos or designs from any book or film are used.)
draw["Zero-G Battle"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local age = t * p.maxLife
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.3)
	local foe = { 1.0, 0.55, 0.15 } -- the defending army
	if p.r > 0.75 and p.g > 0.25 and p.b < 0.35 then foe = { 0.25, 0.60, 1.0 } end -- (scorer is orange: defenders in blue)
	local ice, block = { 0.80, 0.95, 1.0 }, { 0.36, 0.42, 0.58 }
	if p.painted then foe, ice, block = { hr, hg, hb }, { hr, hg, hb }, { r, g, b } end
	local flyFrom, cornersAt, flareAt = 0.12, 0.62, 0.72
	local function at(x, y, f) return C + (R * x) + (U * y) + (F * f) end

	-- the gate
	local power = clamp01(t / 0.10)
	local flare = if t >= flareAt then (t - flareAt) / (1 - flareAt) else 0
	local pulse = 0.75 + 0.25 * math.sin(age * 6)
	outline(p, line, r, g, b, (10 + 14 * clamp01(flare * 4)) * scale * power * pulse * clamp01((1 - t) / 0.08), 4, 1.0)
	outline(p, line, hr, hg, hb, 4 * scale * power, 8, 1.06)

	-- cubes hanging in the room (they are blown outward when the gate goes)
	local cubes = { { -360, 230, 330 }, { 330, 60, 420 }, { -150, 400, 520 }, { 430, 330, 260 }, { -470, 30, 480 }, { 90, 470, 360 } }
	for index, cube in ipairs(cubes) do
		local push = flare * flare * 900
		local centre = at((cube[1] + (if cube[1] < 0 then -push else push)) * scale, (cube[2] + push * 0.5 + math.sin(age * 0.9 + index) * 14) * scale, cube[3] * scale)
		local half = (34 + 8 * (index % 3)) * scale * power * clamp01((1 - t) / 0.06)
		for i = 0, 2 do -- front face
			local y = (i - 1) * half * 0.66
			line(centre - (R * half) + (U * y), centre + (R * half) + (U * y), block[1], block[2], block[3], half * 0.70)
		end
		local lift = (U * (half * 1.2)) - (F * (half * 0.5))
		line(centre - (R * half) + lift, centre + (R * half) + lift, mix(block[1], hr, 0.35), mix(block[2], hg, 0.35), mix(block[3], hb, 0.35), half * 0.45) -- top
	end

	-- a soldier: head, body, two arms, two legs. `feet` is the direction the feet point.
	local function soldier(where, feet, tone, size, rigid)
		local side = norm(feet:cross(F), R)
		local spread = if rigid then 1.5 else 1
		line(where - (feet * (16 * size)), where + (feet * (16 * size)), tone[1], tone[2], tone[3], 15 * size) -- body
		line(where - (feet * (33 * size)) - (side * (7 * size)), where - (feet * (33 * size)) + (side * (7 * size)), tone[1], tone[2], tone[3], 15 * size) -- helmet
		for sign = -1, 1, 2 do
			line(where - (feet * (10 * size)), where - (feet * ((if rigid then 20 else 2) * size)) + (side * (sign * 24 * spread * size)), tone[1], tone[2], tone[3], 7 * size) -- arm
			line(where + (feet * (16 * size)), where + (feet * (46 * size)) + (side * (sign * 9 * spread * spread * size)), tone[1], tone[2], tone[3], 8 * size) -- leg
		end
	end
	local size = 1.7 * scale

	-- defenders: on guard until they are frozen, then stiff and drifting
	local guards = { { -190, 70, 270, 0.22 }, { 200, 160, 310, 0.32 }, { -50, 270, 230, 0.42 }, { 130, 0, 350, 0.52 } }
	local guardAt = {}
	for index, guard in ipairs(guards) do
		local frozen = t >= guard[4]
		local drift = if frozen then (t - guard[4]) else 0
		local where = at((guard[1] + drift * 260 * (if guard[1] < 0 then -1 else 1)) * scale, (guard[2] + drift * 220 + (if frozen then 0 else math.sin(age * 2 + index) * 10)) * scale, (guard[3] - drift * 150) * scale)
		guardAt[index] = where
		local lean = if frozen then drift * 2.2 + index else math.sin(age * 1.5 + index) * 0.2
		local feet = norm((U * -math.cos(lean)) + (R * math.sin(lean)), U * -1)
		if t < flareAt + 0.06 then soldier(where, feet, if frozen then ice else foe, size * power, frozen) end
	end

	-- attackers: four for the corners, one for the middle
	local corners = { { -SHOULDER_X, TOP - 14 }, { SHOULDER_X, TOP - 14 }, { -HALF_W + 16, BOTTOM + 30 }, { HALF_W - 16, BOTTOM + 30 }, { 0, MID_Y } }
	for index, corner in ipairs(corners) do
		local delay = (index - 1) * 0.018
		local u = clamp01((t - flyFrom - delay) / (cornersAt - flyFrom - 0.02))
		local glide = smooth(u)
		local start = at(((index - 3) * 200) * scale, (330 + (index % 2) * 130) * scale, 700 * scale)
		local finish = at(corner[1], corner[2], if index == 5 then 30 else 26)
		local weave = math.sin(u * math.pi) * (if index % 2 == 0 then 1 else -1) * 150 * scale
		local where = start + ((finish - start) * glide) + (R * weave) + (U * (math.sin(u * math.pi) * 90 * scale))
		if index == 5 and t > cornersAt + 0.06 then -- the runner goes through the gate
			where = finish - (F * (smooth((t - cornersAt - 0.06) / 0.08) * 420 * scale))
		end
		if t > flyFrom + delay and t < flareAt + 0.10 then
			-- feet first, diving at the gate as if it were straight down (pitched so the body is seen side-on)
			soldier(where, norm((F * -0.55) - (U * 0.83), U * -1), { r, g, b }, size * clamp01((t - flyFrom - delay) / 0.03), false)
		end
		-- a corner lights up when its attacker gets there
		if index <= 4 and t >= cornersAt + (index - 1) * 0.025 then
			local lit = clamp01((t - cornersAt - (index - 1) * 0.025) / 0.03) * clamp01((1 - t) / 0.1)
			local spot = at(corner[1], corner[2], 12)
			line(spot - (R * (22 * scale)), spot + (R * (22 * scale)), hr, hg, hb, 44 * scale * lit)
		end
		-- the flash that freezes a defender
		local guard = guards[((index - 1) % 4) + 1]
		local sinceShot = t - guard[4]
		if index <= 4 and sinceShot >= 0 and sinceShot < 0.035 then
			local target = guardAt[((index - 1) % 4) + 1]
			line(where, target, hr, hg, hb, 6 * scale * (1 - sinceShot / 0.035))
			for i = 0, 2 do
				local angle = i * math.pi / 3
				local direction = (R * math.cos(angle)) + (U * math.sin(angle))
				line(target - (direction * (40 * scale)), target + (direction * (40 * scale)), ice[1], ice[2], ice[3], 6 * scale * (1 - sinceShot / 0.035))
			end
		end
	end

	-- the gate goes: light floods it from the bottom up, and rays burst off the frame
	if t >= flareAt then
		local rows = 8
		local dim = clamp01((1 - flare) / 0.55)
		for i = 0, rows - 1 do
			if (i + 0.5) / rows <= flare / 0.22 then
				local y = BOTTOM + (i + 0.5) * (TOP - BOTTOM) / rows
				local half = HALF_W
				if y > SHOULDER_Y then half = mix(HALF_W, SHOULDER_X, clamp01((y - SHOULDER_Y) / (TOP - SHOULDER_Y))) end
				line(at(-half, y, 6), at(half, y, 6), mix(r, hr, 0.5), mix(g, hg, 0.5), mix(b, hb, 0.5), (TOP - BOTTOM) / rows * 1.14 * dim)
			end
		end
		local out = easeOut(flare / 0.7)
		for i = 1, 24 do
			local angle = i * TAU / 24
			local direction = (R * math.cos(angle)) + (U * math.sin(angle))
			local from = at(math.cos(angle) * HALF_W, MID_Y + math.sin(angle) * (TOP - BOTTOM) * 0.5, 10)
			line(from + (direction * (out * 120 * scale)), from + (direction * (out * (380 + 260 * hash(p.seed + i)) * scale)), hr, hg, hb, 10 * scale * (1 - flare))
		end
	end
end

-- FIREWORKS ----------------------------------------------------------------------------------
-- Three rockets climb from in front of the goal and burst into drooping, twinkling shells:
-- team colour, a bright white-gold one, and a lighter team tint.
draw["Fireworks"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.2)
	-- second and third shell: white-gold and a light team tint, or shades of the paint colour
	local sr, sg, sb = 1, 0.86, 0.38
	local tr, tg, tb = mix(r, 1, 0.55), mix(g, 1, 0.55), mix(b, 1, 0.55)
	local trailR, trailG, trailB = 1, 0.9, 0.6
	if p.painted then
		sr, sg, sb = r, g, b
		tr, tg, tb = mix(r, hr, 0.5), mix(g, hg, 0.5), mix(b, hb, 0.5)
		trailR, trailG, trailB = hr, hg, hb
	end
	local shells = {
		-- Kept low and compact so a cast framed on the goal still has the whole burst in shot.
		{ at = 0.00, x = -170, height = 300, drift = -45, radius = 190, cr = r, cg = g, cb = b },
		{ at = 0.14, x = 160, height = 370, drift = 50, radius = 220, cr = sr, cg = sg, cb = sb },
		{ at = 0.28, x = -10, height = 335, drift = 10, radius = 205, cr = tr, cg = tg, cb = tb },
	}
	local riseTime, burstTime = 0.20, 0.52
	local streaks = 30
	for index, shell in ipairs(shells) do
		local base = C + (R * (shell.x * scale)) + (U * BOTTOM) + (F * (150 * scale))
		local apex = base + (U * (shell.height * scale)) + (R * (shell.drift * scale))
		local rise = (t - shell.at) / riseTime
		if rise > 0 and rise < 1 then
			local head = base + ((apex - base) * easeOut(rise))
			local tail = base + ((apex - base) * easeOut(math.max(rise - 0.16, 0)))
			local wobble = R * (math.sin(rise * 40 + index) * 6)
			line(tail, head + wobble, trailR, trailG, trailB, 5)
			line(head + wobble, head + wobble + (U * (14 * scale)), hr, hg, hb, 7)
		end
		local burst = (t - shell.at - riseTime) / burstTime
		if burst >= 0 and burst < 1 then
			local radius = shell.radius * scale * (1 - (1 - burst) ^ 3)
			local trailBurst = math.max(burst - 0.10, 0)
			local trailRadius = shell.radius * scale * (1 - (1 - trailBurst) ^ 3)
			local droop = U * (-150 * scale * burst * burst)
			local trailDroop = U * (-150 * scale * trailBurst * trailBurst)
			local thickness = 6.5 * ((1 - burst) ^ 0.7)
			for k = 0, streaks - 1 do
				-- evenly spread directions on a sphere
				local z = 1 - (2 * (k + 0.5) / streaks)
				local ring = math.sqrt(math.max(0, 1 - z * z))
				local angle = k * 2.399963 + index
				local dir = (R * (ring * math.cos(angle))) + (U * z) + (F * (ring * math.sin(angle)))
				local twinkle = burst < 0.6 or hash(p.seed + index * 50 + k + math.floor(burst * 24) * 7) > 0.3
				if twinkle then
					line(apex + (dir * trailRadius) + trailDroop, apex + (dir * radius) + droop, shell.cr, shell.cg, shell.cb, thickness)
				end
			end
			if burst < 0.12 then -- the flash at the moment it pops
				for k = 0, 7 do
					local angle = k * TAU / 8
					local dir = (R * math.cos(angle)) + (U * math.sin(angle))
					line(apex, apex + (dir * (70 * scale)), hr, hg, hb, 6 * (1 - burst / 0.12))
				end
			end
		end
	end
end

-- LIGHTNING STRIKE (ball spot) ---------------------------------------------------------------
-- Three flickering bolts hammer the spot where the ball went in, with side forks and sparks
-- kicked up from the ground. (No rings or ripples spreading out from the ball.)
draw["Lightning Strike"] = function(p, t, fade, line, ctx)
	local T, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.5)
	local age = t * p.maxLife
	local bolts = { { at = 0.00, x = -220, f = 120 }, { at = 0.22, x = 260, f = -60 }, { at = 0.44, x = 30, f = 220 } }
	local window = 0.30
	local points = 10
	for index, bolt in ipairs(bolts) do
		local local_t = (t - bolt.at) / window
		if local_t >= 0 and local_t < 1 then
			local frame = math.floor((age - bolt.at * p.maxLife) / 0.05) -- re-jag the bolt 20 times a second
			local power = ((1 - local_t) ^ 1.5) * (0.6 + 0.4 * hash(p.seed + index * 7 + frame))
			local top = T + (U * (950 * scale)) + (R * (bolt.x * scale)) + (F * (bolt.f * scale))
			local previous = top
			local path = { top }
			for i = 1, points do
				local u = i / points
				local amplitude = 75 * scale * (1 - u * u)
				local seed = p.seed + index * 100 + i * 7 + frame * 13
				local point = top + ((T - top) * u) + (R * ((hash(seed) - 0.5) * 2 * amplitude)) + (F * ((hash(seed + 3) - 0.5) * 2 * amplitude))
				line(previous, point, r, g, b, 12 * power)
				line(previous, point, hr, hg, hb, 4 * power)
				previous = point
				path[i + 1] = point
			end
			for fork = 0, 1 do -- side forks that die out in the air
				local node = path[4 + fork * 3]
				local side = if (index + fork) % 2 == 0 then 1 else -1
				local previousFork = node
				for i = 1, 4 do
					local seed = p.seed + index * 300 + fork * 40 + i * 5 + frame * 11
					local point = previousFork + (R * (side * (55 + hash(seed) * 45) * scale)) + (U * (-(40 + hash(seed + 1) * 50) * scale)) + (F * ((hash(seed + 2) - 0.5) * 80 * scale))
					line(previousFork, point, r, g, b, 6 * power * (1 - i / 5))
					previousFork = point
				end
			end
		end
	end
	if t < 0.62 then -- rain / sparks around the strike
		-- Every streak reaches the floor: it runs from the floor under the strike up to where it
		-- used to stop (a little above the ball's height), however high the ball went in.
		local floorAt = p.ground or T
		local ballHeight = math.max((T - floorAt):dot(U), 0)
		for i = 1, 10 do
			local seed = p.seed + 900 + i * 13 + math.floor(age / 0.07) * 5
			local angle = hash(seed) * TAU
			local distance = (40 + hash(seed + 1) * 200) * scale
			local foot = floorAt + (R * (math.cos(angle) * distance)) + (F * (math.sin(angle) * distance))
			line(foot, foot + (U * (ballHeight + (30 + hash(seed + 2) * 90) * scale)), hr, hg, hb, 3 * (1 - t / 0.62))
		end
	end
end

-- NET RIPPLE ---------------------------------------------------------------------------------
-- The goal becomes a glowing net. It punches back where the ball went in, snaps forward again
-- and sends rings of ripples out to the posts. Lines brighten and thicken where the net moves.
draw["Net Ripple"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local scale = ctx.scale
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.1)
	local age = t * p.maxLife
	local ix, iy = impactPoint(p, 30)
	local cols, rows = 12, 6
	local punch, ripple = 150 * scale, 40 * scale
	local visible = clamp01(t / 0.04) * clamp01((1 - t) / 0.30)
	if visible <= 0.01 then return end

	local function node(col, row)
		local x = -HALF_W + (col / cols) * HALF_W * 2
		local y = BOTTOM + (row / rows) * (topAt(x) - BOTTOM)
		local dx, dy = x - ix, y - iy
		local distance = math.sqrt(dx * dx + dy * dy)
		-- the net is tied to the frame: no movement at the posts, crossbar or goal line
		local edge = clamp01(math.min(HALF_W - math.abs(x), topAt(x) - y, y - BOTTOM) / 60)
		local push = punch * math.exp(-(distance / 135) ^ 2) * math.exp(-2.2 * age) * math.cos(9 * age)
		local wave = 0
		if distance < age * 420 then
			wave = ripple * math.sin(distance * (TAU / 160) - age * TAU * 2.6) * math.exp(-distance / 320) * math.exp(-1.5 * age)
		end
		local depth = (push + wave) * edge
		return C + (R * x) + (U * y) - (F * depth), math.abs(depth)
	end
	local function strand(a, depthA, c, depthC)
		local energy = clamp01((depthA + depthC) * 0.5 / (punch * 0.45))
		line(a, c, mix(r, hr, energy), mix(g, hg, energy), mix(b, hb, energy), (2.4 + 7 * energy) * visible)
	end
	for row = 0, rows do
		local previous, previousDepth = node(0, row)
		for col = 1, cols do
			local point, depth = node(col, row)
			strand(previous, previousDepth, point, depth)
			previous, previousDepth = point, depth
		end
	end
	for col = 0, cols do
		local previous, previousDepth = node(col, 0)
		for row = 1, rows do
			local point, depth = node(col, row)
			strand(previous, previousDepth, point, depth)
			previous, previousDepth = point, depth
		end
	end
	outline(p, line, r, g, b, 6 * visible, 0, 1)
end

-- GLASS SHATTER ------------------------------------------------------------------------------
-- The goal mouth is a pane of glass. Cracks shoot out from where the ball hit, then the pane
-- breaks into shards that tumble out toward the field and fall.
draw["Glass Shatter"] = function(p, t, fade, line, ctx)
	local C, R, U, F = p.center, p.right, p.upDir, p.forward
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.1)
	local gr, gg, gb = mix(hr, r, 0.45), mix(hg, g, 0.45), mix(hb, b, 0.45) -- tinted glass
	if p.painted then gr, gg, gb = r, g, b end -- painted glass is simply the paint colour
	local ix, iy = impactPoint(p, 45)
	local spokes = 12
	local breakAt = 0.28

	-- Corner points of the crack pattern: ring 0 is the impact point, ring 3 the frame.
	local function corner(k, ring)
		k = k % spokes
		if ring == 0 then return ix, iy end
		local angle = (k + (hash(p.seed + k * 3) - 0.5) * 0.5) * TAU / spokes
		local cx, cy = math.cos(angle), math.sin(angle)
		-- distance from the impact point to the frame along this spoke
		local limit = math.huge
		if cx > 0.0001 then limit = math.min(limit, (HALF_W - ix) / cx) elseif cx < -0.0001 then limit = math.min(limit, (-HALF_W - ix) / cx) end
		if cy > 0.0001 then limit = math.min(limit, (TOP - iy) / cy) elseif cy < -0.0001 then limit = math.min(limit, (BOTTOM - iy) / cy) end
		local fraction = 1
		if ring == 1 then fraction = 0.30 + hash(p.seed + k * 5 + 1) * 0.10 end
		if ring == 2 then fraction = 0.62 + hash(p.seed + k * 5 + 2) * 0.12 end
		return ix + cx * limit * fraction, iy + cy * limit * fraction
	end
	local function world(x, y, lift) return C + (R * x) + (U * y) + (F * lift) end

	if t < breakAt then
		local grow = easeOut(t / 0.18) * 3 -- cracks reach ring 1, 2, then the frame
		for k = 0, spokes - 1 do
			for ring = 1, 3 do
				if grow > ring - 1 then
					local ax, ay = corner(k, ring - 1)
					local bx, by = corner(k, ring)
					local part = clamp01(grow - (ring - 1))
					line(world(ax, ay, 6), world(mix(ax, bx, part), mix(ay, by, part), 6), hr, hg, hb, 4.5 - ring * 0.8)
				end
			end
			for ring = 1, 2 do
				if grow > ring + 0.3 then
					local ax, ay = corner(k, ring)
					local bx, by = corner(k + 1, ring)
					line(world(ax, ay, 6), world(bx, by, 6), gr, gg, gb, 2.6)
				end
			end
		end
		if t < 0.10 then -- flash at the impact point
			for k = 0, 5 do
				local angle = k * TAU / 6 + 0.3
				line(world(ix, iy, 10), world(ix + math.cos(angle) * 85, iy + math.sin(angle) * 85, 10), hr, hg, hb, 6 * (1 - t / 0.10))
			end
		end
		outline(p, line, gr, gg, gb, 5, 4, 1)
		return
	end

	local seconds = (t - breakAt) * p.maxLife
	local alpha = clamp01(1 - (t - breakAt) / (1 - breakAt)) ^ 0.8
	for k = 0, spokes - 1 do
		for band = 0, 2 do
			local xs, ys = {}, {}
			if band == 0 then
				xs[1], ys[1] = ix, iy
				xs[2], ys[2] = corner(k, 1)
				xs[3], ys[3] = corner(k + 1, 1)
			else
				xs[1], ys[1] = corner(k, band)
				xs[2], ys[2] = corner(k, band + 1)
				xs[3], ys[3] = corner(k + 1, band + 1)
				xs[4], ys[4] = corner(k + 1, band)
			end
			local count = #xs
			local cx, cy = 0, 0
			for i = 1, count do cx += xs[i]; cy += ys[i] end
			cx, cy = cx / count, cy / count
			local seed = p.seed + k * 29 + band * 131
			local flight = math.max(0, seconds - band * 0.05 - hash(seed) * 0.08) -- inner shards go first
			local away = math.sqrt((cx - ix) ^ 2 + (cy - iy) ^ 2)
			local ox, oy = 0, 1
			if away > 1 then ox, oy = (cx - ix) / away, (cy - iy) / away end
			local speed = 110 + hash(seed + 1) * 210
			local px = cx + ox * speed * flight
			local py = cy + oy * speed * flight - 520 * flight * flight
			local pf = 8 + (240 + hash(seed + 2) * 420) * flight
			-- tumbling: the shard turns edge-on and back, and shrinks as it flies
			local size = math.max(0.22, math.abs(math.cos((2 + hash(seed + 3) * 5) * flight + hash(seed + 4) * 3))) * (1 - 0.45 * clamp01(flight / 1.2))
			local bright = if hash(seed + 5) > 0.7 then 1 else 0.82
			for i = 1, count do
				local j = (i % count) + 1
				local a = world(px + (xs[i] - cx) * size, py + (ys[i] - cy) * size, pf)
				local c = world(px + (xs[j] - cx) * size, py + (ys[j] - cy) * size, pf)
				line(a, c, clamp01(gr * bright), clamp01(gg * bright), clamp01(gb * bright), 3.6 * alpha)
			end
		end
	end
end

-- TORNADO (ball spot) ------------------------------------------------------------------------
-- A spinning funnel twists up around the ball, whipping debris around it, then thins out and
-- lifts away. It always stands ON THE FLOOR, directly under where the ball went in (same side of
-- the goal, same depth), and is always tall enough that the ball is inside the funnel, whether
-- the ball crossed low or right up in the top corner.
draw["Tornado"] = function(p, t, fade, line, ctx)
	local R, U, F = p.right, p.upDir, p.forward
	local scale = ctx.scale
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.15)
	local age = t * p.maxLife
	local base = p.ground or (p.center - (U * 40)) -- p.ground: the floor under the ball spot
	local ballHeight = math.max((p.center - base):dot(U), 0)
	local height = math.max(580 * scale, ballHeight + 150 * scale) * easeOut(t / 0.22)
	local alpha = clamp01((1 - t) / 0.25)
	local spin = 9 * age
	local function funnel(q, angle)
		local radius = (26 + 210 * (q ^ 1.35)) * scale * (1 + 0.08 * math.sin(age * 5 + q * 6))
		local sway = (R * (math.sin(age * 2.1 + q * 2) * 30 * q * scale)) + (F * (math.cos(age * 1.7 + q * 2) * 30 * q * scale))
		return base + (U * (q * height)) + (R * (math.cos(angle) * radius)) + (F * (math.sin(angle) * radius)) + sway
	end
	local segments = 26
	for strandIndex = 0, 2 do
		local previous = nil
		for i = 0, segments do
			local q = i / segments
			local point = funnel(q, strandIndex * TAU / 3 + spin - q * 7)
			if previous ~= nil then
				local glow = (0.25 + 0.5 * q) * (if p.painted then 0.4 else 1) -- painted: the funnel stays the paint colour
				line(previous, point, mix(r, hr, glow), mix(g, hg, glow), mix(b, hb, glow), (3 + 6 * q) * alpha)
			end
			previous = point
		end
	end
	for i = 1, 22 do -- debris swept up and around
		local seed = p.seed + i * 17
		local climb = hash(seed) + age * (0.25 + hash(seed + 1) * 0.3)
		local q = climb - math.floor(climb)
		if q * height > 20 then
			local angle = hash(seed + 2) * TAU + spin * 1.3 - q * 7
			local a = funnel(q, angle)
			local c = funnel(math.min(q + 0.03, 1), angle + 0.28)
			line(a, a + ((c - a) * 1.15), hr, hg, hb, 4 * alpha * (1 - q * 0.5))
		end
	end
	local previous = nil
	local pulse = (60 + 18 * math.sin(age * 12)) * scale
	for i = 0, 16 do -- dust ring at the foot of the funnel
		local angle = i * TAU / 16 + spin * 0.5
		local point = base + (R * (math.cos(angle) * pulse)) + (F * (math.sin(angle) * pulse))
		if previous ~= nil then line(previous, point, r, g, b, 5 * alpha) end
		previous = point
	end
end

-- SLUSHIE ------------------------------------------------------------------------------------
-- A giant frozen slush drink lands on the field in front of the goal. It fills up from a twisting
-- two-flavour stream (one flavour is the scorer's colour) until the slush piles into a swirl, the
-- dome lid drops on and a striped straw jabs in. Then one long slurp: the level sinks, slush
-- races up the straw, the cup shakes. Brain freeze: frost crystals pop out all over it, and the
-- whole thing bursts into slush and snowflakes that arc out and settle.
-- Cup, lid and slush are filled (stacked thick lines) and face the field.
draw["Slushie"] = function(p, t, fade, line, ctx)
	local C, U, F = p.center, p.upDir, p.forward
	local scale = math.min(ctx.scale, 1.5)
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.2)
	local age, life = t * p.maxLife, p.maxLife
	-- X is the viewer's right. From the field, looking at the goal, that is the opposite of the
	-- goal's own right vector; from behind the goal it is the same.
	-- (Which side the camera is on is decided once, on the first frame, so it never flips halfway.)
	if p.behind == nil then p.behind = ctx.eye ~= nil and (ctx.eye - C):dot(F) < 0 end
	local X = if p.behind then p.right else p.right * -1
	-- flavours: the scorer's colour and a second one that stands out against it; ice; the cup
	local ar, ag, ab = r, g, b
	local br, bg, bb = 1.0, 0.16, 0.32 -- cherry
	if p.r > p.b then br, bg, bb = 0.16, 0.62, 1.0 end -- a red / orange / gold scorer gets blue raspberry
	local ir, ig, ib = 0.80, 0.95, 1.0 -- ice
	local cr, cg, cb = 0.93, 0.95, 1.0 -- cup and lid
	local wr, wg, wb = 1, 1, 1 -- glints and the flash
	if p.painted then
		br, bg, bb = r * 0.68, g * 0.68, b * 0.68 -- one paint: the second flavour is a darker shade of it
		ir, ig, ib = hr, hg, hb
		cr, cg, cb = mix(r, 1, 0.06), mix(g, 1, 0.06), mix(b, 1, 0.06)
		wr, wg, wb = hr, hg, hb
	end

	local cupH, bottomHalf, topHalf, domeH = 300 * scale, 70 * scale, 118 * scale, 108 * scale
	local dropT, fillFrom, fillTo, lidAt, strawAt, slurpFrom, slurpTo, freezeAt, burstAt = 0.07, 0.08, 0.33, 0.34, 0.38, 0.44, 0.60, 0.60, 0.72
	local landed = clamp01(t / dropT)
	local drop = (1 - landed) ^ 2 * math.abs(math.cos(landed * 4.7)) * 700 * scale
	local shaking = if t > slurpFrom and t < burstAt then (if t > freezeAt then 11 else 5) else 0
	local shake = math.sin(age * 52) * shaking * scale
	local base = C + (F * (340 * scale)) + (U * (BOTTOM + drop)) + (X * shake)
	local function at(x, y, out) return base + (X * x) + (U * y) + (F * (out or 0)) end
	local function halfAt(v) return mix(bottomHalf, topHalf, v) end
	-- half width of the dome at height q (0 = rim, 1 = top)
	local function domeHalf(q) return topHalf * math.sqrt(math.max(1 - q * q, 0)) end

	-- how full it is: 0 = empty, 1 = to the rim, above 1 = piled into the dome
	local level = 0
	if t >= fillFrom then level = 1.30 * smooth((t - fillFrom) / (fillTo - fillFrom)) end
	if t >= slurpFrom then level = mix(1.30, 0.22, smooth((t - slurpFrom) / (slurpTo - slurpFrom))) end

	if t < burstAt then
		local alpha = clamp01(t / 0.02)
		-- frost creeping over the cup during the brain freeze
		local frost = clamp01((t - freezeAt) / (burstAt - freezeAt))
		local or_, og, ob = mix(cr, ir, frost), mix(cg, ig, frost), mix(cb, ib, frost)

		-- slush: rows in the cup, each split into the two flavours along a wavy line that churns
		local rows = 15
		for i = 0, rows - 1 do
			local v = (i + 0.5) / rows
			if v < level then
				local half = halfAt(v) - 8 * scale
				local swirl = half * 0.62 * math.sin(v * 6.5 + age * 3.2)
				local thick = cupH / rows * 1.14 * alpha
				line(at(-half, v * cupH), at(swirl, v * cupH), ar, ag, ab, thick)
				line(at(swirl, v * cupH), at(half, v * cupH), br, bg, bb, thick)
			end
		end
		-- the pile above the rim: a soft-serve swirl that narrows to a tip
		if level > 1 then
			local pile = (level - 1) / 0.30 -- 0..1
			local layers = 4
			for i = 0, layers - 1 do
				local q = (i + 0.5) / layers * 0.82
				if q < pile * 0.82 then
					local half = domeHalf(q) * (0.92 - 0.50 * (i / layers)) - 6 * scale
					local lean = math.sin(i * 1.9 + age * 3.2) * 9 * scale
					local y = cupH + q * domeH
					local thick = domeH * 0.82 / layers * 1.16 * alpha
					local swirl = half * 0.5 * math.sin(i * 2.4 + age * 3.2)
					line(at(lean - half, y), at(lean + swirl, y), if i % 2 == 0 then br else ar, if i % 2 == 0 then bg else ag, if i % 2 == 0 then bb else ab, thick)
					line(at(lean + swirl, y), at(lean + half, y), if i % 2 == 0 then ar else br, if i % 2 == 0 then ag else bg, if i % 2 == 0 then ab else bb, thick)
				end
			end
		end

		-- the pour: two streams twisting round each other, from high above into the cup
		if t > fillFrom - 0.01 and t < fillTo then
			local top = cupH + domeH + 330 * scale
			local surface = math.min(level, 1.3) * cupH * 0.9
			local previousA, previousB = nil, nil
			for i = 0, 7 do
				local u = i / 7
				local y = mix(top, surface, u)
				local twist = math.sin(u * 9 - age * 14) * 13 * scale
				local a1, b1 = at(twist, y, 2), at(-twist, y, 2)
				if previousA ~= nil then
					line(previousA, a1, ar, ag, ab, 20 * scale * alpha)
					line(previousB, b1, br, bg, bb, 20 * scale * alpha)
				end
				previousA, previousB = a1, b1
			end
		end

		-- the cup: two sides, the bottom and the rim
		local edge = 9 * scale * alpha
		for side = -1, 1, 2 do
			line(at(side * bottomHalf, 0, 4), at(side * topHalf, cupH, 4), or_, og, ob, edge)
		end
		line(at(-bottomHalf, 0, 4), at(bottomHalf, 0, 4), or_, og, ob, edge)
		line(at(-topHalf - 8 * scale, cupH, 5), at(topHalf + 8 * scale, cupH, 5), or_, og, ob, 15 * scale * alpha)
		-- a highlight down the left of the cup, so it reads as clear plastic
		line(at(-bottomHalf * 0.55, cupH * 0.14, 5), at(-topHalf * 0.62, cupH * 0.80, 5), wr, wg, wb, 7 * scale * alpha * (1 - frost))

		-- dome lid: drops on once the cup is full
		if t >= lidAt then
			local settle = (1 - easeOut((t - lidAt) / 0.03)) * 240 * scale
			local previous = nil
			for i = 0, 10 do
				local angle = math.pi * i / 10
				local point = at(math.cos(angle) * topHalf, cupH + settle + math.sin(angle) * domeH, 4)
				if previous ~= nil then line(previous, point, or_, og, ob, edge) end
				previous = point
			end
		end

		-- straw: jabs in through the top of the dome, a little off centre and leaning
		if t >= strawAt then
			local push = (1 - easeOutBack((t - strawAt) / 0.04)) * 320 * scale
			local lean = norm((X * 0.26) + U, U)
			local foot = at(8 * scale, cupH * 0.16, 6) + (lean * push)
			local tip = foot + (lean * (cupH * 0.84 + domeH + 150 * scale))
			line(foot, tip, cr, cg, cb, 24 * scale * alpha)
			for k = 0, 3 do -- stripes
				local stripe = foot + (lean * (cupH * 0.84 + domeH + (22 + k * 34) * scale))
				line(stripe - (X * (13 * scale)), stripe + (X * (13 * scale)) + (U * (9 * scale)), ar, ag, ab, 11 * scale * alpha)
			end
			-- the slurp: slush racing up the straw and little "sip" marks off its tip
			if t > slurpFrom and t < slurpTo + 0.02 then
				for k = 0, 2 do
					local cycle = age * 3.4 + k / 3
					cycle -= math.floor(cycle)
					local bead = foot + (lean * (mix(0.05, 0.98, cycle) * (cupH * 0.84 + domeH + 150 * scale)))
					line(bead - (lean * (20 * scale)), bead + (lean * (20 * scale)), if k % 2 == 0 then ar else br, if k % 2 == 0 then ag else bg, if k % 2 == 0 then ab else bb, 15 * scale * alpha)
				end
				for k = -1, 1 do
					local cycle = age * 4 + (k + 1) * 0.21
					cycle -= math.floor(cycle)
					local direction = norm(lean + (X * (k * 0.75)), U)
					local from = tip + (direction * ((22 + 50 * cycle) * scale))
					line(from, from + (direction * (26 * scale)), ir, ig, ib, 9 * scale * (1 - cycle) * alpha)
				end
			end
		end

		-- brain freeze: frost crystals pop out over the cup, growing
		if t > freezeAt then
			for i = 1, 8 do
				local seed = p.seed + i * 53
				local born = freezeAt + (burstAt - freezeAt) * 0.75 * hash(seed)
				if t > born then
					local grow = easeOutBack((t - born) / 0.035)
					local v = 0.12 + 1.05 * hash(seed + 1)
					local x = (hash(seed + 2) - 0.5) * 2.2 * (if v <= 1 then halfAt(v) else topHalf * 0.8)
					local centre = at(x, v * cupH, 8)
					local size = (16 + 20 * hash(seed + 3)) * scale * grow
					local spin = hash(seed + 4) * TAU
					for arm = 0, 2 do
						local angle = spin + arm * TAU / 6
						local along = ((X * math.cos(angle)) + (U * math.sin(angle))) * size
						line(centre - along, centre + along, ir, ig, ib, 6 * scale)
					end
				end
			end
		end
		return
	end

	-- the burst: slush and snowflakes out of where the cup stood
	local w = (t - burstAt) / (1 - burstAt)
	local seconds = (t - burstAt) * life
	local alpha = clamp01((1 - w) / 0.35)
	local heart = C + (F * (340 * scale)) + (U * (BOTTOM + cupH * 0.55))
	local gravity = 900 * scale
	-- a frost ring spreading over the floor, and one flash ring in the air
	local spread = easeOut(w / 0.55) * 430 * scale
	local previous = nil
	for i = 0, 18 do
		local angle = i * TAU / 18
		local point = C + (F * (340 * scale)) + (U * (BOTTOM + 3)) + (X * (math.cos(angle) * spread)) + (F * (math.sin(angle) * spread * 0.6))
		if previous ~= nil then line(previous, point, ir, ig, ib, 11 * scale * alpha) end
		previous = point
	end
	if w < 0.3 then
		local radius = easeOut(w / 0.3) * 330 * scale
		previous = nil
		for i = 0, 16 do
			local angle = i * TAU / 16
			local point = heart + (X * (math.cos(angle) * radius)) + (U * (math.sin(angle) * radius))
			if previous ~= nil then line(previous, point, wr, wg, wb, 22 * scale * (1 - w / 0.3) ^ 2) end
			previous = point
		end
	end
	-- slush: fat drops thrown up and out, falling back to the floor
	for i = 1, 46 do
		local seed = p.seed + 300 + i * 29
		local angle = hash(seed) * TAU
		local outward = (X * math.cos(angle)) + (F * (math.sin(angle) * 0.7))
		local speed = (150 + 420 * hash(seed + 1)) * scale
		local rise = (260 + 620 * hash(seed + 2)) * scale
		local height = cupH * 0.55 + rise * seconds - 0.5 * gravity * seconds * seconds
		if height > 0 then
			local point = C + (F * (340 * scale)) + (U * (BOTTOM + height)) + (outward * (speed * seconds))
			local velocity = (outward * speed) + (U * (rise - gravity * seconds))
			local tail = norm(velocity, U) * ((34 + 30 * hash(seed + 3)) * scale)
			local first = i % 3
			line(point - tail, point, if first == 0 then ar elseif first == 1 then br else ir, if first == 0 then ag elseif first == 1 then bg else ig,
				if first == 0 then ab elseif first == 1 then bb else ib, (11 + 8 * hash(seed + 4)) * scale * alpha)
		end
	end
	-- snowflakes: thrown out, then drifting down slowly, turning
	for i = 1, 12 do
		local seed = p.seed + 900 + i * 41
		local angle = hash(seed) * TAU
		local reach = easeOut(w / 0.5) * (180 + 380 * hash(seed + 1)) * scale
		local centre = heart + (X * (math.cos(angle) * reach)) + (U * (math.sin(angle) * reach * 0.75 + (170 - 260 * w) * w * scale)) + (F * ((hash(seed + 2) - 0.5) * 160 * scale))
		local size = (22 + 24 * hash(seed + 3)) * scale
		local spin = hash(seed + 4) * TAU + seconds * (1.5 + 2 * hash(seed + 5))
		for arm = 0, 2 do
			local armAngle = spin + arm * TAU / 6
			local along = ((X * math.cos(armAngle)) + (U * math.sin(armAngle))) * size
			line(centre - along, centre + along, ir, ig, ib, 7 * scale * alpha)
		end
	end
end

-- TRASH PANDA --------------------------------------------------------------------------------
-- A steel trash can drops out of the sky onto the field in front of the goal and squashes as it
-- lands. It rattles. The lid lifts a crack and two eyes glow in the dark, looking left and right.
-- Then the lid flips up and a raccoon pops out (just his head, with the lid for a hat and his
-- paws on the rim). He looks left, looks right, blinks, grins, holds up a lit bomb, and ducks
-- back in with it. The lid slams. The can starts to shake, swell and glow in the scorer's colour
-- while light is sucked in from all round it, and it blows: a fireball, a ring in the air and
-- one across the floor, the sides of the can spinning away, the lid going straight up, and
-- rubbish everywhere (a fish bone, a banana peel, a tin, an apple core, a pizza slice, balled-up
-- paper) that lands and stays.
-- Encore: the raccoon peers out of what is left of the can, scorched and seeing stars, and the
-- lid comes back down and lands on his head.
--
-- How it is drawn. Shapes are filled with thick strokes, back to front, and there are a lot of
-- layers here (a pupil on an eye on a mask on a head in a can). So the can and the raccoon are a
-- BILLBOARD: the drawing stands on its spot and turns to face the camera, which puts every stroke
-- in one plane square-on to the viewer, and each layer is then moved a little toward the camera
-- along its own line of sight (which does not move it on screen). Whether the game puts the
-- later line on top or the nearer one, the picture comes out the same.
draw["Trash Panda"] = function(p, t, fade, line, ctx)
	local C, U, F = p.center, p.upDir, p.forward
	local scale = math.min(ctx.scale, 1.5)
	local s = scale * 1.15 -- the can and the raccoon are drawn in these units
	local r, g, b, hr, hg, hb = palette(p, ctx, 1.3)
	local age, life = t * p.maxLife, p.maxLife
	local spot = C + (F * (340 * scale)) + (U * BOTTOM) -- where the can stands, on the floor

	-- The billboard's axes: X = the viewer's right (level), Up = up the picture, deep = away from
	-- the viewer along the floor. With no camera position they are simply the goal's own.
	local eye = ctx.eye
	local X, Up, deep, sight = p.right * -1, U, F * -1, F * -1
	if eye ~= nil then
		local view = norm((spot + (U * (200 * s))) - eye, F * -1) -- from the camera to the drawing
		local flat = norm(view - (U * view:dot(U)), F * -1) -- the same, along the floor
		-- which way round "right" is depends on the handedness of the game's axes: read it off the goal
		local hand = if U:cross(F):dot(p.right) >= 0 then 1 else -1
		X = norm(U:cross(flat) * hand, X)
		local tilted = X:cross(view)
		if tilted:dot(U) < 0 then tilted = tilted * -1 end
		Up, deep, sight = norm(tilted, U), flat, view
	end
	-- Moves a point `layer` steps toward the camera along its own line of sight, so it does not
	-- move on screen. A step is 12 units measured straight toward the camera, so each layer is its
	-- own flat sheet in front of the last.
	local function nearer(point, layer)
		if layer == nil or layer == 0 then return point end
		if eye == nil then return point - (deep * (layer * 12)) end
		local toEye = eye - point
		local distance = toEye:length()
		if distance < 1 then return point end
		local square = math.max(-toEye:dot(sight) / distance, 0.3) -- 1 when the point is dead ahead of the camera
		return point + (toEye * (math.min(layer * 12 / square, distance * 0.3) / distance))
	end

	-- A colour, or with a paint colour chosen, that paint at brightness k (above 1 = the lighter shade).
	local function tone(cr, cg, cb, k)
		if p.painted then
			if k > 1 then return { hr, hg, hb } end
			return { r * k, g * k, b * k }
		end
		return { cr, cg, cb }
	end
	local team, hot = { r, g, b }, { hr, hg, hb }
	-- (painted shades stay between two-thirds of the paint and its lighter shade, like every other
	-- explosion: a crimson one is all crimson, a black one all black)
	local steel, steelDark, steelLight = tone(0.62, 0.66, 0.72, 0.86), tone(0.36, 0.39, 0.45, 0.70), tone(0.86, 0.90, 0.95, 1.1)
	local hollow = tone(0.05, 0.05, 0.07, 0.66)
	local fur, furDark, furLight = tone(0.58, 0.58, 0.62, 1.0), tone(0.33, 0.33, 0.38, 0.78), tone(0.95, 0.95, 0.92, 1.1)
	local soot, sootDark, sootLight = tone(0.30, 0.30, 0.33, 0.82), tone(0.17, 0.17, 0.20, 0.68), tone(0.66, 0.66, 0.63, 0.95)
	local black, pink, white = tone(0.05, 0.05, 0.07, 0.66), tone(0.95, 0.55, 0.65, 0.9), tone(1, 1, 1, 1.1)
	local glow, stink, smoke = tone(0.80, 1.0, 0.25, 1.1), tone(0.55, 0.88, 0.25, 0.9), tone(0.24, 0.24, 0.28, 0.68)
	local yellow, bone, red, crust, cheese = tone(1.0, 0.86, 0.20, 1.1), tone(0.93, 0.93, 0.86, 1.1), tone(0.88, 0.14, 0.12, 0.78), tone(0.85, 0.62, 0.30, 0.85), tone(1.0, 0.72, 0.18, 1.0)

	local vis = clamp01(t / 0.015) * clamp01((1 - t) / 0.05)
	local function seg(a, c, colour, thickness) line(a, c, colour[1], colour[2], colour[3], thickness * vis) end
	-- A drawing frame on the billboard: x along the viewer's right, y up the picture, both from
	-- `origin`, leaning over by `lean`. The third number is the layer (higher = further in front).
	local function frame(origin, lean, sx, sy)
		local ax = (X * math.cos(lean)) + (Up * math.sin(lean))
		local up = (Up * math.cos(lean)) - (X * math.sin(lean))
		return function(x, y, layer) return nearer(origin + (ax * (x * sx)) + (up * (y * sy)), layer) end
	end
	local function window(from, to) -- 0 outside, a smooth bump inside
		if t <= from or t >= to then return 0 end
		return math.sin(math.pi * (t - from) / (to - from))
	end
	local function floorRing(radius, segments, colourA, colourB, thickness) -- a circle lying on the floor
		local previous = nil
		for i = 0, segments do
			local angle = i * TAU / segments
			local point = spot + (U * 3) + (X * (math.cos(angle) * radius)) + (deep * (math.sin(angle) * radius))
			if previous ~= nil then seg(previous, point, if i % 2 == 0 then colourA else colourB, thickness) end
			previous = point
		end
	end

	local canH, botHalf, topHalf, lidHalf = 230 * s, 76 * s, 96 * s, 108 * s
	local ribW = topHalf * 0.27
	local landAt, rattleAt, peekAt, popAt, upAt, duckAt, shutAt, boomAt, encoreAt, bonkAt = 0.065, 0.105, 0.160, 0.225, 0.265, 0.495, 0.530, 0.655, 0.820, 0.900
	-- layers, back to front: 0 inside of the can | 1-5 the raccoon | 6 what he holds, his hat |
	-- 7-8 the can | 9 his paws | 10 the lid when it is on the can, light, stars | 11 the lid in flight

	-- THE CAN: nine ribs shaded like a cylinder, hoops, a stripe in the scorer's colour, handles.
	-- `heat` 0..1 turns the steel the scorer's colour; `torn` leaves only a ragged, scorched base.
	local function can(at, heat, torn)
		for i = 0, 8 do
			local fx = (i - 4) / 4
			local k = clamp01(1 - math.abs(fx + 0.3) * 0.85) * (if i % 2 == 0 then 1 else 0.7)
			local colour = { mix(steelDark[1], steelLight[1], k), mix(steelDark[2], steelLight[2], k), mix(steelDark[3], steelLight[3], k) }
			local top = canH
			if torn then
				top = (30 + 46 * hash(p.seed + i * 7)) * s
				colour = { mix(colour[1], hollow[1], 0.6), mix(colour[2], hollow[2], 0.6), mix(colour[3], hollow[3], 0.6) }
			elseif heat > 0 then
				colour = { mix(colour[1], team[1], heat), mix(colour[2], team[2], heat), mix(colour[3], team[3], heat) }
			end
			seg(at(fx * botHalf * 0.88, 0, 7), at(fx * mix(botHalf, topHalf, top / canH) * 0.88, top, 7), colour, ribW)
		end
		seg(at(-botHalf - 4 * s, 7 * s, 8), at(botHalf + 4 * s, 7 * s, 8), steelDark, 14 * s) -- foot
		if torn then return end
		local bandHalf, hoopHalf = mix(botHalf, topHalf, 0.34), mix(botHalf, topHalf, 0.64)
		seg(at(-bandHalf, canH * 0.34, 8), at(bandHalf, canH * 0.34, 8), team, 24 * s) -- the scorer's stripe
		seg(at(-hoopHalf - 2 * s, canH * 0.64, 8), at(hoopHalf + 2 * s, canH * 0.64, 8), steelDark, 9 * s) -- hoop
		for side = -1, 1, 2 do -- handles
			local hx = side * (mix(botHalf, topHalf, 0.76) + 3 * s)
			seg(at(hx, canH * 0.80, 8), at(hx + side * 20 * s, canH * 0.76, 8), steelDark, 6 * s)
			seg(at(hx + side * 20 * s, canH * 0.76, 8), at(hx + side * 2 * s, canH * 0.60, 8), steelDark, 6 * s)
		end
		seg(at(-topHalf - 6 * s, canH, 8.5), at(topHalf + 6 * s, canH, 8.5), steelLight, 15 * s) -- rim
	end

	-- THE LID: brim, two steps of dome and the handle, round `centre` (the middle of the brim).
	local function lid(centre, angle, layer)
		local ax = (X * math.cos(angle)) + (Up * math.sin(angle))
		local up = (Up * math.cos(angle)) - (X * math.sin(angle))
		local function at(x, y) return nearer(centre + (ax * x) + (up * y), layer) end
		seg(at(-lidHalf, 0), at(lidHalf, 0), steelLight, 15 * s)
		seg(at(-lidHalf * 0.74, 15 * s), at(lidHalf * 0.74, 15 * s), steel, 20 * s)
		seg(at(-lidHalf * 0.40, 30 * s), at(lidHalf * 0.40, 30 * s), steel, 14 * s)
		seg(at(-13 * s, 43 * s), at(13 * s, 43 * s), steelDark, 11 * s)
	end

	-- THE RACCOON'S HEAD, from the chin up. look -1..1 = looking left..right (his face slides a
	-- little that way). mood: "calm", "blink", "grin", "dazed" or "wince".
	local function raccoon(at, look, mood, sooty)
		local coat, coatDark, coatLight = fur, furDark, furLight
		if sooty then coat, coatDark, coatLight = soot, sootDark, sootLight end
		local slide = look * 7
		local function skull(x, y, layer) return at(x * s, y * s, layer) end
		local function face(x, y, layer) return at((x + slide) * s, y * s, layer) end
		local twitch = if math.sin(age * 7.3) > 0.9 then 7 else 0
		for side = -1, 1, 2 do -- ears, with pink insides
			local flick = if side == 1 then twitch else 0
			seg(skull(side * 50 - look * 3, 90, 1), skull(side * 66 - look * 3, 138 + flick, 1), coatDark, 34 * s)
			seg(skull(side * 52 - look * 3, 100, 1.5), skull(side * 63 - look * 3, 129 + flick, 1.5), pink, 13 * s)
		end
		seg(skull(-40, 88, 2), skull(40, 88, 2), coat, 36 * s) -- the head: crown, cheeks, jaw
		seg(skull(-64, 58, 2), skull(64, 58, 2), coat, 46 * s)
		seg(skull(-40, 26, 2), skull(40, 26, 2), coat, 36 * s)
		for side = -1, 1, 2 do
			seg(skull(side * 58, 52, 2), skull(side * 92, 36, 2), coat, 22 * s) -- cheek fur
			seg(skull(side * 54, 34, 2), skull(side * 80, 16, 2), coat, 14 * s)
		end
		if sooty then -- frazzled fur standing on end
			for i = -2, 2 do seg(skull(i * 15, 102, 2), skull(i * 23, 124 + 10 * hash(p.seed + i * 3), 2), coatDark, 7 * s) end
		end
		for side = -1, 1, 2 do
			seg(face(side * 60, 82, 3), face(side * 14, 76, 3), coatLight, 11 * s) -- pale brow
			seg(face(side * 8, 58, 3), face(side * 62, 50, 3), black, 30 * s) -- the mask
		end
		seg(face(0, 101, 3), face(0, 56, 3), coatDark, 12 * s) -- dark stripe down to the nose
		seg(face(-22, 26, 4), face(22, 26, 4), coatLight, 36 * s) -- pale muzzle
		for side = -1, 1, 2 do -- whiskers
			seg(face(side * 20, 28, 5), face(side * 58, 36, 5), coatLight, 2.6 * s)
			seg(face(side * 20, 22, 5), face(side * 58, 13, 5), coatLight, 2.6 * s)
		end
		seg(face(-9, 40, 5), face(9, 40, 5), black, 14 * s) -- nose
		-- mouth
		if mood == "grin" then
			seg(face(-17, 17, 5), face(17, 17, 5), black, 13 * s)
			seg(face(-13, 20, 5.5), face(13, 20, 5.5), white, 5 * s)
		elseif mood == "dazed" then
			seg(face(-10, 16, 5), face(-3, 19, 5), black, 3.5 * s)
			seg(face(-3, 19, 5), face(4, 15, 5), black, 3.5 * s)
			seg(face(3, 13, 5.5), face(7, 3, 5.5), pink, 7 * s) -- tongue
		elseif mood == "wince" then
			seg(face(-9, 13, 5), face(0, 17, 5), black, 3.5 * s)
			seg(face(0, 17, 5), face(9, 13, 5), black, 3.5 * s)
		else
			seg(face(-9, 17, 5), face(0, 13, 5), black, 3.5 * s)
			seg(face(0, 13, 5), face(9, 17, 5), black, 3.5 * s)
		end
		-- eyes, inside the mask
		for side = -1, 1, 2 do
			local ex, ey = side * 34, 55
			if mood == "blink" then
				seg(face(ex - 8, ey, 4), face(ex + 8, ey, 4), coatLight, 3 * s)
			elseif mood == "dazed" then
				seg(face(ex - 7, ey - 7, 4), face(ex + 7, ey + 7, 4), white, 4 * s)
				seg(face(ex - 7, ey + 7, 4), face(ex + 7, ey - 7, 4), white, 4 * s)
			elseif mood == "wince" then
				seg(face(ex - side * 7, ey + 7, 4), face(ex + side * 6, ey, 4), white, 4 * s)
				seg(face(ex + side * 6, ey, 4), face(ex - side * 7, ey - 7, 4), white, 4 * s)
			else
				seg(face(ex - 7, ey, 4), face(ex + 7, ey, 4), white, (if mood == "grin" then 10 else 15) * s)
				seg(face(ex - 3 + look * 4, ey, 5), face(ex + 3 + look * 4, ey, 5), black, 8 * s)
			end
		end
	end

	-- ============================== before it blows ==============================
	if t < boomAt then
		-- where the can is, and how it is squashed, leaning and shaking
		local dropY, sx, sy = 0, 1, 1
		if t < landAt then
			local u = t / landAt
			dropY = (1 - u * u) * 950 * scale -- falling faster and faster
			sx, sy = 0.93, 1.10
		elseif t < landAt + 0.05 then
			local since = (t - landAt) / 0.05
			local squash = math.exp(-since * 3.5) * math.cos(since * 13) * 0.24
			sx, sy = 1 + squash * 0.7, 1 - squash
		end
		local rattle = window(rattleAt, rattleAt + 0.03) + window(peekAt - 0.025, peekAt) + window(popAt - 0.012, popAt + 0.006) * 0.6
		local charge = clamp01((t - shutAt) / (boomAt - shutAt))
		local lean = math.sin(age * 34) * 0.085 * rattle + math.sin(age * 47) * 0.035 * charge
		local shake = math.sin(age * 61) * (if t > shutAt then 1.5 + 13 * charge * charge else 0) * scale
		sx *= 1 + 0.17 * charge * charge
		sy *= 1 + 0.04 * charge * charge
		local at = frame(spot + (U * dropY) + (X * shake), lean, sx, sy)

		-- falling: speed lines above it
		if t < landAt then
			for i = -1, 2 do
				local x = (i - 0.5) * topHalf * 0.6
				seg(at(x, canH + (90 + 40 * hash(p.seed + i)) * s), at(x, canH + (300 + 160 * hash(p.seed + i + 9)) * s), hot, 5 * s)
			end
		end
		-- landing: a ring across the floor and dust kicked out to both sides
		local landed = (t - landAt) / 0.07
		if landed > 0 and landed < 1 then
			floorRing(botHalf + 330 * scale * easeOut(landed), 16, team, team, 11 * scale * (1 - landed) ^ 2)
			for i = 1, 10 do
				local side = if i % 2 == 0 then 1 else -1
				local reach = botHalf + (40 + 190 * hash(p.seed + i * 5)) * scale * easeOut(landed)
				local height = (10 + 90 * hash(p.seed + i * 5 + 1)) * scale * easeOut(landed)
				local puff = spot + (X * (side * reach)) + (U * height)
				seg(puff - (X * (side * 14 * scale)), puff + (X * (side * 14 * scale)), steelLight, (30 - 8 * hash(p.seed + i)) * scale * (1 - landed))
			end
		end
		-- a whiff coming off it while it stands there
		if t > landAt + 0.03 and t < shutAt then
			for side = -1, 1, 2 do
				local previous = nil
				for k = 0, 3 do
					local y = canH + (60 + k * 34) * s + (age * 30 * s) % (34 * s)
					local point = at(side * (topHalf + 34 * s) + math.sin(k * 1.9 + age * 4 + side) * 12 * s, y)
					if previous ~= nil then seg(previous, point, stink, 5 * s * (1 - k / 4)) end
					previous = point
				end
			end
		end

		-- the raccoon: how far out he is (0 = down in the can, 1 = head out)
		local rise = 0
		if t >= popAt and t < duckAt then rise = easeOutBack((t - popAt) / (upAt - popAt))
		elseif t >= duckAt and t < shutAt then rise = 1 - clamp01((t - duckAt) / (shutAt - duckAt)) ^ 2 end
		local out = t >= popAt and t < shutAt
		local look, mood, headLean = 0, "calm", 0
		local grinFrom = upAt + 0.79 * (duckAt - upAt)
		if t >= upAt and t < duckAt then
			local v = (t - upAt) / (duckAt - upAt)
			look = -smooth((v - 0.05) / 0.07) + 2 * smooth((v - 0.33) / 0.08) - smooth((v - 0.62) / 0.07)
			if (v > 0.24 and v < 0.265) or (v > 0.71 and v < 0.75) then mood = "blink" end
			if t > grinFrom then mood = "grin" end
			headLean = look * 0.10 + (if mood == "grin" then math.sin(age * 31) * 0.035 else 0)
		elseif t >= duckAt and t < shutAt then
			mood = "grin"
		end
		local chin = canH + mix(-158 * s, -8 * s, rise)

		-- the lid: on the can, lifted a crack for the eyes, worn as a hat, or slammed back on
		local lidY, lidAngle = canH + 7 * s, 0
		local hop = math.abs(math.sin(age * 34)) * 16 * s * rattle + math.abs(math.sin(age * 40)) * (2 + 15 * charge) * s * (if t > shutAt then 1 else 0)
		local gap = 0
		if t >= peekAt and t < popAt then
			gap = 30 * s * smooth((t - peekAt) / 0.012) * (1 - smooth((t - (popAt - 0.014)) / 0.010))
			lidAngle = 0.10 * gap / (30 * s)
		end
		if out then
			local hat = chin + 134 * s
			lidY = math.max(lidY, hat)
			lidAngle = (0.26 + headLean) * clamp01((hat - canH) / (60 * s))
		elseif t >= shutAt then
			lidAngle = math.sin(age * 33) * 0.10 * charge
		end
		local lidCentre = at(if out then look * 4 * s else 0, lidY + gap + hop)

		-- drawn back to front: the dark inside, the raccoon, what he holds and wears, the can, his paws
		if gap > 1 or out then
			seg(at(-topHalf + 8 * s, canH + 4 * s + gap * 0.5, 0), at(topHalf - 8 * s, canH + 4 * s + gap * 0.5, 0), hollow, 20 * s + gap)
		end
		if gap > 6 * s then -- eyes in the dark, looking one way and then the other
			local peer = math.sin((t - peekAt) / (popAt - peekAt) * TAU) * 16 * s
			for side = -1, 1, 2 do
				seg(at(side * 20 * s + peer - 6 * s, canH + 6 * s + gap * 0.5, 1), at(side * 20 * s + peer + 6 * s, canH + 6 * s + gap * 0.5, 1), glow, math.min(gap * 0.5, 11 * s))
			end
		end
		local armed = out and mood == "grin"
		if out then
			raccoon(frame(at(look * 4 * s, chin), lean + headLean, 1, 1), look, mood, false)
			if armed then -- a lit bomb, held up in one paw
				local lift = easeOutBack(clamp01((t - grinFrom) / 0.018))
				local paw = at(topHalf * 0.86, chin + mix(-30, 78, lift) * s, 6)
				local bomb = at(topHalf * 0.86, chin + mix(-30, 78, lift) * s + 30 * s, 6)
				seg(at(topHalf * 0.70, chin + mix(-40, 20, lift) * s, 6), paw, furDark, 15 * s) -- arm
				seg(bomb - (X * (15 * s)), bomb + (X * (15 * s)), black, 34 * s)
				local shine = nearer(bomb + (Up * (6 * s)), 0.5)
				seg(shine - (X * (9 * s)), shine - (X * (3 * s)), steelLight, 7 * s)
				local fuse = bomb + (Up * (17 * s)) + (X * (4 * s))
				local tip = fuse + (Up * (16 * s)) + (X * (12 * s))
				seg(fuse, tip, crust, 4 * s)
				local fizz = math.floor(age / 0.035)
				for i = 0, 3 do
					local angle = hash(p.seed + fizz * 5 + i) * TAU
					local direction = (X * math.cos(angle)) + (Up * math.sin(angle))
					seg(tip, tip + (direction * ((10 + 14 * hash(p.seed + fizz + i * 3)) * s)), if i % 2 == 0 then yellow else hot, 4.5 * s)
				end
			end
			lid(lidCentre, lean + lidAngle, 6) -- his hat
		end
		can(at, charge * charge * 0.8, false)
		if out and rise > 0.55 then -- paws over the rim (one, once the other is holding the bomb)
			for side = -1, if armed then -1 else 1, 2 do
				seg(at(side * topHalf * 0.74, canH + 3 * s, 9), at(side * topHalf * 0.50, canH + 3 * s, 9), furDark, 15 * s)
				for finger = 0, 2 do
					local x = side * topHalf * (0.53 + finger * 0.09)
					seg(at(x, canH + 6 * s, 9.5), at(x, canH - 12 * s, 9.5), black, 4.5 * s)
				end
			end
		end
		if not out then lid(lidCentre, lean + lidAngle, 10) end

		-- little bursts: the pop, and the clang as the lid slams
		for _, burst in ipairs({ popAt, shutAt }) do
			local since = (t - burst) / 0.022
			if since >= 0 and since < 1 then
				for i = 0, 6 do
					local angle = math.pi * (0.08 + 0.84 * i / 6)
					local direction = (X * math.cos(angle)) + (Up * math.sin(angle))
					local from = at(0, canH + 20 * s) + (direction * ((lidHalf + 10 * s) + 70 * s * since))
					seg(from, from + (direction * (34 * s)), hot, 7 * s * (1 - since))
				end
			end
		end

		-- charging up: light leaks out under the lid and streaks are pulled in from all round
		if t > shutAt then
			local flicker = math.floor(age / 0.04)
			for i = 0, 8 do
				local angle = math.pi * (0.06 + 0.88 * i / 8)
				local direction = (X * math.cos(angle)) + (Up * (math.sin(angle) * 0.8 + 0.2))
				local from = at(math.cos(angle) * topHalf * 0.92, canH + 6 * s, 10)
				local reach = (12 + 120 * charge) * s * (0.55 + 0.45 * hash(p.seed + i * 3 + flicker))
				seg(from, from + (direction * reach), if i % 3 == 1 then hot else team, (4 + 10 * charge) * s)
			end
			local heart = spot + (Up * (canH * 0.6))
			for i = 1, 12 do
				local cycle = age * (1.3 + 1.6 * charge) + i / 12
				cycle -= math.floor(cycle)
				local angle = hash(p.seed + i * 17) * TAU
				local direction = (X * math.cos(angle)) + (Up * (math.sin(angle) * 0.8)) + (deep * ((hash(p.seed + i * 17 + 1) - 0.5) * 0.8))
				local radius = mix(560, 170, cycle ^ 1.6) * scale
				local from = heart + (direction * radius)
				seg(from, from + (direction * (70 * scale * (0.3 + cycle))), if i % 2 == 0 then hot else team, 6 * scale * cycle * clamp01(charge / 0.25))
			end
		end
		return
	end

	-- ============================== it blows ==============================
	local w = (t - boomAt) / (1 - boomAt)
	local seconds = (t - boomAt) * life
	local heart = spot + (Up * (canH * 0.55))
	local gravity = 1150 * scale

	if w < 0.07 then -- flash
		local glare = 1 - w / 0.07
		for i = 0, 9 do
			local angle = i * TAU / 10 + 0.2
			local direction = (X * math.cos(angle)) + (Up * math.sin(angle))
			seg(heart + (direction * (40 * s)), heart + (direction * ((220 + 520 * (1 - glare)) * scale)), hot, 28 * scale * glare)
		end
	end
	if w < 0.42 then -- fireball: fat lumps thrown outward, white-hot in the middle
		local out = easeOut(w / 0.42)
		local shrink = (1 - w / 0.42) ^ 1.3
		for i = 1, 28 do
			local seed = p.seed + 100 + i * 23
			local angle, lean = hash(seed) * TAU, (hash(seed + 1) - 0.5) * 1.4
			local direction = (X * (math.cos(angle) * math.cos(lean))) + (Up * (math.sin(angle) * math.cos(lean))) + (deep * math.sin(lean))
			local reach = out * (130 + 290 * hash(seed + 2)) * scale
			local colour = if i % 3 == 0 then hot elseif i % 5 == 0 then yellow else team
			seg(heart + (direction * (reach * 0.45)), heart + (direction * reach), colour, (30 + 52 * hash(seed + 3)) * scale * shrink)
		end
	end
	if w < 0.38 then -- shock ring in the air, facing the viewer
		local grow = w / 0.38
		local radius = (60 + 480 * easeOut(grow)) * scale
		local previous = nil
		for i = 0, 18 do
			local angle = i * TAU / 18
			local point = heart + (X * (math.cos(angle) * radius)) + (Up * (math.sin(angle) * radius))
			if previous ~= nil then seg(previous, point, team, 22 * scale * (1 - grow) ^ 2) end
			previous = point
		end
	end
	if w < 0.6 then -- and one racing out across the floor
		local grow = w / 0.6
		floorRing(botHalf + 660 * scale * easeOut(grow), 20, hot, team, 13 * scale * (1 - grow) ^ 1.5)
	end
	for i = 1, 8 do -- smoke rolling up
		local seed = p.seed + 700 + i * 31
		local climb = easeOut(w / 0.85)
		local puff = heart + (X * ((hash(seed) - 0.5) * 300 * scale * climb)) + (U * ((80 + 560 * hash(seed + 1)) * scale * climb))
		local size = (22 + 30 * hash(seed + 2)) * scale * clamp01(w / 0.08) * clamp01((0.85 - w) / 0.5)
		if size > 0.5 then seg(puff - (X * (size * 0.5)), puff + (X * (size * 0.5)), smoke, size) end
	end
	for i = 0, 8 do -- the sides of the can, spinning away
		local seed = p.seed + 400 + i * 13
		local fx = (i - 4) / 4
		local fan = fx * 1.2 + (hash(seed) - 0.5) * 0.3
		local speed = (620 + 320 * hash(seed + 1)) * scale
		local velocity = (X * (math.sin(fan) * speed)) + (U * (math.cos(fan) * speed * 0.9)) + (deep * ((hash(seed + 2) - 0.5) * 260 * scale))
		local centre = spot + (X * (fx * topHalf * 0.8)) + (Up * (canH * 0.6)) + (velocity * seconds) - (U * (0.9 * gravity * seconds * seconds))
		if (centre - spot):dot(U) > 0 then
			local spin = seconds * (5 + 7 * hash(seed + 3)) * (if fx < 0 then 1 else -1) + fx
			local axis = ((X * math.sin(spin)) + (Up * math.cos(spin))) * (canH * 0.34)
			local k = clamp01(1 - math.abs(fx + 0.3) * 0.85) * 0.6
			seg(centre - axis, centre + axis, { mix(steelDark[1], steelLight[1], k), mix(steelDark[2], steelLight[2], k), mix(steelDark[3], steelLight[3], k) }, ribW)
		end
	end
	for i = 1, 40 do -- sparks
		local seed = p.seed + 1300 + i * 29
		local angle = hash(seed) * TAU
		local speed = (300 + 760 * hash(seed + 1)) * scale
		local velocity = (X * (math.cos(angle) * speed)) + (U * (math.sin(angle) * speed * 0.8 + 260 * scale)) + (deep * ((hash(seed + 2) - 0.5) * 500 * scale))
		local point = heart + (velocity * seconds) - (U * (0.5 * gravity * seconds * seconds))
		local dying = clamp01((0.62 - w) / 0.4)
		if (point - spot):dot(U) > 0 and dying > 0 then
			local tail = norm(velocity - (U * (gravity * seconds)), U) * ((40 + 40 * hash(seed + 3)) * scale)
			seg(point - tail, point, if i % 3 == 0 then hot elseif i % 3 == 1 then team else yellow, (5 + 6 * hash(seed + 4)) * scale * dying)
		end
	end

	-- RUBBISH: each piece is a little drawing {x1, y1, x2, y2, thickness, colour} that tumbles
	-- through the air, lands, and stays where it fell.
	local rubbish = {
		{ { -30, 0, 30, 0, 5, bone }, { -12, -12, -12, 12, 4, bone }, { 0, -13, 0, 13, 4, bone }, { 12, -11, 12, 11, 4, bone }, { 30, 0, 44, 0, 17, bone }, { -30, 0, -45, 13, 5, bone }, { -30, 0, -45, -13, 5, bone } }, -- fish bone
		{ { 0, 0, -27, -21, 11, yellow }, { 0, 0, 27, -21, 11, yellow }, { 0, 2, 0, -30, 11, yellow }, { 0, 2, 3, 18, 7, crust } }, -- banana peel
		{ { -13, 0, 13, 0, 34, steelLight }, { -13, 0, 13, 0, 16, team }, { 13, 17, 27, 27, 4, steelLight } }, -- tin
		{ { -10, 16, 10, 16, 12, red }, { -10, -16, 10, -16, 12, red }, { 0, -14, 0, 14, 9, bone }, { 0, 22, 4, 32, 3, crust } }, -- apple core
		{ { -22, 18, 22, 18, 10, crust }, { -14, 6, 14, 6, 16, cheese }, { -6, -10, 6, -10, 16, cheese }, { -2, 3, 3, 3, 8, red } }, -- pizza slice
		{ { -9, -6, 9, 6, 13, white }, { -8, 7, 8, -7, 11, bone } }, -- balled-up paper
		{ { -9, -6, 9, 6, 13, white }, { -8, 7, 8, -7, 11, bone } },
		{ { -9, -6, 9, 6, 13, white }, { -8, 7, 8, -7, 11, bone } },
	}
	for i, shape in ipairs(rubbish) do
		local seed = p.seed + 2100 + i * 37
		local side = if i % 2 == 0 then 1 else -1
		local fan = side * (0.25 + 0.75 * hash(seed))
		local speed = (430 + 330 * hash(seed + 1)) * scale
		local vx, vy = math.sin(fan) * speed, math.cos(fan) * speed
		local vd = (hash(seed + 2) - 0.5) * 240 * scale
		local start, rest = (heart - spot):dot(U), 16 * s
		local landing = (vy + math.sqrt(vy * vy + 2 * gravity * (start - rest))) / gravity
		local flight = math.min(seconds, landing)
		local centre = heart + (X * (vx * flight)) + (deep * (vd * flight)) + (U * (vy * flight - 0.5 * gravity * flight * flight))
		local spin = if seconds < landing then seconds * (4 + 6 * hash(seed + 3)) * side else 0
		local ax = (X * math.cos(spin)) + (Up * math.sin(spin))
		local up = (Up * math.cos(spin)) - (X * math.sin(spin))
		for k, stroke in ipairs(shape) do
			seg(nearer(centre + (ax * (stroke[1] * s)) + (up * (stroke[2] * s)), k * 0.5), nearer(centre + (ax * (stroke[3] * s)) + (up * (stroke[4] * s)), k * 0.5), stroke[6], stroke[5] * s)
		end
	end

	-- what is left of the can, the raccoon coming up out of it, and the lid coming back down
	local base = frame(spot, 0, 1, 1)
	local rise = if t >= encoreAt then easeOutBack((t - encoreAt) / 0.04) else 0
	local bonk = (t - bonkAt) / 0.03 -- above 0 once the lid has landed on him
	local dip = if bonk >= 0 and bonk < 1 then math.sin(bonk * math.pi) * 22 * s else 0
	local chin = mix(-150 * s, 34 * s, rise) - dip
	local sway = math.sin(age * 4.6) * 0.11 * (if bonk >= 0 then 0.4 else 1)
	if t >= encoreAt then
		seg(base(-botHalf * 0.8, 30 * s, 0), base(botHalf * 0.8, 30 * s, 0), hollow, 44 * s)
		local head = frame(base(0, chin), sway, 1, 1)
		raccoon(head, 0, if bonk >= 0 and bonk < 1.6 then "wince" else "dazed", true)
		for i = 0, 2 do -- seeing stars
			local angle = age * 5 + i * TAU / 3
			local star = head(math.cos(angle) * 84 * s, 168 * s + math.sin(angle) * 20 * s, 10)
			local size = 11 * s
			seg(star - (X * size), star + (X * size), yellow, 5 * s)
			seg(star - (Up * size), star + (Up * size), yellow, 5 * s)
		end
	end
	can(base, 0, true)
	do
		local u = clamp01((t - boomAt) / (bonkAt - boomAt))
		local landedY = 34 * s + 134 * s
		local height = mix(canH + 7 * s, landedY, u) + 4 * u * (1 - u) * 1000 * scale - dip
		local drift = math.sin(u * TAU) * 60 * scale
		local angle = 0.2 + (1 - u) ^ 2 * 30
		if bonk >= 0 then angle = 0.2 + sway + math.sin(bonk * 9) * 0.25 * math.exp(-bonk * 1.2) end
		lid(spot + (X * drift) + (Up * height), angle, 11)
		if bonk >= 0 and bonk < 1 then -- bonk
			for i = 0, 5 do
				local a = math.pi * (0.1 + 0.8 * i / 5)
				local direction = (X * math.cos(a)) + (Up * math.sin(a))
				local from = spot + (Up * (height + 20 * s)) + (direction * ((lidHalf * 0.8) + 60 * s * bonk))
				seg(from, from + (direction * (30 * s)), hot, 7 * s * (1 - bonk))
			end
		end
	end
end

-- Draws one effect entry. ctx: { scale, vibrance, budget, eye, fov }. Returns false for an unknown type.
function Effects.draw(p, t, fade, line, ctx)
	local renderer = draw[p.type]
	if renderer == nil then return false end
	if p.seed == nil then p.seed = 1 end
	renderer(p, clamp01(t), fade, line, ctx)
	return true
end

return Effects
