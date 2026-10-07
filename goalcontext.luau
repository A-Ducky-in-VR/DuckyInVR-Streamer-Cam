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
-- None of his code is copied here. Taken from Caster Camera 2.6.4: the arena box sizes, the goal
-- positions and the slot-name matching. The code itself is written for Streamer Cam.
--
-- Read-only arena/score adapter. No camera writes or overlay dependencies.
-- Geometry and slot matching are from Dennssen's Caster Camera 2.6.4.
-- Unsupported/custom layouts (including Strike) fail closed instead of guessing.
local Context = { time = 0, nextPoll = 0, entries = {}, baselines = {}, touches = {}, fired = {},
	available = false, status = "Waiting for score source", current = nil, lastSeen = 0,
	lastGoal = "None", scorer = "Unknown", events = 0 }

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function profile(slot)
	if slot:find("TKB") and not slot:find("Driftplex") and not slot:find("Full") and not slot:find("Playground") then
		return { kind = "3v3", size = Vec3.new(5100, 6750, 1440), offset = Vec3.new(0, 0, 650), goal = Vec3.new(3250, 0, 175) }
	elseif slot:find("Soccer") then
		return { kind = "driftblitz", size = Vec3.new(7270, 11825, 1440), offset = Vec3.new(0, 0, 740), goal = Vec3.new(5295, 0, 175), ballBased = true }
	elseif slot:find("Jakeball") or slot:find("Driftball")
		or (slot:find("TKB") and slot:find("Driftplex") and not slot:find("Full"))
		or slot:find("Beta") or slot:find("Gamma") or slot:find("Alpha") then
		return { kind = "4v4", size = Vec3.new(6715, 8400, 1490), offset = Vec3.new(0, 0, 685), goal = Vec3.new(4085, 0, 270) }
	elseif slot:lower():find("zdrift") then
		return { kind = "zdrift", size = Vec3.new(7180, 17800, 1710), offset = Vec3.new(0, 0, 880), goal = Vec3.new(8200, 0, 585), ballBased = true }
	end
	return nil
end

local function contains(entry, point)
	if point == nil then return false end
	local ok, result = pcall(function()
		local p = entry.rotation:inverse():rotateVector(point - entry.position) - entry.profile.offset
		local h = entry.profile.size * 0.5
		return math.abs(p.x) <= h.x and math.abs(p.y) <= h.y and math.abs(p.z) <= h.z
	end)
	return ok and result == true
end

local function sameGeometry(a, b)
	local ok, same = pcall(function()
		return a.profile.kind == b.profile.kind and Vec3.distance(a.position, b.position) < 1
			and a.rotation:getForwardVector():dot(b.rotation:getForwardVector()) > 0.9999
			and a.rotation:getUpVector():dot(b.rotation:getUpVector()) > 0.9999
	end)
	return ok and same
end

function Context:reset()
	self.nextPoll = 0
	self.lastPoll = nil
	self.entries, self.baselines, self.touches, self.fired = {}, {}, {}, {}
	self.current, self.lastBallPosition = nil, nil
	self.available = false
	self.status, self.lastGoal, self.scorer = "Waiting for score source", "None", "Unknown"
end

function Context:readEntries()
	local ok, list = pcall(function() return SpectatorGamemodes.listGamemodes() end)
	if not ok or type(list) ~= "table" then
		self.available = false
		self.status = "Score source unavailable"
		return {}
	end
	local entries = {}
	for _, gm in pairs(list) do
		local readOK, entry = pcall(function()
			local slot = gm:getSlotId()
			if type(slot) ~= "string" then return nil end
			local p = profile(slot)
			if p == nil then return nil end
			local data = SpectatorGamemodes.getGamemodeData(slot)
			local a, b = data.teams[1], data.teams[2]
			if not a or not b or not finite(a.score) or not finite(b.score)
				or a.score < 0 or b.score < 0 or a.score % 1 ~= 0 or b.score % 1 ~= 0 then return nil end
			local position, rotation = gm.transform.position, gm.transform.rotation
			-- Exercise the required transform operations inside the guard.
			rotation:inverse():rotateVector(position - position)
			local homeOffset, awayOffset = Quat.fromEuler(0, 0, 90), Quat.fromEuler(0, 0, -90)
			return { slot = slot, profile = p, position = position, rotation = rotation,
				home = { position = position + (rotation * homeOffset):rotateVector(p.goal), rotation = rotation * homeOffset:inverse() },
				away = { position = position + (rotation * awayOffset):rotateVector(p.goal), rotation = rotation * awayOffset:inverse() },
				scores = { a.score, b.score }, running = data.isGameRunning,
				colors = { a.teamColor and a.teamColor.primary, b.teamColor and b.teamColor.primary } }
		end)
		if readOK and entry then entries[entry.slot] = entry end
	end
	self.available = next(entries) ~= nil
	if not self.available then self.status = "No readable supported arena scores/geometry" end
	return entries
end

function Context:select(ballPosition, anchor, settings)
	local point = ballPosition or anchor
	local candidate, matches = nil, 0
	for _, entry in pairs(self.entries) do
		if contains(entry, point) then candidate = entry; matches += 1 end
	end
	if matches == 1 then
		if self.current == nil or self.current.slot ~= candidate.slot or not sameGeometry(self.current, candidate) then
			self.baselines[candidate.slot] = nil -- acquisition/reacquisition never celebrates old scores
			self.touches[candidate.slot] = nil
			self.lastBallPosition = nil
		end
		self.current = candidate
		self.lastSeen = self.time
		if ballPosition ~= nil then self.lastBallPosition = ballPosition; self.lastBallTime = self.time end
		self.status = "Tracking " .. candidate.slot
	elseif matches > 1 then
		self.current = nil
		self.lastBallPosition = nil
		self.status = "Ambiguous overlapping arenas; automatic effects suppressed"
	elseif self.current ~= nil and ballPosition == nil and self.time - self.lastSeen <= settings.goalExplosionArenaGraceSeconds then
		self.status = "Retaining arena while ball/anchor is missing"
	else
		self.current = nil
		self.lastBallPosition = nil
		if self.available then self.status = "No supported arena contains the ball/camera" end
	end
