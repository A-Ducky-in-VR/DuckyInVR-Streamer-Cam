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
-- None of his code is copied here. Taken from Caster Camera 2.6.4: the rule for when a round starts
-- (which game signals it reads, and when). The code itself is written for Streamer Cam.
--
-- Streamer Cam kickoffs: works out when a kickoff is happening in the arena being watched, draws a
-- countdown graphic around the ball at the kickoff spot, and proposes a kickoff camera shot.
-- Read-only: it never writes the camera (main.luau applies the shot) and it only draws through the
-- line function it is handed, so it shares the goal-effect line budget.
--
-- HOW A KICKOFF IS DETECTED (same signals Dennssen Caster 2.6.4 uses for its round-start effect):
--   SpectatorGamemodes.getGamemodeData(slot).secondaryTimeSeconds  the kickoff countdown ("action
--       timer" in Caster and on the overlay scoreboards). While it is running down, a kickoff is
--       coming. When it reaches zero the ball is live: GO.
--   SpectatorGamemodes.getGamemodeData(slot).isGameRunning         false -> true with no countdown
--       showing is treated as GO too (Caster's rule for a round that starts without one).
-- Nothing is fired for a countdown that is cancelled, stuck, or already over when we arrive.
--
-- ROUND START ONLY. In the game that timer also runs in the middle of a round (after a
-- goal, while the team that was scored on brings the ball out; when the ball comes back to the
-- middle). Those are not kickoffs. A countdown is only treated as a kickoff while a round start is
-- PENDING, and the launch uses that up:
--   pending is set when  the game is seen NOT running (before a match, between rounds), or
--                        the score goes back to 0 - 0, or the rounds-won count changes
--   pending is cleared   when a kickoff reaches GO
-- This is the Caster Camera's own rule for its round-start effect (armed when the game goes from
-- not running to running, fired when the timer reaches zero), widened so the countdown before the
-- launch can be drawn too. settings.every = true treats every countdown as a kickoff instead.
--
-- WHERE: around the arena's ball while it is sitting in the middle; otherwise at the arena's
-- kickoff spot (ArenaMap's kickZ, from Caster's "place ball" box for each layout).
local Kickoff = {
	styles = { "Countdown Ring", "Face-Off", "Beacon", "Lock-On" },
	styleChoices = { "Countdown Ring", "Face-Off", "Beacon", "Lock-On", "Cycle (a different one each kickoff)" },
	camStyles = { "Sideline", "Orbit", "Top Down" },
	phase = "idle", -- "idle" | "count" (countdown showing) | "go" (burst after the ball goes live)
	status = "Waiting for an arena", lastEvent = "none yet", reading = "no arena",
	time = 0, count = 0, lastGo = -math.huge, camActive = false, camAge = 0, source = "none",
	fresh = false, -- a round start is pending: the next countdown is the launch
	ignored = 0, -- mid-round countdowns that were not drawn
}

local GO_SECONDS = 1.6 -- length of the GO burst
local TAU = math.pi * 2

local function clamp01(v) return math.clamp(v, 0, 1) end
local function easeOut(u) u = clamp01(u); return 1 - (1 - u) * (1 - u) * (1 - u) end
local function easeOutBack(u) u = clamp01(u) - 1; return 1 + 2.70158 * u * u * u + 1.70158 * u * u end
local function mix(a, b, u) return a + (b - a) * u end
local function norm(v, fallback)
	local length = v:length()
	if length ~= length or length < 0.0001 then return fallback end
	return v * (1 / length)
end

-- ---------------------------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------------------------

function Kickoff.stop(note)
	Kickoff.phase, Kickoff.camActive, Kickoff.wentAt, Kickoff.testLeft = "idle", false, nil, nil
	Kickoff.camSide = nil
	if note ~= nil then Kickoff.lastEvent = note end
end

-- Menu button: play a made-up countdown of `seconds`, then GO, in the arena being watched.
function Kickoff.test(seconds)
	Kickoff.stop()
	Kickoff.testLeft = math.clamp(tonumber(seconds) or 3, 0.5, 15)
	Kickoff.testTotal = Kickoff.testLeft
end

local function arm(source, total)
	Kickoff.count += 1
	Kickoff.phase, Kickoff.source = "count", source
	Kickoff.countAge, Kickoff.total = 0, math.max(total or 1, 0.5)
	Kickoff.number, Kickoff.numberAt = nil, Kickoff.time
	Kickoff.wentAt, Kickoff.goSpot = nil, nil
	Kickoff.camActive, Kickoff.camAge, Kickoff.camSide, Kickoff.camCentre = true, 0, nil, nil
end

local function go(source)
	if Kickoff.phase ~= "count" then
		arm(source, 1)
		Kickoff.camActive = false -- no countdown was seen: graphics only, the camera is not pulled away late
	end
	Kickoff.phase, Kickoff.goAge = "go", 0
	Kickoff.wentAt, Kickoff.lastGo, Kickoff.goSpot = Kickoff.time, Kickoff.time, Kickoff.spot
	if source ~= "test" then Kickoff.fresh = false end -- this round has had its launch
	Kickoff.lastEvent = string.format("GO #%d (%s) in %s", Kickoff.count, source, tostring(Kickoff.slot))
end

-- Is `point` inside (or within `margin` of) this arena's box?
local function near(entry, point, margin)
	local p = entry.inverse:rotateVector(point - entry.position)
	return math.abs(p.x) <= entry.hx + margin and math.abs(p.y) <= entry.hy + margin
		and math.abs(p.z - entry.lift) <= entry.hz + margin
end

-- Call once per tick.
--   anchor   where the camera is (decides which arena is watched when there is no ball)
--   ballPos  position of the ball being followed / the ball at the kickoff spot, or nil
--   map      ArenaMap
--   settings { window = seconds of countdown to show, afterGo = seconds the kickoff cam stays after GO,
--              every = true to treat every countdown as a kickoff (not only the round-start launch) }
function Kickoff.update(dt, anchor, ballPos, map, settings)
	Kickoff.time += dt
	local now = Kickoff.time
	local window = settings.window or 5

	-- 1. Which arena?
	local slot, entry = nil, nil
	local point = ballPos or anchor
	if map ~= nil and map.available and point ~= nil then
		local okSlot, found = pcall(map.locate, point)
		if okSlot and found ~= nil then
			local candidate = map.entries[found]
			local okNear, isNear = pcall(near, candidate, point, 800)
			if candidate ~= nil and okNear and isNear then slot, entry = found, candidate end
		end
	end
	if slot ~= Kickoff.slot then
		-- a different arena (or none): nothing carries over, and the first reading never fires a GO
		Kickoff.slot, Kickoff.prev, Kickoff.watch = slot, nil, nil
		Kickoff.fresh, Kickoff.score, Kickoff.wasLive = false, nil, false
		if Kickoff.phase ~= "idle" or Kickoff.camActive then Kickoff.stop() end
	end
	if entry == nil then
		Kickoff.frame, Kickoff.base, Kickoff.spot, Kickoff.colors = nil, nil, nil, nil
		Kickoff.status, Kickoff.reading = "Not in an arena", "no arena"
		if Kickoff.testLeft ~= nil then Kickoff.stop("Test not played: the camera has to be in an arena") end
		return
	end

	-- 2. Arena frame and the kickoff spot.
	local okFrame = pcall(function()
		local up = entry.rotation:rotateVector(Vec3.new(0, 0, 1))
		Kickoff.frame = { entry = entry, up = up,
			side = entry.rotation:rotateVector(Vec3.new(1, 0, 0)),
			goal = entry.rotation:rotateVector(Vec3.new(0, 1, 0)) } -- toward the home (team 1) goal
		Kickoff.base = if entry.kickZ ~= nil then entry.position + (up * entry.kickZ) else nil
		local spot = Kickoff.base
		if ballPos ~= nil then
			local p = entry.inverse:rotateVector(ballPos - entry.position)
			if math.sqrt(p.x * p.x + p.y * p.y) <= 450 and p.z > -150 and p.z < (entry.kickZ or 435) + 700 then spot = ballPos end
		end
		-- Until GO the graphic sits on the ball (or the spot); after GO it stays where it went off.
		if Kickoff.phase ~= "go" then Kickoff.spot = spot end
	end)
	if not okFrame then
		Kickoff.frame, Kickoff.base, Kickoff.spot = nil, nil, nil
		Kickoff.status = "Arena geometry unavailable"
		if Kickoff.phase ~= "idle" or Kickoff.camActive then Kickoff.stop() end
		return
	end

	-- 3. Read the arena's clock.
	local running, timer = nil, nil
	local okData, data = pcall(function() return SpectatorGamemodes.getGamemodeData(slot) end)
	-- The data only has to be THERE, it does not have to be a plain Lua table. In the game
	-- it may well be an engine object (the goal detection, which is known to work in game, never
	-- asked for a table). The fields are read under a guard instead.
	local readable = false
	if okData and data ~= nil then
		readable = pcall(function()
			running = data.isGameRunning == true
			local value = data.secondaryTimeSeconds
			if type(value) == "number" and value == value and value >= 0 and value < 3600 then timer = value end
		end)
	end
	if readable then
		local okColors, colors = pcall(function()
			local a, b = data.teams[1], data.teams[2]
			return { a and a.teamColor and a.teamColor.primary, b and b.teamColor and b.teamColor.primary }
		end)
		Kickoff.colors = if okColors then colors else nil
		-- Is a round start pending? (see the note at the top of this file)
		local okScore, home, away, rounds = pcall(function()
			local a, b = data.teams[1], data.teams[2]
			return a.score, b.score, (a.roundsWon or 0) + (b.roundsWon or 0)
		end)
		if not okScore or type(home) ~= "number" or type(away) ~= "number" or type(rounds) ~= "number" then home, away, rounds = nil, nil, nil end
		local before = Kickoff.score
		if not running and now - Kickoff.lastGo > 3 then
			Kickoff.fresh, Kickoff.freshWhy = true, "game not running"
		elseif home ~= nil and before ~= nil then
			if before.home + before.away > 0 and home + away == 0 then
				Kickoff.fresh, Kickoff.freshWhy = true, "score back to 0 - 0"
			elseif rounds ~= before.rounds then
				Kickoff.fresh, Kickoff.freshWhy = true, "rounds won changed"
			end
		end
		Kickoff.score = if home ~= nil then { home = home, away = away, rounds = rounds } else nil
		Kickoff.reading = string.format("%s | game %s | timer %s | score %s | round start %s", tostring(slot),
			if running then "running" else "not running", if timer ~= nil then string.format("%.1f", timer) else "not reported",
			if home ~= nil then string.format("%d - %d", home, away) else "?",
			if Kickoff.fresh then "pending (" .. tostring(Kickoff.freshWhy) .. ")" else "done for this round")
	else
		running, timer = nil, nil
		Kickoff.prev, Kickoff.watch = nil, nil
		Kickoff.reading = tostring(slot) .. " | game data unavailable ("
			.. (if not okData then "the call failed" elseif data == nil then "nothing came back" else "a " .. type(data) .. " that could not be read") .. ")"
	end

	-- A countdown only counts once it has been seen going DOWN, and only while it keeps doing so
	-- (a timer parked on a number is not a kickoff).
	local watch = Kickoff.watch
	if timer ~= nil and timer > 0.02 then
		if watch == nil or timer > watch.value + 0.05 then
			watch = { value = timer, moved = now, falling = false }
		elseif timer < watch.value - 0.0005 then
			watch.value, watch.moved, watch.falling = timer, now, true
		end
	else
		watch = nil
	end
	Kickoff.watch = watch
	local live = watch ~= nil and watch.falling and now - watch.moved <= 1.6

	-- 4. Countdown / GO.
	local prev = Kickoff.prev
	local counting, goSource, remaining = false, nil, 0
	-- only the round-start launch counts as a kickoff, unless every countdown was asked for
	local allowed = settings.every == true or Kickoff.fresh == true
	local midRound = false
	if Kickoff.testLeft ~= nil then
		Kickoff.testLeft -= dt
		if Kickoff.testLeft <= 0 then
			Kickoff.testLeft, goSource = nil, "test"
		else
			counting, remaining = true, Kickoff.testLeft
		end
	elseif Kickoff.source == "test" and Kickoff.phase ~= "idle" then
		-- a test's GO burst is playing: real signals wait until it has finished
	elseif live and timer <= window then
		if allowed then counting, remaining = true, timer else midRound = true end
	elseif prev ~= nil and prev.live and prev.timer ~= nil and prev.timer <= 1.6 and timer ~= nil and timer <= 0.02 then
		if allowed then goSource = "countdown reached zero" end
	elseif prev ~= nil and prev.running == false and running == true and (timer == nil or timer <= 0.02)
		and now - Kickoff.lastGo > 3 then
		if allowed then goSource = "round started" end
	end
	if midRound and not Kickoff.wasLive then
		Kickoff.ignored += 1
		Kickoff.lastIgnored = string.format("Mid-round timer #%d in %s (not a round start, nothing drawn)", Kickoff.ignored, tostring(slot))
	end
	Kickoff.wasLive = midRound

	if counting then
		if Kickoff.phase ~= "count" then
			arm(if Kickoff.testLeft ~= nil then "test" else "countdown", if Kickoff.testLeft ~= nil then Kickoff.testTotal else remaining)
			Kickoff.lastEvent = string.format("Countdown #%d showing in %s", Kickoff.count, tostring(slot))
		end
		Kickoff.remaining = remaining
		local number = math.max(math.ceil(remaining - 0.0005), 1)
		if number ~= Kickoff.number then Kickoff.number, Kickoff.numberAt = number, now end
		Kickoff.countAge += dt
	elseif goSource ~= nil then
		go(goSource)
	elseif Kickoff.phase == "count" then
		Kickoff.stop(string.format("Countdown #%d stopped before zero (no GO)", Kickoff.count))
	elseif Kickoff.phase == "go" then
		Kickoff.goAge += dt
		if Kickoff.goAge >= GO_SECONDS then Kickoff.phase = "idle" end
	end
	if readable then Kickoff.prev = { timer = timer, running = running, live = live } end

	-- 5. Kickoff cam: on from the moment the countdown shows until a little after GO (sooner if the
	-- ball has already been knocked well away from the spot).
	if Kickoff.camActive then
		Kickoff.camAge += dt
		if Kickoff.phase ~= "count" then
			if Kickoff.wentAt == nil then
				Kickoff.camActive = false
			else
				local since = now - Kickoff.wentAt
				local moved = ballPos ~= nil and Kickoff.goSpot ~= nil and (ballPos - Kickoff.goSpot):length() > 900
				if since >= (settings.afterGo or 3) or (moved and since >= 0.6) then Kickoff.camActive = false end
			end
		end
	end

	Kickoff.status = if Kickoff.phase == "count" then string.format("Kickoff in %.1f", Kickoff.remaining or 0)
		elseif Kickoff.phase == "go" then "GO!"
		elseif midRound then string.format("Mid-round timer %.1f (not a round start, nothing drawn)", timer or 0)
		elseif Kickoff.spot == nil then "Watching (this arena layout has no known kickoff spot)"
		else "Watching for a kickoff"
end

-- ---------------------------------------------------------------------------------------------
-- Kickoff cam
-- ---------------------------------------------------------------------------------------------

-- Returns position, look-at point, up vector and field of view for the kickoff shot, or nil when
-- there is no kickoff shot right now.
--   style     "Sideline" | "Orbit" | "Top Down"
--   settings  { distance, height, fov, orbitSpeed (degrees per second) }
--   eye       where the camera is now (picks the nearer side / the orbit's starting angle)
function Kickoff.pose(style, settings, eye, map)
	local frame = Kickoff.frame
	if not Kickoff.camActive or frame == nil then return nil end
	if Kickoff.camCentre == nil then Kickoff.camCentre = Kickoff.base or Kickoff.spot end
	local centre = Kickoff.camCentre
	if centre == nil then return nil end
	local entry = frame.entry
	if Kickoff.camSide == nil then
		local across, along = 1, 0
		if eye ~= nil then
			across, along = (eye - centre):dot(frame.side), (eye - centre):dot(frame.goal)
		end
		Kickoff.camSide = if across < 0 then -1 else 1
		Kickoff.camAngle = if math.abs(across) + math.abs(along) > 1 then math.atan2(along, across) else 0
	end
	-- stay inside the walls and under the roof
	local distance = math.min(settings.distance or 1900, math.max(entry.hx - 300, 300))
	local centreZ = (centre - entry.position):dot(frame.up)
	local headroom = math.max(entry.lift + entry.hz - 120 - centreZ, 60)
	local height = math.min(settings.height or 450, headroom)
	local position
	if style == "Orbit" then
		local radius = math.min(distance, math.max((entry.goalY or entry.hy) - 500, 300))
		local angle = Kickoff.camAngle + (math.rad(settings.orbitSpeed or 22) * Kickoff.camAge)
		position = centre + (frame.side * (math.cos(angle) * radius)) + (frame.goal * (math.sin(angle) * radius)) + (frame.up * height)
	elseif style == "Top Down" then
		-- high over the spot, leaning a little to one side so "up" on screen is never ambiguous
		local high = math.min(math.max(distance * 0.6, 600), headroom)
		position = centre + (frame.up * high) + (frame.side * (Kickoff.camSide * high * 0.25))
	else
		position = centre + (frame.side * (Kickoff.camSide * distance)) + (frame.up * height)
	end
	if map ~= nil then
		local okInside, inside = pcall(map.keepInside, position, centre, 90, 380, 70)
		if okInside and inside ~= nil then position = inside end
	end
	return position, centre, frame.up, settings.fov or 100
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

-- An arc of a circle in the plane (ax, ay); `colourAt(angle)` may pick a colour per segment.
local function arc(line, centre, ax, ay, radius, from, to, segments, r, g, b, width, colourAt)
	local previous = centre + (ax * (math.cos(from) * radius)) + (ay * (math.sin(from) * radius))
	for i = 1, segments do
		local angle = from + ((to - from) * i / segments)
		local point = centre + (ax * (math.cos(angle) * radius)) + (ay * (math.sin(angle) * radius))
		if colourAt ~= nil then r, g, b = colourAt(from + ((to - from) * (i - 0.5) / segments)) end
		line(previous, point, r, g, b, width)
		previous = point
	end
end

-- Seven-segment digits and "GO!", as strokes in a box 1 tall (x1, y1, x2, y2).
local SEGMENTS = { a = { 0, 1, 0.6, 1 }, b = { 0.6, 1, 0.6, 0.5 }, c = { 0.6, 0.5, 0.6, 0 }, d = { 0, 0, 0.6, 0 },
	e = { 0, 0, 0, 0.5 }, f = { 0, 0.5, 0, 1 }, g = { 0, 0.5, 0.6, 0.5 } }
local DIGITS = { [0] = "abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc", "abc", "abcdefg", "abcdfg" }
local GO_TEXT = {
	{ 0.75, 0.85, 0.35, 1 }, { 0.35, 1, 0, 0.5 }, { 0, 0.5, 0.35, 0 }, { 0.35, 0, 0.75, 0.2 }, { 0.75, 0.2, 0.75, 0.5 }, { 0.75, 0.5, 0.45, 0.5 }, -- G
	{ 1.25, 1, 1.5, 1 }, { 1.5, 1, 1.75, 0.72 }, { 1.75, 0.72, 1.75, 0.28 }, { 1.75, 0.28, 1.5, 0 }, { 1.5, 0, 1.25, 0 }, { 1.25, 0, 1.0, 0.28 }, { 1.0, 0.28, 1.0, 0.72 }, { 1.0, 0.72, 1.25, 1 }, -- O
	{ 2.1, 1, 2.1, 0.36 }, { 2.1, 0.13, 2.1, 0 }, -- !
}

-- Strokes centred on `centre`, facing the camera (bx = right on screen, by = up on screen). Each
-- stroke is drawn a touch long so thick strokes meet at the corners.
local function strokes(line, centre, bx, by, height, list, width, r, g, b, thickness)
	for _, stroke in ipairs(list) do
		local x1, y1, x2, y2 = stroke[1] - (width * 0.5), stroke[2] - 0.5, stroke[3] - (width * 0.5), stroke[4] - 0.5
		local dx, dy = x2 - x1, y2 - y1
		local length = math.sqrt(dx * dx + dy * dy)
		if length > 0.0001 then
			local extra = (thickness * 0.45) / height / length
			x1, y1, x2, y2 = x1 - (dx * extra), y1 - (dy * extra), x2 + (dx * extra), y2 + (dy * extra)
		end
		line(centre + (bx * (x1 * height)) + (by * (y1 * height)), centre + (bx * (x2 * height)) + (by * (y2 * height)), r, g, b, thickness)
	end
end

local function numberStrokes(value)
	local text = tostring(math.clamp(math.floor(value + 0.5), 0, 99))
	local list, x = {}, 0
	for i = 1, #text do
		local digit = tonumber(string.sub(text, i, i))
		local pattern = DIGITS[digit]
		for j = 1, #pattern do
			local segment = SEGMENTS[string.sub(pattern, j, j)]
			table.insert(list, { segment[1] + x, segment[2], segment[3] + x, segment[4] })
		end
		x += 0.9
	end
	return list, x - 0.3
end

local styles = {}

-- COUNTDOWN RING ---------------------------------------------------------------------------------
-- A two-colour ring around the ball (each team's colour on its own side) that drains like a clock
-- as the countdown runs, with a ripple across the pitch on every second. On GO the ring blows
-- outward, two team-coloured shockwaves cross the floor and sparks fly.
styles["Countdown Ring"] = function(k, line)
	local S, s, radius = k.spot, k.scale, 180 * k.scale
	if k.phase == "count" then
		arc(line, S, k.bx, k.by, radius, 0, TAU, 16, k.dim[1], k.dim[2], k.dim[3], 3 * s) -- the part that has drained
		local sweep = TAU * k.left
		local segments = math.max(2, math.ceil(28 * k.left))
		arc(line, S, k.bx, k.by, radius, math.pi * 0.5, (math.pi * 0.5) - sweep, segments, 1, 1, 1, (13 + (8 * k.pulse)) * s, k.screenSide)
		arc(line, S, k.bx, k.by, 62 * s, 0, TAU, 12, k.ink[1], k.ink[2], k.ink[3], 4 * s) -- collar round the ball
		local ripple = radius * (1.1 + (2.0 * easeOut(k.second)))
		arc(line, S, k.goal, k.side, ripple, 0, TAU, 20, 1, 1, 1, ((9 * (1 - k.second)) + 0.6) * s, k.pitchSide)
		return radius + (70 * s)
	end
	local a, fade = k.age, 1 - k.gone
	local burst = easeOut(a / 0.9)
	arc(line, S, k.bx, k.by, radius * (1 + (1.3 * burst)), 0, TAU, 24, 1, 1, 1, 18 * s * fade, k.screenSide)
	if a < 1.2 then
		arc(line, S, k.goal, k.side, (150 + (700 * easeOut(a / 1.2))) * s, 0, TAU, 24, k.home[1], k.home[2], k.home[3], 22 * s * (1 - (a / 1.2)))
	end
	if a > 0.12 and a < 1.32 then
		local b = (a - 0.12) / 1.2
		arc(line, S + (k.up * (40 * s)), k.goal, k.side, (150 + (500 * easeOut(b))) * s, 0, TAU, 24, k.away[1], k.away[2], k.away[3], 20 * s * (1 - b))
	end
	for i = 1, 14 do
		local angle = TAU * (i + 0.5) / 14
		local direction = (k.bx * math.cos(angle)) + (k.by * math.sin(angle))
		local inner = radius * (0.6 + (1.6 * burst))
		local colour = if i % 2 == 0 then k.home else k.away
		line(S + (direction * inner), S + (direction * (inner + (170 * s * fade))), colour[1], colour[2], colour[3], 10 * s * fade)
	end
	return radius + (70 * s)
end

-- FACE-OFF ---------------------------------------------------------------------------------------
-- A row of chevrons on each team's side of the ball, pointing at it, in that team's colour. They
-- march in one place per second and the row gets one shorter each second: three each side means
-- three seconds. On GO both teams' charges shoot through the middle toward the far goal.
styles["Face-Off"] = function(k, line)
	local S, s = k.spot, k.scale
	if k.phase == "count" then
		local shown = math.min(k.number, 5)
		local slide = 1 - k.second
		for teamSide = 1, 2 do
			local sign = if teamSide == 1 then 1 else -1
			local colour = if teamSide == 1 then k.home else k.away
			for i = 1, shown do
				local tip = S + (k.goal * (sign * (230 + (120 * (i - 1 + slide))) * s))
				local back = tip + (k.goal * (sign * 78 * s))
				local arm = 96 * s
				local glow = 1 - (0.06 * (i - 1))
				local width = (if i == 1 then 15 else 11) * s
				local r, g, b = colour[1] * glow, colour[2] * glow, colour[3] * glow
				line(tip, back + (k.up * arm), r, g, b, width)
				line(tip, back - (k.up * arm), r, g, b, width)
				line(tip, back + (k.side * arm), r, g, b, width)
				line(tip, back - (k.side * arm), r, g, b, width)
			end
		end
		-- the hoop the ball sits in, thumping on each second
		arc(line, S, k.bx, k.by, 150 * s, 0, TAU, 20, k.ink[1], k.ink[2], k.ink[3], (4 + (11 * k.pulse)) * s)
		return 240 * s
	end
	local a, fade = k.age, 1 - k.gone
	for teamSide = 1, 2 do
		local sign = if teamSide == 1 then -1 else 1 -- home starts on +goal and charges toward -goal
		local colour = if teamSide == 1 then k.home else k.away
		for j = 1, 6 do
			local angle = TAU * j / 6
			local offset = ((k.side * math.cos(angle)) + (k.up * math.sin(angle))) * (55 * s)
			local head = S + offset + (k.goal * (sign * (-250 + (1700 * a * (0.8 + (0.07 * j)))) * s))
			local tail = head - (k.goal * (sign * ((380 * fade) + 60) * s))
			line(tail, head, colour[1], colour[2], colour[3], 12 * s * fade)
		end
	end
	if a < 0.9 then
		arc(line, S, k.bx, k.by, (150 + (420 * easeOut(a / 0.9))) * s, 0, TAU, 24, k.ink[1], k.ink[2], k.ink[3], 20 * s * (1 - (a / 0.9)))
	end
	for i = 1, 12 do
		local angle = TAU * (i + 0.25) / 12
		local direction = (k.bx * math.cos(angle)) + (k.by * math.sin(angle))
		local inner = (120 + (400 * easeOut(a / 1.1))) * s
		local colour = if i % 2 == 0 then k.home else k.away
		line(S + (direction * inner), S + (direction * (inner + (150 * s * fade))), colour[1], colour[2], colour[3], 9 * s * fade)
	end
	return 240 * s
end

-- BEACON -----------------------------------------------------------------------------------------
-- A slowly turning pillar of light through the ball, with rings sliding down it: one lands on the
-- ball on every second. On GO the pillar fires upward, the rings race up it and a fountain of
-- sparks arcs out over the pitch.
styles["Beacon"] = function(k, line)
	local S, s = k.spot, k.scale
	local top, bottom = 560 * s, 120 * s
	local spin = k.clock * 0.9
	if k.phase == "count" then
		for i = 1, 6 do
			local angle = spin + (TAU * i / 6)
			local offset = ((k.side * math.cos(angle)) + (k.goal * math.sin(angle))) * (62 * s)
			local colour = if i % 2 == 0 then k.home else k.away
			line(S + offset - (k.up * bottom), S + offset + (k.up * top), colour[1], colour[2], colour[3], 6 * s)
		end
		for j = 0, 2 do
			local high = ((1 - k.second) + (j / 3)) % 1 -- 1 = top of the pillar, 0 = on the ball
			arc(line, S + (k.up * (high * top)), k.goal, k.side, (75 + (190 * high)) * s, 0, TAU, 16, 1, 1, 1, (5 + (9 * (1 - high))) * s, k.pitchSide)
		end
		arc(line, S, k.goal, k.side, (120 + (60 * k.pulse)) * s, 0, TAU, 18, k.ink[1], k.ink[2], k.ink[3], (5 + (12 * k.pulse)) * s)
		return 110 * s, 300 * s -- the numbers stand beside the pillar, not on it
	end
	local a, fade = k.age, 1 - k.gone
	local burst = easeOut(a / 0.8)
	for i = 1, 6 do
		local angle = spin + (TAU * i / 6)
		local offset = ((k.side * math.cos(angle)) + (k.goal * math.sin(angle))) * ((55 + (40 * burst)) * s)
		local colour = if i % 2 == 0 then k.home else k.away
		line(S + offset, S + offset + (k.up * (top * (1 + (0.4 * burst)))), colour[1], colour[2], colour[3], 14 * s * fade)
	end
	for j = 0, 2 do
		local high = clamp01((a * 1.6) - (j * 0.18)) * 1.15
		arc(line, S + (k.up * (high * top)), k.goal, k.side, (90 + (150 * high)) * s, 0, TAU, 16, 1, 1, 1, 12 * s * fade, k.pitchSide)
	end
	for i = 1, 14 do
		local angle = TAU * (i + 0.5) / 14
		local direction = (k.side * math.cos(angle)) + (k.goal * math.sin(angle))
		local function at(time)
			return S + (direction * (420 * time * s)) + (k.up * (((560 * time) - (700 * time * time)) * s))
		end
		local colour = if i % 2 == 0 then k.home else k.away
		line(at(math.max(a - 0.07, 0)), at(a), colour[1], colour[2], colour[3], 11 * s * fade)
	end
	return 60 * s, 520 * s
end

-- LOCK-ON ----------------------------------------------------------------------------------------
-- Targeting brackets around the ball, team-coloured by side, turning slowly and closing in as the
-- clock runs down, with a radar ping every second and a dial of ticks that empties. On GO the
-- brackets snap outward and a flash ring opens.
styles["Lock-On"] = function(k, line)
	local S, s = k.spot, k.scale
	local turn = k.clock * 0.8
	local ax = (k.bx * math.cos(turn)) + (k.by * math.sin(turn))
	local ay = (k.by * math.cos(turn)) - (k.bx * math.sin(turn))
	local function brackets(half, width)
		local arm = half * 0.42
		for q = 1, 4 do
			local sx = if q == 1 or q == 4 then 1 else -1
			local sy = if q <= 2 then 1 else -1
			local corner = S + (ax * (sx * half)) + (ay * (sy * half))
			local colour = if (corner - S):dot(k.bx) * k.homeOnRight >= 0 then k.home else k.away
			line(corner, corner - (ax * (sx * arm)), colour[1], colour[2], colour[3], width)
			line(corner, corner - (ay * (sy * arm)), colour[1], colour[2], colour[3], width)
		end
	end
	if k.phase == "count" then
		local half = (150 + (300 * k.left)) * s
		brackets(half, (12 + (7 * k.pulse)) * s)
		-- inner diamond turning the other way
		local back = -turn * 1.6
		local dx = (k.bx * math.cos(back)) + (k.by * math.sin(back))
		local dy = (k.by * math.cos(back)) - (k.bx * math.sin(back))
		arc(line, S, dx, dy, 105 * s, 0, TAU, 4, k.ink[1], k.ink[2], k.ink[3], 5 * s)
		-- fixed cross ticks
		for q = 0, 3 do
			local direction = if q == 0 then k.bx elseif q == 1 then k.by elseif q == 2 then k.bx * -1 else k.by * -1
			line(S + (direction * (half + (50 * s))), S + (direction * (half + (130 * s))), k.ink[1], k.ink[2], k.ink[3], 5 * s)
		end
		-- radar ping
		arc(line, S, k.bx, k.by, mix(110 * s, half * 1.35, easeOut(k.second)), 0, TAU, 20, k.ink[1], k.ink[2], k.ink[3], ((8 * (1 - k.second)) + 0.5) * s)
		-- dial
		local lit = math.ceil(12 * k.left - 0.0001)
		for i = 1, 12 do
			local angle = (math.pi * 0.5) - (TAU * (i - 0.5) / 12)
			local direction = (k.bx * math.cos(angle)) + (k.by * math.sin(angle))
			local colour = if math.cos(angle) * k.homeOnRight >= 0 then k.home else k.away
			if i <= lit then
				line(S + (direction * (520 * s)), S + (direction * (575 * s)), colour[1], colour[2], colour[3], 9 * s)
			else
				line(S + (direction * (535 * s)), S + (direction * (560 * s)), k.dim[1], k.dim[2], k.dim[3], 4 * s)
			end
		end
		return half + (110 * s)
	end
	local a, fade = k.age, 1 - k.gone
	local burst = easeOut(a / 0.7)
	brackets((150 + (520 * burst)) * s, 14 * s * fade)
	arc(line, S, k.bx, k.by, (110 + (380 * easeOut(a / 1.0))) * s, 0, TAU, 24, 1, 1, 1, 16 * s * fade, k.screenSide)
	for i = 1, 8 do
		local angle = TAU * (i + 0.5) / 8
		local direction = (k.bx * math.cos(angle)) + (k.by * math.sin(angle))
		local inner = (90 + (360 * burst)) * s
		local colour = if i % 2 == 0 then k.home else k.away
		line(S + (direction * inner), S + (direction * (inner + (160 * s * fade))), colour[1], colour[2], colour[3], 10 * s * fade)
	end
	return 300 * s
end

-- Which style a kickoff uses ("Cycle" steps through them, one per kickoff).
function Kickoff.styleFor(choice)
	if styles[choice] ~= nil then return choice end
	if type(choice) == "string" and string.sub(choice, 1, 5) == "Cycle" then
		return Kickoff.styles[((math.max(Kickoff.count, 1) - 1) % #Kickoff.styles) + 1]
	end
	return Kickoff.styles[1]
end

-- Draws the current kickoff graphic (nothing when idle).
--   line(a, b, r, g, b, thickness)
--   ctx { eye = camera position, scale, style, numbers = show 3-2-1 / GO!, home = {r,g,b}, away = {r,g,b},
--         ink = {r,g,b} for the neutral parts and lettering, dim = {r,g,b} for the faint parts (both optional) }
function Kickoff.draw(line, ctx)
	local frame, spot = Kickoff.frame, Kickoff.spot
	if Kickoff.phase == "idle" or frame == nil or spot == nil then return end
	if Kickoff.phase == "go" and Kickoff.goSpot ~= nil then spot = Kickoff.goSpot end
	-- Size: drawn for a camera about 1950 away (the sideline kickoff cam) and scaled with the
	-- camera's real distance, so it takes up about the same part of the picture from a close ball
	-- cam as from the wide kickoff shot (within limits: it never gets tiny or enormous).
	local scale = (ctx.scale or 1) * 1.5
	-- Screen axes at the spot, so rings and lettering face the camera wherever it is.
	local bx, by = frame.goal, frame.up
	if ctx.eye ~= nil then
		local gap = (spot - ctx.eye):length()
		if gap == gap then scale *= math.clamp(gap / 1950, 0.4, 1.6) end
		local toward = norm(spot - ctx.eye, nil)
		if toward ~= nil then
			local right = norm(frame.up:cross(toward), nil) or norm(frame.goal:cross(toward), frame.side)
			bx, by = right, norm(toward:cross(right), frame.up)
		end
	end
	local home, away = ctx.home or { 0.2, 0.55, 1.0 }, ctx.away or { 1.0, 0.42, 0.05 }
	local homeOnRight = if frame.goal:dot(bx) < 0 then -1 else 1 -- which side of the screen the home goal is on
	local total = math.max(Kickoff.total or 1, 0.5)
	local second = clamp01(Kickoff.time - (Kickoff.numberAt or Kickoff.time)) -- progress through this second
	local k = {
		phase = Kickoff.phase, spot = spot, scale = scale, clock = Kickoff.time,
		up = frame.up, goal = frame.goal, side = frame.side, bx = bx, by = by,
		home = home, away = away, ink = ctx.ink or { 1, 1, 1 }, dim = ctx.dim or { 0.30, 0.32, 0.38 }, homeOnRight = homeOnRight,
		number = Kickoff.number or 1, second = second, pulse = 1 - clamp01(second / 0.35),
		left = clamp01((Kickoff.remaining or 0) / total),
		age = Kickoff.goAge or 0, gone = clamp01((Kickoff.goAge or 0) / GO_SECONDS),
	}
	k.screenSide = function(angle) -- colour by side of the screen (rings that face the camera)
		local colour = if math.cos(angle) * homeOnRight >= 0 then home else away
		return colour[1], colour[2], colour[3]
	end
	k.pitchSide = function(angle) -- colour by half of the pitch (rings lying flat; angle 0 = home goal)
		local colour = if math.cos(angle) >= 0 then home else away
		return colour[1], colour[2], colour[3]
	end
	local lift, shift = styles[Kickoff.styleFor(ctx.style)](k, line)
	if ctx.numbers == false then return end
	local textSpot = spot + (bx * (shift or 0))
	local ink = k.ink
	if k.phase == "count" then
		local list, width = numberStrokes(k.number)
		local height = 250 * scale * (1 + (0.28 * k.pulse))
		local r, g, b = ink[1], ink[2], ink[3]
		if k.number <= 3 and ctx.ink == nil then r, g, b = 1.0, 0.86, 0.25 end -- last three seconds
		strokes(line, textSpot + (by * (lift + (height * 0.5))), bx, by, height, list, width, r, g, b, height * 0.13)
	elseif k.age < 1.25 then
		local pop = easeOutBack(k.age / 0.16) * clamp01((1.25 - k.age) / 0.25)
		local height = 300 * scale * pop
		if height > 1 then
			local r, g, b = 0.55, 1.0, 0.45
			if ctx.ink ~= nil then r, g, b = ink[1], ink[2], ink[3] end
			strokes(line, textSpot + (by * (lift + (150 * scale))), bx, by, height, GO_TEXT, 2.1, r, g, b, height * 0.13)
		end
	end
end

return Kickoff
