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
-- None of his code is copied here. Taken from Caster Camera: the shape of the "api" table and the
-- game calls used to fill it. The code itself is written for Streamer Cam.
--
-- Streamer Cam "Send Overlay Info": publishes match data for OD Caster Bridge, the same way
-- Dennssen's Caster Camera does. Optional and OFF by default; main.luau only calls tick() while
-- the "Send Overlay Info" checkbox is on.
--
-- HOW THE DATA GETS OUT: one table is stored at config.api and saveConfig() is called. The bridge
-- polls http://localhost:5420/cameras/duckyinvr.streamercam.public/config and reads the "api" key.
-- Nothing else is sent anywhere.
--
-- The bridge parses that table strictly: one missing or wrongly typed field and it silently throws
-- the whole update away. So every field always exists, numbers are always finite, the "integer"
-- fields are always whole, and nothing is ever set to nil. check() below enforces that before
-- every save.
--
-- Data shape and the game calls used (Transform.new, getNumberConfigVariable, the gamemode data
-- fields) follow Caster Camera's overlay.luau / arena.luau / gamemodes.luau (MIT licence,
-- (c) dennssen, https://github.com/dennssen/CasterCamera). The code here is written for Streamer Cam.
--
-- NO ARENA: the same table with gamemodeId "" and every other field empty or zero. It is sent while
-- no arena is selected, while the camera is outside every arena (outsideEveryArena below), and for
-- a finished match whose arena has emptied (updateHidden below).
--
-- READ FROM THE GAME: arena, rosters (head transform + velocity), the ball, finished rounds, grace
-- period after a goal, overtime, best-of and match length, the followed player.
-- WORKED OUT from player and ball movement (matchstats.luau; estimates, like Caster's): possession,
-- dribble distance, passes, possessions won / lost, shots, saves, goals, assists, lastShotInfo and
-- a boost estimate.
local Stats = require("matchstats")

local Overlay = { status = "Off", slot = nil, time = 0, sends = 0, lastSave = -math.huge, lastGoal = "none", cameraNote = "not checked yet" }
Overlay.matchStats = Stats -- (for the menu and for tests)

local SAVES_PER_SECOND = 20   -- config saves (disk writes) while the feature is on
local GRACE_SECONDS = 6       -- isGracePeriod stays true at least this long after a goal
local GRACE_MAX_SECONDS = 20  -- ...and never longer than this
local SWITCH_SECONDS = 1      -- the camera must be inside a different arena this long before it is selected
local MISSING_SECONDS = 3     -- the selected arena must be gone from the list this long before it is dropped
local NO_LIST_SECONDS = 15    -- ...or this long when the whole arena list is empty / unreadable
local ROSTER_MARGIN = 300     -- a player this far outside the arena box (in a goal pocket) still counts
local HIDE_DECIDED_SECONDS = 3  -- match decided: blank the data this long after the arena empties / the camera leaves it
local HIDE_UNSURE_SECONDS = 30  -- the same, when it cannot be told that the match is decided (a series may still be going)
local OUTSIDE_SECONDS = 2     -- camera outside every arena this long: "no arena" is sent (a setting; this is the fallback)
local OUTSIDE_MARGIN = 2500   -- ...and "outside" starts this far from an arena's box (a setting; this is the fallback)

local api = nil        -- built on first use: no engine calls while the module loads
local blank = nil      -- the empty "no arena" table: every field there, all empty or zero
local held = nil       -- saved beside it while it is out: the selected arena and its finished rounds
local prev = nil       -- previous reading of the arena's clock and score
local restored = nil   -- finished rounds carried over a script reload: { slot, rounds }

local function finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- A whole number from 0 to `limit` (anything unusable becomes 0).
local function whole(n, limit)
	if not finite(n) then return 0 end
	return math.clamp(math.floor(n + 0.5), 0, limit or 1000000)
end

-- `v` if it is a vector with three finite components, else nil.
local function goodVec(v)
	if v == nil then return nil end
	local ok, fine = pcall(function() return finite(v.x) and finite(v.y) and finite(v.z) end)
	return if ok and fine then v else nil
end

local function noShot()
	return { shooter = "", assister = "", team = -1, shotSpeed = 0, shotDistanceMeters = 0 }
end

local function newApi()
	return {
		gamemodeId = "",
		home = { players = {}, possession = 0 },
		away = { players = {}, possession = 0 },
		arenaSize = Vec3.zeroVector,
		ball = { transform = Transform.identity, velocity = Vec3.zeroVector },
		rounds = {},
		followedPlayer = "",
		lastShotInfo = noShot(),
		isGracePeriod = false,
		isOvertime = false,
		bestOf = 0,
		matchLengthSeconds = 0,
	}
end

-- A Transform from a position and rotation (a missing or broken rotation becomes "no rotation").
-- Returns nil when the position is unusable.
local function makeTransform(position, rotation)
	if goodVec(position) == nil then return nil end
	local ok, transform = pcall(function()
		local q = rotation
		if q == nil or goodVec(q:rotateVector(Vec3.forwardVector)) == nil then q = Quat.identity end
		return Transform.new(position, q, Vec3.oneVector)
	end)
	return if ok then transform else nil
end

-- Is `point` inside this arena's box (or within `margin` of it)?
local function inside(entry, point, margin)
	if entry == nil or point == nil then return false end
	local ok, result = pcall(function()
		local p = entry.inverse:rotateVector(point - entry.position)
		return math.abs(p.x) <= entry.hx + margin and math.abs(p.y) <= entry.hy + margin
			and math.abs(p.z - entry.lift) <= entry.hz + margin
	end)
	return ok and result == true
end

-- ---------------------------------------------------------------------------------------------
-- Validation: nil when `value` is exactly the table the bridge expects, else what is wrong.
-- ---------------------------------------------------------------------------------------------
local function isWhole(n) return finite(n) and n % 1 == 0 end
local STAT_WHOLE = { "goals", "saves", "assists", "shots", "passes", "possessionsWon", "possessionsLost" }

local function checkTeam(team, label)
	if type(team) ~= "table" then return label .. " is missing" end
	if not finite(team.possession) or team.possession < 0 or team.possession > 100 then return label .. ".possession" end
	if type(team.players) ~= "table" then return label .. ".players" end
	for name, player in pairs(team.players) do
		local where = label .. ".players[" .. tostring(name) .. "]"
		if type(name) ~= "string" or type(player) ~= "table" then return where end
		if type(player.stats) ~= "table" then return where .. ".stats" end
		for _, key in ipairs(STAT_WHOLE) do
			if not isWhole(player.stats[key]) then return where .. ".stats." .. key end
		end
		if not finite(player.stats.possession) then return where .. ".stats.possession" end
		if not finite(player.stats.dribbleMeters) then return where .. ".stats.dribbleMeters" end
		if goodVec(player.velocity) == nil then return where .. ".velocity" end
		if player.transform == nil or goodVec(player.transform.position) == nil then return where .. ".transform" end
		if not finite(player.boost) or player.boost < 0 or player.boost > 100 then return where .. ".boost" end
	end
	return nil
end

function Overlay.check(value)
	if type(value) ~= "table" then return "api is missing" end
	if type(value.gamemodeId) ~= "string" then return "gamemodeId" end
	local bad = checkTeam(value.home, "home") or checkTeam(value.away, "away")
	if bad ~= nil then return bad end
	if goodVec(value.arenaSize) == nil then return "arenaSize" end
	if type(value.ball) ~= "table" or value.ball.transform == nil or goodVec(value.ball.transform.position) == nil then return "ball.transform" end
	if goodVec(value.ball.velocity) == nil then return "ball.velocity" end
	if type(value.rounds) ~= "table" then return "rounds" end
	local count = 0
	for _ in pairs(value.rounds) do count += 1 end
	if count ~= #value.rounds then return "rounds is not a plain list" end
	for i, round in ipairs(value.rounds) do
		if type(round) ~= "table" or not isWhole(round.home) or not isWhole(round.away) then return "rounds[" .. i .. "]" end
	end
	if type(value.followedPlayer) ~= "string" then return "followedPlayer" end
	local shot = value.lastShotInfo
	if type(shot) ~= "table" then return "lastShotInfo" end
	if type(shot.shooter) ~= "string" or type(shot.assister) ~= "string" then return "lastShotInfo.shooter / assister" end
	if not isWhole(shot.team) or shot.team < -1 or shot.team > 1 then return "lastShotInfo.team" end
	if not finite(shot.shotSpeed) or not finite(shot.shotDistanceMeters) then return "lastShotInfo.shotSpeed / shotDistanceMeters" end
	if type(value.isGracePeriod) ~= "boolean" then return "isGracePeriod" end
	if type(value.isOvertime) ~= "boolean" then return "isOvertime" end
	if not isWhole(value.bestOf) then return "bestOf" end
	if not isWhole(value.matchLengthSeconds) then return "matchLengthSeconds" end
	return nil
end

-- ---------------------------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------------------------

-- Called when the feature is switched off: the next time it is switched on it starts clean.
function Overlay.reset()
	api, prev, restored, blank, held = nil, nil, nil, nil, nil
	Overlay.hidden, Overlay.hiddenWhy, Overlay.goneTime, Overlay.readOk = false, nil, 0, false
	Overlay.outsideTime, Overlay.outsideGap, Overlay.outsideMargin, Overlay.cameraNote = nil, nil, nil, "not checked yet"
	Overlay.homeRounds, Overlay.awayRounds, Overlay.roundsPerMatch, Overlay.useBestOf = nil, nil, nil, nil
	Stats.reset()
	Overlay.slot, Overlay.challenger, Overlay.challengeTime, Overlay.missingTime = nil, nil, 0, 0
	Overlay.gamemode, Overlay.settingsAt, Overlay.statusAt, Overlay.statusWhy = nil, nil, nil, nil
	Overlay.lastSave, Overlay.status, Overlay.lastGoal = -math.huge, "Off", "none"
end

-- At script load with the feature on: keep the finished rounds of the arena that was selected, so
-- reloading the script in the middle of a series does not wipe the series.
-- `kept` is the copy saved beside the data while the empty table was out (config.apiHeld).
function Overlay.restore(saved, kept)
	restored = nil
	if type(saved) == "table" and saved.gamemodeId == "" and type(kept) == "table" then saved = kept end
	if type(saved) ~= "table" or type(saved.gamemodeId) ~= "string" or saved.gamemodeId == "" or type(saved.rounds) ~= "table" then return end
	local rounds = {}
	for _, round in ipairs(saved.rounds) do
		if type(round) ~= "table" or not finite(round.home) or not finite(round.away) then return end
		table.insert(rounds, { home = whole(round.home, 999), away = whole(round.away, 999) })
	end
	restored = { slot = saved.gamemodeId, rounds = rounds }
end

-- The table being sent (nil until the first tick). For the menu and for tests.
function Overlay.current()
	return api
end

local function clearMatch()
	api.rounds = {}
	api.lastShotInfo = noShot()
	api.home.possession, api.away.possession = 0, 0
	Stats.reset()
	for _, team in ipairs({ api.home, api.away }) do
		for name, player in pairs(team.players) do
			player.stats, player.boost = Stats.statsFor(name), Stats.boostFor(name)
		end
	end
end

local function selectArena(slot, entry)
	Overlay.slot = slot
	Overlay.challenger, Overlay.challengeTime, Overlay.missingTime = nil, 0, 0
	Overlay.gamemode, Overlay.settingsAt = nil, nil
	api.gamemodeId = slot or ""
	api.arenaSize = Vec3.zeroVector
	if entry ~= nil and entry.known then
		local okSize, size = pcall(function() return Vec3.new(entry.hx * 2, entry.hy * 2, entry.hz * 2) end)
		if okSize and goodVec(size) ~= nil then api.arenaSize = size end
	end
	api.home.players, api.away.players = {}, {}
	api.rounds, prev = {}, nil
	api.lastShotInfo = noShot()
	api.home.possession, api.away.possession = 0, 0
	Stats.reset()
	api.isGracePeriod, api.isOvertime = false, false
	api.bestOf, api.matchLengthSeconds = 0, 0
	Overlay.rise, Overlay.graceStart = 0, nil
	Overlay.goneTime, Overlay.readOk = 0, false
	Overlay.homeRounds, Overlay.awayRounds, Overlay.roundsPerMatch, Overlay.useBestOf = nil, nil, nil, nil
	if restored ~= nil then
		if slot ~= nil and restored.slot == slot then api.rounds = restored.rounds end
		restored = nil
	end
end

-- Which arena the data is about. The arena the camera (or the ball it follows) is inside; once one
-- is selected it STAYS selected while the camera is outside every arena (players are thrown out
-- between rounds and the camera follows them: that must not wipe the series), and it only changes
-- after the camera has been inside a different arena for a second. With nothing selected yet, the
-- closest arena is used.
local function pickArena(map, anchor, dt)
	if map == nil or type(map.entries) ~= "table" then return Overlay.slot end
	local here = nil
	if anchor ~= nil and map.available then
		local okSlot, found = pcall(map.locate, anchor)
		if okSlot and found ~= nil and inside(map.entries[found], anchor, 600) then here = found end
	end
	if Overlay.slot ~= nil then
		if map.entries[Overlay.slot] == nil then
			-- gone from the arena list: a failed read looks the same, so wait before believing it
			Overlay.missingTime = (Overlay.missingTime or 0) + dt
			if Overlay.missingTime < (if map.available then MISSING_SECONDS else NO_LIST_SECONDS) then return Overlay.slot end
		else
			Overlay.missingTime = 0
			if here == nil or here == Overlay.slot then
				Overlay.challenger, Overlay.challengeTime = nil, 0
				return Overlay.slot
			end
			if Overlay.challenger ~= here then Overlay.challenger, Overlay.challengeTime = here, 0 end
			Overlay.challengeTime += dt
			if Overlay.challengeTime < SWITCH_SECONDS then return Overlay.slot end
			return here
		end
	end
	if here ~= nil then return here end
	if not map.available then return nil end
	-- just loaded, with rounds carried over a script reload: back to the arena they belong to
	if Overlay.slot == nil and restored ~= nil and map.entries[restored.slot] ~= nil then return restored.slot end
	-- not inside any arena: the closest one (recognised layouts first, then by slot name so the
	-- answer never depends on table order)
	local best, bestGap, bestKnown = nil, math.huge, false
	if anchor ~= nil then
		for slot, entry in pairs(map.entries) do
			local okGap, gap = pcall(function() return (anchor - entry.position):length() end)
			if okGap and finite(gap) then
				local known = entry.known == true
				local better = (known and not bestKnown) or (known == bestKnown and (gap < bestGap - 0.5
					or (math.abs(gap - bestGap) <= 0.5 and (best == nil or slot < best))))
				if better then best, bestGap, bestKnown = slot, gap, known end
			end
		end
	end
	return best
end

-- Goals, round ends, new matches and overtime, from the arena's own clock and score.
local function readClock(slot, now, entry)
	local okData, data = pcall(function() return SpectatorGamemodes.getGamemodeData(slot) end)
	local reading = nil
	-- Only checked for being there, not for being a plain Lua table (see kickoff.luau).
	if okData and data ~= nil then
		pcall(function()
			local a, b = data.teams[1], data.teams[2]
			if not finite(a.score) or not finite(b.score) then return end
			reading = { running = data.isGameRunning == true, home = whole(a.score, 999), away = whole(b.score, 999),
				homeRounds = whole(a.roundsWon, 999), awayRounds = whole(b.roundsWon, 999),
				time = if finite(data.timeSeconds) then data.timeSeconds else nil,
				secondary = if finite(data.secondaryTimeSeconds) then data.secondaryTimeSeconds else nil }
		end)
	end
	if reading == nil then
		prev = nil -- nothing is concluded across a gap in the data
		Overlay.clock, Overlay.running, Overlay.readOk = "score unavailable", false, false
		return
	end
	Overlay.readOk, Overlay.homeRounds, Overlay.awayRounds = true, reading.homeRounds, reading.awayRounds
	if prev ~= nil then
		local starting = reading.running and not prev.running
		if starting then
			api.isOvertime, Overlay.rise = false, 0
			-- a round that starts with nobody having won a round yet is a new match
			if reading.homeRounds == 0 and reading.awayRounds == 0 then clearMatch() end
			Stats.clearContacts()
			Stats.refill()
		elseif reading.home > prev.home or reading.away > prev.away then
			api.isGracePeriod, Overlay.graceStart = true, now
			local team = if reading.home > prev.home then 0 else 1
			local shot = Stats.goal(team, now, entry)
			api.lastShotInfo = shot
			local side = if team == 0 then "home" else "away"
			Overlay.lastGoal = if shot.shooter == "" then side .. " team, scorer unknown"
				else string.format("%s (%s)%s, %.1f m/s from %.1f m", shot.shooter, side,
					if shot.assister ~= "" then ", assist " .. shot.assister else "", shot.shotSpeed, shot.shotDistanceMeters)
		end
		if prev.running and not reading.running then
			local home, away = reading.home, reading.away
			-- (if the score was wiped in the same moment the round ended, use the last score seen)
			if home == 0 and away == 0 and (prev.home ~= 0 or prev.away ~= 0) then home, away = prev.home, prev.away end
			if home ~= away then
				table.insert(api.rounds, { home = home, away = away })
				while #api.rounds > 50 do table.remove(api.rounds, 1) end
			end
		end
		-- overtime: the clock counting UP during a round (a single big jump is a clock reset, not overtime)
		if reading.running and prev.running and not starting and reading.time ~= nil and prev.time ~= nil then
			local delta = reading.time - prev.time
			if delta > 0.0005 and delta < 2 then
				Overlay.rise = (Overlay.rise or 0) + delta
			elseif delta < -0.0005 or delta >= 2 then
				Overlay.rise = 0
			end
			if (Overlay.rise or 0) >= 0.25 and not api.isOvertime then
				api.isOvertime = true
				Stats.refill() -- everyone's boost is topped up when overtime starts
			end
		end
	end
	if api.isGracePeriod then
		local elapsed = now - (Overlay.graceStart or now)
		if not reading.running or elapsed > GRACE_MAX_SECONDS
			or (elapsed > GRACE_SECONDS and (reading.secondary == nil or reading.secondary <= 0)) then
			api.isGracePeriod = false
		end
	end
	Overlay.clock = string.format("%d - %d%s", reading.home, reading.away, if reading.running then "" else " (not running)")
	Overlay.running = reading.running
	prev = reading
end

-- Best-of and match length from the arena's own settings (read about once a second).
local function readSettings(slot, now)
	if Overlay.settingsAt ~= nil and now - Overlay.settingsAt < 1 then return end
	Overlay.settingsAt = now
	if Overlay.gamemode == nil then
		pcall(function()
			for _, gamemode in pairs(SpectatorGamemodes.listGamemodes()) do
				if gamemode:getSlotId() == slot then Overlay.gamemode = gamemode end
			end
		end)
	end
	local gamemode = Overlay.gamemode
	if gamemode == nil then return end
	local okRead = pcall(function()
		local length = whole(gamemode:getNumberConfigVariable("matchlengthseconds"), 86400)
		local bestOf = 0
		local useBestOf = gamemode:getBoolConfigVariable("busebestof") == true
		local rounds = whole(gamemode:getNumberConfigVariable("roundspermatch"), 99)
		if useBestOf then bestOf = rounds end
		api.matchLengthSeconds, api.bestOf = length, bestOf
		Overlay.roundsPerMatch, Overlay.useBestOf = rounds, useBestOf -- (for matchDecided below)
	end)
	if not okRead then Overlay.gamemode = nil end -- look the arena up again next time
end

-- The arena's ball and both rosters, then the match stats worked out from them.
local function readField(entry, now, input, dt)
	-- ball: the one the camera follows if it is in this arena, else the arena ball nearest the middle
	local ball = nil
	local followed = input.ball
	if followed ~= nil and followed.transform ~= nil and inside(entry, followed.transform.position, 600) then
		ball = followed
	else
		local nearest = math.huge
		for _, candidate in ipairs(input.balls or {}) do
			local okBall, gap = pcall(function()
				if candidate.transform == nil or not inside(entry, candidate.transform.position, 600) then return nil end
				if input.isArenaBall ~= nil and not input.isArenaBall(candidate) then return nil end
				return (candidate.transform.position - entry.position):length()
			end)
			if okBall and finite(gap) and gap < nearest then ball, nearest = candidate, gap end
		end
	end
	local ballPos, ballVel = nil, nil
	if ball ~= nil then
		local transform = makeTransform(ball.transform.position, ball.transform.rotation)
		if transform ~= nil then
			ballPos, ballVel = ball.transform.position, goodVec(ball.velocity) or Vec3.zeroVector
			api.ball = { transform = transform, velocity = ballVel }
		end
	end

	local seen = { [0] = {}, [1] = {} }
	local field = {}
	for _, player in ipairs(input.players or {}) do
		pcall(function()
			local index = player.teamIndex
			if index ~= 0 and index ~= 1 then return end
			local root = if player.root ~= nil then goodVec(player.root.position) else nil
			if root == nil or not inside(entry, root, ROSTER_MARGIN) then return end
			local name = player.playerName
			if type(name) ~= "string" or name == "" then return end
			local team = if index == 0 then api.home else api.away
			local record = team.players[name]
			if record == nil then
				record = { stats = Stats.statsFor(name), velocity = Vec3.zeroVector, transform = Transform.identity, boost = 0 }
				team.players[name] = record
			end
			local head = player.head
			local headPos = (if head ~= nil then goodVec(head.position) else nil) or root
			local transform = makeTransform(headPos, if head ~= nil then head.rotation else nil)
			if transform ~= nil then record.transform = transform end
			record.velocity = goodVec(player.velocity) or Vec3.zeroVector
			seen[index][name] = true
			-- head and hands in world space, for the match stats
			local hands = {}
			for _, key in ipairs({ "leftHand", "rightHand" }) do
				local hand = player[key]
				if hand ~= nil and goodVec(hand.position) ~= nil and player.root.rotation ~= nil then
					-- hand positions are relative to the player's root (as in Caster's util.luau)
					hands[key] = goodVec(root + player.root.rotation:rotateVector(hand.position))
				end
			end
			table.insert(field, { name = name, team = index, root = root, head = headPos, left = hands.leftHand, right = hands.rightHand,
				thrust = player.leftThrusterActive == true or player.rightThrusterActive == true })
		end)
	end
	for index, team in pairs({ [0] = api.home, [1] = api.away }) do
		for name in pairs(team.players) do
			if not seen[index][name] then team.players[name] = nil end
		end
	end
	-- Match stats (own guard: a fault here leaves the numbers as they were, the table still goes out).
	local okStats, statsError = pcall(Stats.tick, dt, now, { entry = entry, ballPos = ballPos, ballVel = ballVel, field = field,
		running = Overlay.running == true, grace = api.isGracePeriod, castRay = input.castRay })
	Overlay.statsError = if okStats then nil else tostring(statsError)
	local homeShare, awayShare = Stats.teamPossession()
	api.home.possession = if finite(homeShare) then homeShare else 0
	api.away.possession = if finite(awayShare) then awayShare else 0
	for _, team in ipairs({ api.home, api.away }) do
		for name, record in pairs(team.players) do
			record.stats = Stats.statsFor(name)
			local boost = Stats.boostFor(name)
			record.boost = if finite(boost) then boost else 0
		end
	end
