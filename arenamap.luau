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
-- None of his code is copied here. Taken from Caster Camera 2.6.4: the arena box sizes, the kickoff
-- spot heights and the slot-name matching. The code itself is written for Streamer Cam.
--
-- Streamer Cam arena map: answers "which arena is this point in?" so the camera can be kept in
-- the SAME arena as the selected target. Read-only; no camera writes, no drawing.
--
-- Source of truth: SpectatorGamemodes.listGamemodes() -> one entry per arena (slot id + transform),
-- the same call Dennssen Caster / Follow+ use. Arena box sizes for known layouts come from Caster
-- 2.6.4 (also used by goalcontext.luau). A layout that is not recognised still takes part, with a
-- generic box, because all that matters here is that a player and the ball of the same arena
-- resolve to the same arena, and that two different arenas never do.
--
-- kickZ is the height of the kickoff spot above the arena origin (Caster 2.6.4's "place ball" box
-- for each layout); kickoff.luau uses it.
--
-- Every engine call is guarded. With no gamemode data at all, locate() returns nil and the caller
-- falls back to plain distance.
local ArenaMap = { entries = {}, count = 0, time = 0, nextPoll = 0, available = false }

local POLL_SECONDS = 1

local function profileFor(slot)
	local lower = string.lower(slot)
	if slot:find("TKB") and not slot:find("Driftplex") and not slot:find("Full") and not slot:find("Playground") then
		return 5100, 6750, 1440, 650, true, 3250, 300 -- 3v3 (centre-to-goal distance, kickoff spot height)
	elseif slot:find("Soccer") then
		return 7270, 11825, 1440, 740, true, 5295, 100 -- driftblitz
	elseif slot:find("Jakeball") or slot:find("Driftball")
		or (slot:find("TKB") and slot:find("Driftplex") and not slot:find("Full"))
		or slot:find("Beta") or slot:find("Gamma") or slot:find("Alpha") then
		return 6715, 8400, 1490, 685, true, 4085, 435 -- 4v4
	elseif lower:find("zdrift") then
		return 7180, 17800, 1710, 880, true, 8200, 500 -- zdrift
	end
	return 6715, 8400, 1490, 685, false, nil, nil -- unknown layout: generic 4v4-sized box
end

-- Re-reads the arena list about once a second. Call every tick with dt.
function ArenaMap.refresh(dt)
	ArenaMap.time += dt
	if ArenaMap.time < ArenaMap.nextPoll then return end
	ArenaMap.nextPoll = ArenaMap.time + POLL_SECONDS
	local ok, list = pcall(function() return SpectatorGamemodes.listGamemodes() end)
	local entries, count = {}, 0
	if ok and type(list) == "table" then
		for _, gamemode in pairs(list) do
			local readOK, entry = pcall(function()
				local slot = gamemode:getSlotId()
				if type(slot) ~= "string" then return nil end
				local position, rotation = gamemode.transform.position, gamemode.transform.rotation
				local inverse = rotation:inverse()
				inverse:rotateVector(position - position) -- exercise the operations locate() needs
				local sx, sy, sz, lift, known, goalY, kickZ = profileFor(slot)
				return { slot = slot, position = position, rotation = rotation, inverse = inverse,
					hx = sx * 0.5, hy = sy * 0.5, hz = sz * 0.5, lift = lift, known = known, goalY = goalY, kickZ = kickZ }
			end)
			if readOK and entry ~= nil and entries[entry.slot] == nil then
				entries[entry.slot] = entry
				count += 1
			end
		end
	end
	ArenaMap.entries, ArenaMap.count, ArenaMap.available = entries, count, count > 0
end

-- Distance from a point to an arena's box (0 when inside), and to the box centre.
local function measure(entry, point)
	local p = entry.inverse:rotateVector(point - entry.position)
	local x, y, z = p.x, p.y, p.z - entry.lift
	local dx = math.max(math.abs(x) - entry.hx, 0)
	local dy = math.max(math.abs(y) - entry.hy, 0)
	local dz = math.max(math.abs(z) - entry.hz, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz), math.sqrt(x * x + y * y + z * z)
end

local KNOWN_MARGIN = 600 -- a goal pocket reaches a little outside its arena's box

-- Best entry for a point among entries accepted by `filter`.
local function nearest(point, knownOnly, limit)
	local bestSlot, bestOutside, bestCentre = nil, math.huge, math.huge
	for slot, entry in pairs(ArenaMap.entries) do
		if entry.known or not knownOnly then
			local ok, outside, centre = pcall(measure, entry, point)
			if ok and outside == outside and centre == centre and outside <= limit then
				-- Nearest box wins; boxes that tie (overlap, or equally far) are split by nearest
				-- centre, then by slot name so the answer never depends on table iteration order.
				local better = outside < bestOutside - 0.5
				if not better and math.abs(outside - bestOutside) <= 0.5 then
					better = centre < bestCentre - 0.5 or (math.abs(centre - bestCentre) <= 0.5 and (bestSlot == nil or slot < bestSlot))
				end
				if better then bestSlot, bestOutside, bestCentre = slot, outside, centre end
			end
		end
	end
	return bestSlot
end

-- Returns the slot id of the arena the point belongs to, or nil when there is no arena data.
-- A recognised arena that contains the point (or nearly does: a ball in a goal pocket sits just
-- outside the box) always wins over unrecognised gamemode slots that may overlap it. Otherwise
-- the nearest box of any slot is used.
function ArenaMap.locate(point)
	if point == nil or not ArenaMap.available then return nil end
	return nearest(point, true, KNOWN_MARGIN) or nearest(point, false, math.huge)
end

-- Keeps a camera position inside the playable part of the arena that `reference` (the ball) is in:
-- not behind either goal line, not outside the side walls, not above the ceiling. Only arenas with
-- a recognised layout are clamped (their real size is known); anything else is returned unchanged.
-- Returns the (possibly moved) point and whether it was moved.
function ArenaMap.keepInside(point, reference, sideMargin, goalMargin, topMargin)
	if point == nil or reference == nil or not ArenaMap.available then return point, false end
	local slot = nearest(reference, true, KNOWN_MARGIN)
	local entry = if slot ~= nil then ArenaMap.entries[slot] else nil
	if entry == nil or entry.goalY == nil then return point, false end
	local p = entry.inverse:rotateVector(point - entry.position)
	local limitX = math.max(entry.hx - sideMargin, 100)
	local limitY = math.max(entry.goalY - goalMargin, 100)
	local top = entry.lift + entry.hz - topMargin
	local x = math.clamp(p.x, -limitX, limitX)
	local y = math.clamp(p.y, -limitY, limitY)
	local z = math.min(p.z, top)
	if x == p.x and y == p.y and z == p.z then return point, false end
	return entry.position + entry.rotation:rotateVector(Vec3.new(x, y, z)), true
end

return ArenaMap