end

function Context:rememberTouch(ballPosition, players, settings)
	local entry = self.current
	if not entry or not ballPosition or not contains(entry, ballPosition) then return end
	local best, distance = nil, settings.goalExplosionTouchRadius or 95
	for _, player in pairs(players or {}) do
		local ok, d = pcall(function()
			if player.teamIndex ~= 0 and player.teamIndex ~= 1 then return nil end
			if not player.root or not contains(entry, player.root.position) then return nil end
			local result = Vec3.distance(ballPosition, player.root.position)
			if player.head and player.head.position then result = math.min(result, Vec3.distance(ballPosition, player.head.position)) end
			-- Caster util.luau transforms hand positions from root-local to world.
			for _, key in { "leftHand", "rightHand" } do
				local hand = player[key]
				if hand and hand.position and player.root.rotation then
					local p = player.root.position + player.root.rotation:rotateVector(hand.position)
					result = math.min(result, Vec3.distance(ballPosition, p))
				end
			end
			return result
		end)
		if ok and d and d < distance then best, distance = player, d end
	end
	if best then
		local touches = self.touches[entry.slot] or {}
		touches[best.teamIndex + 1] = { name = best.playerName or "Unknown", time = self.time }
		self.touches[entry.slot] = touches
	end
end

function Context:frame(entry, teamIndex, settings)
	if entry == nil then return nil, "No valid tracked goal frame" end
	local ok, frame = pcall(function()
		local scoring = if teamIndex == 0 then entry.home else entry.away
		local opposing = if teamIndex == 0 then entry.away else entry.home
		local position = opposing.position + entry.rotation:rotateVector(Vec3.new(0, 0, -60))
		if entry.profile.ballBased then
			if not self.current or self.current.slot ~= entry.slot or not self.lastBallPosition
				or self.time - (self.lastBallTime or 0) > settings.goalExplosionArenaGraceSeconds then return nil end
			position = self.lastBallPosition -- Caster's driftblitz/zdrift convention
		end
		local rotation = scoring.rotation * Quat.fromEuler(0, 0, 180)
		return { position = position, rotation = rotation,
			forward = rotation:rotateVector(Vec3.new(1, 0, 0)),
			right = rotation:rotateVector(Vec3.new(0, 1, 0)),
			up = rotation:rotateVector(Vec3.new(0, 0, 1)), color = entry.colors[teamIndex + 1] }
	end)
	if ok and frame then return frame end
	return nil, "Goal geometry unavailable; no camera-position substitute"
end

function Context:update(dt, ball, anchor, players, settings)
	self.time += dt
	local polling = self.time >= self.nextPoll
	local gap = polling and self.lastPoll ~= nil and self.time - self.lastPoll > math.max(1, settings.goalExplosionScorePollSeconds * 4)
	if polling then
		self.lastPoll = self.time
		self.nextPoll = self.time + settings.goalExplosionScorePollSeconds
		self.entries = self:readEntries()
		if gap then self.baselines = {}; self.touches = {} end
	end
	local ballPosition = if ball and ball.transform then ball.transform.position else nil
	self:select(ballPosition, anchor, settings)
	self:rememberTouch(ballPosition, players, settings)
	local events = {}
	if not polling then return events end
	local nextBaselines = {}
	for slot, entry in pairs(self.entries) do
		local previous = self.baselines[slot]
		local eligible = not settings.goalExplosionOnlyClosestArena or (self.current and self.current.slot == slot)
		local homeDelta = previous and entry.scores[1] - previous.scores[1] or 0
		local awayDelta = previous and entry.scores[2] - previous.scores[2] or 0
		local roundStart = previous and entry.running == true and previous.running ~= true
		local continuous = previous and sameGeometry(previous, entry) and not roundStart
			and homeDelta >= 0 and awayDelta >= 0 and homeDelta <= 1 and awayDelta <= 1
			and homeDelta + awayDelta <= 1
		if not continuous then self.touches[slot] = nil end
		if eligible and continuous and homeDelta + awayDelta == 1 then
			local teamIndex = if homeDelta == 1 then 0 else 1
			local eventKey = slot .. ":" .. tostring(teamIndex)
			if self.time - (self.fired[eventKey] or -math.huge) >= settings.goalExplosionDebounceSeconds then
				self.fired[eventKey] = self.time
				local touch = self.touches[slot] and self.touches[slot][teamIndex + 1]
				local scorer = if touch and self.time - touch.time <= settings.goalExplosionTouchMaxAgeSeconds then touch.name else "Unknown"
				local frame, reason = self:frame(entry, teamIndex, settings)
				self.lastGoal = slot .. " | " .. tostring(entry.scores[1]) .. " - " .. tostring(entry.scores[2])
				self.scorer = scorer
				if frame then
					table.insert(events, { frame = frame, teamIndex = teamIndex, scorer = scorer })
					self.events += 1
				else self.status = reason end
				self.touches[slot] = nil
			end
		end
		nextBaselines[slot] = entry
	end
	self.baselines = nextBaselines -- failed/disappeared slots reacquire with a new baseline
	return events
end

return Context