end

-- Has the match in the selected arena been decided? Only "yes" when the arena's own settings and
-- rounds-won counts say so: a single game (one round per match), a best-of series somebody has
-- won more than half of, or a fixed number of rounds that have all been played.
local function matchDecided()
	local total = Overlay.roundsPerMatch
	if not finite(total) then return false end
	if total <= 1 then return true end
	local home, away = Overlay.homeRounds or 0, Overlay.awayRounds or 0
	if Overlay.useBestOf then return math.max(home, away) * 2 > total end
	return home + away >= total
end

-- Distance from `point` to the nearest arena's box (0 inside one). nil when there is no arena that
-- can be measured.
local function nearestArenaGap(map, point)
	local best = nil
	for _, entry in pairs(map.entries) do
		local ok, gap = pcall(function()
			local p = entry.inverse:rotateVector(point - entry.position)
			local dx = math.max(math.abs(p.x) - entry.hx, 0)
			local dy = math.max(math.abs(p.y) - entry.hy, 0)
			local dz = math.max(math.abs(p.z - entry.lift) - entry.hz, 0)
			return math.sqrt(dx * dx + dy * dy + dz * dz)
		end)
		if ok and finite(gap) and (best == nil or gap < best) then best = gap end
	end
	return best
end

-- OUTSIDE EVERY ARENA (the hub, a lobby): the empty "no arena" table is sent instead of the selected
-- arena's data. The camera itself has to be further than `margin` from every arena's box for `delay`
-- seconds in a row, so an overview or a sideline spot just outside a box still counts as inside.
-- It never applies while the camera is casting an arena (input.casting: a ball cam on one, or a
-- player cam on somebody who is in one), wherever the camera itself is.
-- Nothing is thrown away: the arena stays selected and is still read, so back inside its data is
-- sent again on that same frame, finished rounds included. Returns whether to send the empty table.
local function outsideEveryArena(map, input, dt)
	Overlay.outsideGap = nil
	if input.clearOutside ~= true then
		Overlay.outsideTime = 0
		return false
	end
	local delay = if finite(input.outsideSeconds) then math.clamp(input.outsideSeconds, 0, 60) else OUTSIDE_SECONDS
	local margin = if finite(input.outsideMargin) then math.clamp(input.outsideMargin, 0, 20000) else OUTSIDE_MARGIN
	Overlay.outsideMargin = margin
	local point = goodVec(input.cameraPos)
	if point ~= nil and map ~= nil and map.available and type(map.entries) == "table" then
		Overlay.outsideGap = nearestArenaGap(map, point)
	end
	if input.casting == true then
		Overlay.outsideTime = 0
		return false
	end
	local gap = Overlay.outsideGap
	-- no arena list or no camera position this frame: nothing can be concluded, so nothing changes
	if gap == nil then return (Overlay.outsideTime or 0) >= delay end
	if gap <= margin then
		Overlay.outsideTime = 0
		return false
	end
	Overlay.outsideTime = (Overlay.outsideTime or 0) + dt
	return Overlay.outsideTime >= delay
