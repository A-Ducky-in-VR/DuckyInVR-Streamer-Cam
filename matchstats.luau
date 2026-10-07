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
-- None of his code is copied here. Taken from Caster Camera: the definitions of the stats, the
-- boost numbers and the 4v4 boost pad positions. The code itself is written for Streamer Cam.
--
-- Streamer Cam match stats for "Send Overlay Info" (used only by overlay.luau, only while that
-- feature is on). The game does not report any of these, so every one is WORKED OUT from where the
-- players and the ball are each frame. They are estimates, the same kind Caster Camera sends.
--
--   possession        whoever touched the ball last has it, until someone else does or 3 seconds
--                     pass with nobody on it (then it is loose). Team and player share of the time.
--   dribbleMeters     how far a player travelled while they had it.
--   passes            the ball goes from one player to a team-mate (counted for the passer).
--   possessionsWon /  the ball goes from one team to the other (won for the player who took it,
--   possessionsLost   lost for the player who had it).
--   shots             a player's touch sends the ball at the other team's goal mouth (straight, or
--                     off one bounce), arriving within 3 seconds. One per touch. A goal with no
--                     shot counted for it counts as one.
--   saves             a defender gets a touch on a ball that was heading into their goal, within
--                     6 m of it, and no goal follows in the next 0.7 s.
--   goals, assists,   the last player of the scoring team on the ball; the team-mate who passed it
--   lastShotInfo      to them if they received it under 5 seconds before the goal; the ball's top
--                     speed after the last touch; distance from that touch to the goal.
--   boost             starts at 100, drains over 4 seconds of thruster use, refilled for everyone
--                     at a round start, a goal and the start of overtime. Boost pads are only
--                     known for 4v4 arenas, so in the other layouts it reads low between goals.
--
-- The definitions, the boost numbers and the 4v4 pad positions follow Caster Camera's main.luau,
-- possession.luau, boost.luau and gamemodes.luau (MIT licence, (c) dennssen,
-- https://github.com/dennssen/CasterCamera). The code is written for Streamer Cam.
local Stats = {}

local CONTACT = 40              -- a head or hand this close to the ball's path this frame is a touch
local CONTEST_SECONDS = 0.2     -- the ball does not change hands while the old holder still had a touch this recently
local POSSESSION_TIMEOUT = 3    -- seconds with nobody on the ball before it counts as loose
local SHOT_SEPARATION = 30      -- the ball must be this far from where it was touched to be "released"
local SHOT_MIN_SPEED = 150      -- slower than this is a rolling ball, not a shot
local SHOT_SECONDS = 3          -- it must reach the goal within this long at its current speed
local SAVE_RANGE = 600          -- a save happens within this distance of the goal
local SAVE_LIVE_SECONDS = 0.4   -- ...on a ball that was heading in this recently
local SAVE_CONFIRM_SECONDS = 0.7 -- ...and counts once no goal has followed for this long
local ASSIST_SECONDS = 5        -- the scorer must have received the pass within this long of the goal
local SCORER_MAX_AGE = 10       -- a touch older than this is not credited with the goal
local MAX_FRAME_MOVE = 500      -- a bigger jump in one frame is a teleport / respawn, not movement

local BOOST_DRAIN_PER_SECOND = 25 -- 4 seconds of thrust empties a full tank
local PAD = { small = { gain = 22.5, cooldown = 6, hx = 38.5, hy = 38.5, hz = 25 }, big = { gain = 100, cooldown = 10, hx = 60, hy = 60, hz = 50 } }

-- Goal mouths per arena layout, keyed by the centre-to-goal distance ArenaMap already knows:
-- height of the goal centre above the arena origin, and the mouth's width and height.
local GOALS = {
	[3250] = { z = 175, width = 500, height = 225 }, -- 3v3
	[4085] = { z = 270, width = 450, height = 225 }, -- 4v4
	[5295] = { z = 175, width = 890, height = 300 }, -- driftblitz
	[8200] = { z = 585, width = 600, height = 600 }, -- zdrift
}
-- Boost pads (x, y, z in the arena's own frame). Only 4v4 has been measured.
local PADS = {
	[4085] = {
		{ -1501, -3475, 180, "big" }, { 0, -3700, 170, "small" }, { 800, -2975, 139, "small" }, { -800, -2975, 139, "small" },
		{ 1501, -3475, 180, "big" }, { 2400, -900, 417, "small" }, { 2400, 0, 417, "small" }, { 2400, 900, 417, "small" },
		{ 0, 500, 37, "small" }, { 0, 0, 150, "small" }, { -500, 0, 37, "small" }, { 0, -500, 37, "small" }, { 500, 0, 37, "small" },
		{ 1330, 0, 550, "small" }, { 705, -660, 425, "small" }, { -6, -1170, 698, "small" }, { -1360, 0, 555, "small" },
		{ -703, 656, 426, "small" }, { -8, 1171, 697, "small" }, { -1501, 3475, 180, "big" }, { 1501, 3475, 180, "big" },
		{ 0, 3700, 170, "small" }, { 800, 2975, 139, "small" }, { -800, 2975, 139, "small" }, { -2450, 0, 417, "small" },
		{ -2450, 900, 417, "small" }, { -2450, -900, 417, "small" },
	},
}

local function finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function newStats()
	return { goals = 0, saves = 0, assists = 0, shots = 0, passes = 0, possessionsWon = 0, possessionsLost = 0,
		possession = 0, dribbleMeters = 0 }
end

-- Distance from a point to the segment a-b.
local function segmentGap(point, a, b)
	local segment = b - a
	local lengthSq = segment:dot(segment)
	if lengthSq < 0.0001 then return (point - a):length() end
	local t = math.clamp((point - a):dot(segment) / lengthSq, 0, 1)
	return (point - (a + (segment * t))):length()
end

-- Does the segment a-b (arena frame) pass through the box centred on `pad`?
local function segmentHitsBox(a, b, pad, size)
	local tMin, tMax = 0, 1
	local origin = { a.x - pad[1], a.y - pad[2], a.z - pad[3] }
	local delta = { b.x - a.x, b.y - a.y, b.z - a.z }
	local extent = { size.hx, size.hy, size.hz }
	for axis = 1, 3 do
		if math.abs(delta[axis]) < 1e-9 then
			if origin[axis] < -extent[axis] or origin[axis] > extent[axis] then return false end
		else
			local t1 = (-extent[axis] - origin[axis]) / delta[axis]
			local t2 = (extent[axis] - origin[axis]) / delta[axis]
			if t1 > t2 then t1, t2 = t2, t1 end
			tMin, tMax = math.max(tMin, t1), math.min(tMax, t2)
			if tMin > tMax then return false end
		end
	end
	return true
end

-- ---------------------------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------------------------

local function record(name)
	local entry = Stats.players[name]
	if entry == nil then
		-- players start with a full tank, so anyone not seen before starts topped up
		entry = { stats = newStats(), seconds = 0, boost = 100 }
		Stats.players[name] = entry
	end
	return entry
end

-- Nobody has the ball: after a goal, at a round start.
function Stats.clearContacts()
	Stats.holder = nil
	Stats.last = { [0] = {}, [1] = {} }
	Stats.touched = {}
	Stats.previousBall, Stats.live, Stats.dribbleName, Stats.dribbleFrom = nil, nil, nil, nil
	Stats.shotArmed, Stats.separated, Stats.peak = false, false, 0
end

-- New match or a different arena: everything starts from nothing.
function Stats.reset()
	Stats.players = {}
	Stats.seconds = { home = 0, away = 0, loose = 0 }
	Stats.padReady = {}
	Stats.pendingSave, Stats.lastSaveAt = nil, nil
	Stats.clearContacts()
end

function Stats.refill()
	for _, entry in pairs(Stats.players) do entry.boost = 100 end
end

function Stats.statsFor(name) return record(name).stats end
function Stats.boostFor(name) return math.clamp(record(name).boost, 0, 100) end

-- Share of the time each team has had the ball, 0-100 (loose time counts toward neither).
function Stats.teamPossession()
	local seconds = Stats.seconds
	local total = seconds.home + seconds.away + seconds.loose
	if total <= 0 then return 0, 0 end
	return math.clamp(seconds.home / total * 100, 0, 100), math.clamp(seconds.away / total * 100, 0, 100)
end

-- ---------------------------------------------------------------------------------------------
-- Per frame
-- ---------------------------------------------------------------------------------------------

-- `player` touched the ball this frame and is the nearest one to it.
local function contact(player, now, ballPos, counting)
	local holder = Stats.holder
	local side = Stats.last[player.team]
	if holder ~= nil and holder.name == player.name then
		-- same player again: a fresh touch after letting go can be a new shot
		if Stats.separated then Stats.shotArmed, Stats.separated, Stats.peak = true, false, 0 end
		holder.time, holder.place = now, ballPos
		if side.current ~= nil and side.current.name == player.name then side.current.time, side.current.place = now, ballPos end
		return
	end
	-- two players on it at once: it stays with whoever had it until they are off it
	if holder ~= nil and now - (Stats.touched[holder.name] or -math.huge) < CONTEST_SECONDS then return end
	local from = nil
	if holder ~= nil then
		if holder.team == player.team then
			from = holder.name
			if counting then record(holder.name).stats.passes += 1 end
		elseif counting then
			record(player.name).stats.possessionsWon += 1
			record(holder.name).stats.possessionsLost += 1
		end
	end
	side.current = { name = player.name, time = now, first = now, place = ballPos, from = from }
	Stats.holder = { name = player.name, team = player.team, time = now, place = ballPos }
	Stats.shotArmed, Stats.separated, Stats.peak = true, false, 0
	Stats.dribbleName, Stats.dribbleFrom = nil, nil
end

-- Is the ball heading into a goal mouth? Returns the index of the team DEFENDING that goal
-- (0 = the home goal, at +Y in the arena frame), or nil. Straight line, or off one bounce.
local function onTarget(ctx, goal, ballLocal, velocityLocal)
	local speed = velocityLocal:length()
	if not finite(speed) or speed < SHOT_MIN_SPEED then return nil end
	local entry = ctx.entry
	local function crossing(origin, direction, reach)
		if math.abs(direction.y) < 0.05 then return nil end
		local sign = if direction.y > 0 then 1 else -1
		local distance = ((sign * entry.goalY) - origin.y) / direction.y
		if distance <= 0 or distance > reach then return nil end
		local x, z = origin.x + (direction.x * distance), origin.z + (direction.z * distance)
		if math.abs(x) <= goal.width * 0.5 and math.abs(z - goal.z) <= goal.height * 0.5 then
			return (if sign > 0 then 0 else 1), distance
		end
		return nil
	end
	local direction = velocityLocal * (1 / speed)
	local reach = speed * SHOT_SECONDS
	local defending, distance = crossing(ballLocal, direction, reach)
	if ctx.castRay ~= nil then
		-- is something in the way first? then follow one bounce off it
		local length = distance or math.min(reach, entry.goalY * 2)
		local okRay, hit = pcall(function()
			return ctx.castRay(ctx.ballPos, ctx.ballPos + (entry.rotation:rotateVector(direction) * length))
		end)
		if okRay and hit ~= nil and hit.successful and hit.position ~= nil then
			local hitLocal = entry.inverse:rotateVector(hit.position - entry.position)
			local travelled = (hitLocal - ballLocal):length()
			if finite(travelled) and (distance == nil or travelled < distance - 40) then
				defending = nil
				if hit.normal ~= nil then
					local normal = entry.inverse:rotateVector(hit.normal)
					local reflected = direction - (normal * (2 * direction:dot(normal)))
					local length2 = reflected:length()
					if finite(length2) and length2 > 0.001 then
						defending = crossing(hitLocal, reflected * (1 / length2), reach - travelled)
					end
				end
			end
		end
	end
	return defending
end

-- Boost estimate for one player.
local function boostTick(player, entry, dt, now, ctx, pads)
	if ctx.running and player.thrust then
		entry.boost = math.max(0, entry.boost - (BOOST_DRAIN_PER_SECOND * dt))
	end
	if pads == nil then return end
	local arena = ctx.entry
	local limbs = { arena.inverse:rotateVector(player.head - arena.position),
		if player.left ~= nil then arena.inverse:rotateVector(player.left - arena.position) else nil,
		if player.right ~= nil then arena.inverse:rotateVector(player.right - arena.position) else nil }
	local previous = entry.limbs or {}
	entry.limbs = limbs
	-- nearest pad to the head; only worth a closer look within 1.5 m
	local head = limbs[1]
	local nearest, nearestGap = nil, 150
	for index, pad in ipairs(pads) do
		local dx, dy, dz = head.x - pad[1], head.y - pad[2], head.z - pad[3]
		local gap = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
		if gap < nearestGap then nearest, nearestGap = index, gap end
	end
	if nearest == nil then
		entry.onPad = false
		return
	end
	local pad = pads[nearest]
	local size = PAD[pad[4]]
	local touching = false
	for index = 1, 3 do
		local limb = limbs[index]
		if limb ~= nil then
			local was = previous[index] or limb
			if (limb - was):length() > MAX_FRAME_MOVE then was = limb end
			if segmentHitsBox(was, limb, pad, size) then touching = true end
		end
	end
	if touching and not entry.onPad and entry.boost < 100 and now >= (Stats.padReady[nearest] or 0) then
		entry.boost = math.min(100, entry.boost + size.gain)
		Stats.padReady[nearest] = now + size.cooldown
	end
	entry.onPad = touching
end

-- Call once per frame.
--   ctx.entry     the arena (ArenaMap entry: position, rotation, inverse, goalY)
--   ctx.ballPos / ctx.ballVel   the arena ball, or nil when there is none
--   ctx.field     the players on the two rosters: { name, team (0 / 1), root, head, left, right, thrust }
--   ctx.running   the round is running;  ctx.grace  a goal was just scored (ball dead)
--   ctx.castRay   function(from, to) -> { successful, position, normal }, optional (bank shots)
function Stats.tick(dt, now, ctx)
	local arena = ctx.entry
	local pads = if arena ~= nil then PADS[arena.goalY] else nil
	for _, player in ipairs(ctx.field) do
		local entry = record(player.name)
		local okBoost = pcall(boostTick, player, entry, dt, now, ctx, pads)
		if not okBoost then entry.limbs = nil end
		if not finite(entry.boost) then entry.boost = 0 end
	end

	-- a save is only counted once no goal has followed it
	local pending = Stats.pendingSave
	if pending ~= nil and now - pending.time >= SAVE_CONFIRM_SECONDS then
		record(pending.name).stats.saves += 1
		Stats.pendingSave = nil
	end

	local ballPos = ctx.ballPos
	local live = ctx.running and not ctx.grace
	if ballPos == nil or ctx.grace then
		-- no ball in play: nothing is touched, and the clock for possession does not run
		Stats.previousBall, Stats.live = nil, nil
		if ballPos == nil and live then Stats.seconds.loose += dt end
		return
	end

	-- 1. Who is on the ball: nearest head / hand to the path the ball took this frame.
	local from = Stats.previousBall or ballPos
	if (ballPos - from):length() > 1500 then from = ballPos end -- the ball was put back in the middle
	Stats.previousBall = ballPos
	local nearest, nearestGap = nil, CONTACT
	local keeper, keeperGap = nil, CONTACT
	local defending = if Stats.live ~= nil and now - Stats.live.time <= SAVE_LIVE_SECONDS then Stats.live.defending else nil
	for _, player in ipairs(ctx.field) do
		local gap = segmentGap(player.head, from, ballPos)
		if player.left ~= nil then gap = math.min(gap, segmentGap(player.left, from, ballPos)) end
		if player.right ~= nil then gap = math.min(gap, segmentGap(player.right, from, ballPos)) end
		if finite(gap) and gap < CONTACT then
			Stats.touched[player.name] = now
			if gap < nearestGap then nearest, nearestGap = player, gap end
			if player.team == defending and gap < keeperGap then keeper, keeperGap = player, gap end
		end
	end
	if nearest ~= nil then contact(nearest, now, ballPos, ctx.running) end

	-- 2. Has the ball been released, and how fast has it gone since?
	local holder = Stats.holder
	local speed = if ctx.ballVel ~= nil then ctx.ballVel:length() else 0
	if not finite(speed) then speed = 0 end
	if holder ~= nil then
		if (ballPos - holder.place):length() >= SHOT_SEPARATION then Stats.separated = true end
		if Stats.separated and speed > Stats.peak then Stats.peak = speed end
	end

	-- 3. Possession time and dribbling.
	if live then
		local seconds = Stats.seconds
		if holder ~= nil and now - holder.time <= POSSESSION_TIMEOUT then
			local entry = record(holder.name)
			entry.seconds += dt
			if holder.team == 0 then seconds.home += dt else seconds.away += dt end
			for _, player in ipairs(ctx.field) do
				if player.name == holder.name then
					if Stats.dribbleName == holder.name and Stats.dribbleFrom ~= nil then
						local moved = (player.root - Stats.dribbleFrom):length()
						if finite(moved) and moved < MAX_FRAME_MOVE then entry.stats.dribbleMeters += moved / 100 end
					end
					Stats.dribbleName, Stats.dribbleFrom = holder.name, player.root
				end
			end
		else
			seconds.loose += dt
			Stats.dribbleName, Stats.dribbleFrom = nil, nil
		end
		local total = seconds.home + seconds.away + seconds.loose
		if total > 0 then
			for _, entry in pairs(Stats.players) do
				entry.stats.possession = math.clamp(entry.seconds / total * 100, 0, 100)
			end
		end
	end

	-- 4. Shots and saves (arenas whose goal mouth is known).
	local goal = if arena ~= nil and arena.goalY ~= nil then GOALS[arena.goalY] else nil
	if goal == nil or not live then
		Stats.live = nil
		return
	end
	local ballLocal = arena.inverse:rotateVector(ballPos - arena.position)
	local target = nil
	if ctx.ballVel ~= nil then
		local okTarget, result = pcall(onTarget, ctx, goal, ballLocal, arena.inverse:rotateVector(ctx.ballVel))
		if okTarget then target = result end
	end
	if target ~= nil then
		Stats.live = { defending = target, time = now }
		if holder ~= nil and holder.team ~= target and Stats.separated and Stats.shotArmed then
			record(holder.name).stats.shots += 1
			Stats.shotArmed = false
		end
	end
	if keeper ~= nil and Stats.pendingSave == nil and (Stats.lastSaveAt == nil or now - Stats.lastSaveAt > 1) then
		local sign = if defending == 0 then 1 else -1
		local dx, dy, dz = ballLocal.x, ballLocal.y - (sign * arena.goalY), ballLocal.z - goal.z
		local inFront = ballLocal.y * sign < arena.goalY -- still on the pitch side of the goal line
		if inFront and math.sqrt((dx * dx) + (dy * dy) + (dz * dz)) <= SAVE_RANGE then
			Stats.pendingSave = { name = keeper.name, team = defending, time = now }
			Stats.lastSaveAt = now
		end
	end
end

-- `team` (0 home / 1 away) just scored. Credits the goal and the assist, and returns the
-- lastShotInfo table: { shooter, assister, team, shotSpeed (m/s), shotDistanceMeters }.
function Stats.goal(team, now, arena)
	local info = { shooter = "", assister = "", team = team, shotSpeed = 0, shotDistanceMeters = 0 }
	local scorer = Stats.last[team].current
	if scorer ~= nil and now - scorer.time <= SCORER_MAX_AGE then
		info.shooter = scorer.name
		local entry = record(scorer.name)
		entry.stats.goals += 1
		-- a goal is a shot: count one if this touch had not been counted as a shot already
		if Stats.holder ~= nil and Stats.holder.name == scorer.name and Stats.shotArmed then entry.stats.shots += 1 end
		if scorer.from ~= nil and scorer.from ~= scorer.name and now - scorer.first < ASSIST_SECONDS then
			info.assister = scorer.from
			record(scorer.from).stats.assists += 1
		end
		local goal = if arena ~= nil and arena.goalY ~= nil then GOALS[arena.goalY] else nil
		if goal ~= nil then
			pcall(function()
				-- home (0) scores in the away goal, at -Y in the arena frame
				local centre = arena.position + arena.rotation:rotateVector(Vec3.new(0, (if team == 0 then -1 else 1) * arena.goalY, goal.z))
				local metres = (centre - scorer.place):length() / 100
				if finite(metres) then info.shotDistanceMeters = math.floor((metres * 100) + 0.5) / 100 end
			end)
		end
	end
	if finite(Stats.peak) and Stats.peak > 0 then
		info.shotSpeed = math.floor(math.min(Stats.peak / 100, 300) * 10 + 0.5) / 10
	end
	-- a save that was about to be credited to the team that just conceded did not hold
	if Stats.pendingSave ~= nil and Stats.pendingSave.team ~= team then Stats.pendingSave = nil end
	Stats.clearContacts()
	Stats.refill()
	return info
end

Stats.reset()
return Stats