end

-- A finished match is HIDDEN (an empty "no match" table is sent instead of its data) once the game
-- there is not running AND the arena has emptied (nobody on a team left in it) or the camera has
-- left it, for 3 seconds when the match is known to be decided and 30 seconds otherwise.
-- Nothing is thrown away: the arena stays selected and is still read, so the moment a round runs
-- again, or the camera is back in the arena with players in it, the data is sent again (a series
-- keeps its finished rounds across a long break).
local function updateHidden(entry, anchor, dt, wanted)
	local gone = false
	if wanted and entry ~= nil and Overlay.readOk == true and Overlay.running ~= true then
		local emptied = next(api.home.players) == nil and next(api.away.players) == nil
		local cameraOut = anchor == nil or not inside(entry, anchor, 600)
		gone = emptied or cameraOut
	end
	Overlay.goneTime = if gone then (Overlay.goneTime or 0) + dt else 0
	return gone and Overlay.goneTime >= (if matchDecided() then HIDE_DECIDED_SECONDS else HIDE_UNSURE_SECONDS)
end

-- Call once per frame while the feature is on.
--   input.map          ArenaMap (entries + locate)
--   input.anchor       position of the ball the camera follows, or of the camera
--   input.ball         the ball the camera follows, or nil
--   input.balls        every ball; input.isArenaBall(ball) tells match balls from toys
--   input.players      every player
--   input.followed     name of the player the camera is following, or ""
--   input.castRay      function(from, to) -> ray hit, optional (lets shots off one bounce count)
--   input.clearAfterMatch  true: stop sending a finished match once its arena has emptied (see updateHidden)
--   input.clearOutside     true: send "no arena" while the camera is outside every arena (see outsideEveryArena)
--   input.cameraPos        where the camera itself is (input.anchor may be the ball instead)
--   input.casting          true while a ball cam or a player cam is casting an arena
--   input.outsideSeconds, input.outsideMargin   the delay and the margin of that rule
function Overlay.tick(dt, input)
	if api == nil then
		api = newApi()
		Overlay.slot, Overlay.challenger, Overlay.challengeTime, Overlay.missingTime = nil, nil, 0, 0
		Overlay.outsideTime = math.huge -- switched on outside every arena: "no arena" from the first send
	end
	Overlay.time += dt
	local now = Overlay.time
	local map = input.map

	local slot = pickArena(map, input.anchor, dt)
	local entry = if slot ~= nil and map ~= nil and type(map.entries) == "table" then map.entries[slot] else nil
	if slot ~= Overlay.slot then selectArena(slot, entry) end

	if slot ~= nil then
		readClock(slot, now, entry)
		readSettings(slot, now)
		if entry ~= nil then readField(entry, now, input, dt) end
	else
		prev = nil
		Overlay.goneTime = 0
	end
	local wasOutside = Overlay.hiddenWhy == "outside"
	local outside = outsideEveryArena(map, input, dt)
	-- Back inside, but in a DIFFERENT arena than the one selected: stay empty for the second it takes
	-- the selection to move over, rather than showing the old arena's data in the new one.
	if not outside and wasOutside and input.clearOutside == true and input.casting ~= true and Overlay.challenger ~= nil then outside = true end
	local finished = slot ~= nil and updateHidden(entry, input.anchor, dt, input.clearAfterMatch == true)
	Overlay.hiddenWhy = if outside then "outside" elseif finished then "finished" else nil
	Overlay.hidden = Overlay.hiddenWhy ~= nil
	api.followedPlayer = if type(input.followed) == "string" then input.followed else ""
	local sending = api
	if Overlay.hidden then
		-- every field the bridge needs, all empty or zero: gamemodeId "" is what says "no arena"
		if blank == nil then blank = newApi() end
		sending = blank
	end

	-- Save about 20 times a second (the bridge reads the saved config).
	if now - Overlay.lastSave >= (1 / SAVES_PER_SECOND) - 0.0001 then
		local bad = Overlay.check(sending)
		if bad ~= nil then
			-- should never happen; sending it would only make the bridge drop the update without a word
			Overlay.status = "NOT SENT: bad field " .. bad
			return
		end
		Overlay.lastSave = now
		config.api = sending
		-- while the empty table is out, the arena and its finished rounds are kept beside it, so a
		-- script reload in the middle of a series still finds them (Overlay.restore)
		if sending ~= api and slot ~= nil then
			if held == nil then held = {} end
			held.gamemodeId, held.rounds = api.gamemodeId, api.rounds
			config.apiHeld = held
		else
			config.apiHeld = nil
		end
		saveConfig()
		Overlay.sends += 1
	end

	-- (twice a second, and at once when the data is hidden or shown again)
	if Overlay.statusAt == nil or now - Overlay.statusAt >= 0.5 or Overlay.statusWhy ~= Overlay.hiddenWhy then
		Overlay.statusAt, Overlay.statusWhy = now, Overlay.hiddenWhy
		local home, away = 0, 0
		for _ in pairs(api.home.players) do home += 1 end
		for _ in pairs(api.away.players) do away += 1 end
		Overlay.status = if slot == nil then "Sending, but no arena found yet"
			else string.format("Sending %s | %s | players %d v %d | possession %.0f%% - %.0f%% | rounds finished %d%s%s%s", slot, tostring(Overlay.clock or "?"), home, away,
				api.home.possession, api.away.possession, #api.rounds, if api.isOvertime then " | overtime" else "",
				if api.isGracePeriod then " | goal grace period" else "", if Overlay.statsError ~= nil then " | stats error: " .. Overlay.statsError else "")
		if Overlay.hiddenWhy == "outside" then
			Overlay.status = Overlay.status .. " | EMPTY sent to overlays (no arena): the camera is outside every arena"
		elseif Overlay.hiddenWhy == "finished" then
			Overlay.status = Overlay.status .. " | HIDDEN from overlays: match over and the arena has emptied"
		end
		-- where the camera is for the outside rule (for the menu, and for setting the margin)
		local gap, margin = Overlay.outsideGap, Overlay.outsideMargin or OUTSIDE_MARGIN
		Overlay.cameraNote = if input.clearOutside ~= true then "rule switched off"
			elseif input.casting == true then "casting an arena, so that arena's data is sent wherever the camera is"
			elseif gap == nil then "cannot be placed (no arena list right now)"
			elseif gap <= 0 then "inside an arena"
			elseif gap <= margin then string.format("%.0f outside the nearest arena, which still counts as inside (margin %.0f)", gap, margin)
			else string.format("%.0f outside the nearest arena, past the margin of %.0f: outside every arena", gap, margin)
	end
end

return Overlay
