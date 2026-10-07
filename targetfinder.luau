-- Streamer Cam target finder (EXPERIMENTAL).
-- Hops the numbered matchmaking servers until the selected target shows up in the player list.
-- Network calls and station names come from august.matchmaker:
--   Network.getCurrentServer(), Network.connectToServer(stationName),
--   stations "Matchmaking", "Matchmaking_1" .. "Matchmaking_N".
-- This module never touches the camera. Every Orion call is guarded.
--
-- How one server is checked (nothing here advances on a blind timer):
--   connect -> ask to join. A refused request is retried on the SAME server, never skipped at once.
--   travel  -> wait until the game reports we are on that server. No new join is sent while a
--              server change is still in flight, so the search cannot run ahead of the spectator.
--   dwell   -> wait for that server's own player list, then look for the target.
-- Only after a server was really checked (or really could not be reached) does it move on.
-- Order: every matchmaking server once, then the home server, then every one again, then stop
-- (see stepInfo). A server that cannot be reached is skipped, never a reason to end the sweep.
-- "Every matchmaking server" is 0..max by default, or just the numbers typed into the server list
-- (for example only the servers of your own region), which makes a sweep much shorter.
-- Progress and the log are saved to config so a script reload on server change continues the search.
--
-- USUAL SERVERS: every time the selected player is seen on a matchmaking server (found by a search,
-- or simply there when the spectator arrives) that server's count for that player goes up by one.
-- A search then asks for the servers in this order: the ones this player has been seen on, most
-- often first; then the ones other remembered players were seen on; then the rest, in the order
-- they would have had anyway. It is only the ORDER that changes. Both sweeps still ask for every
-- server, so nothing is checked less often than before. (Setting: targetFinderFrequentFirst.)
--
-- A SERVER THAT THROWS THE SPECTATOR OUT: joining some servers does not load them, it drops the
-- spectator back to the game's main menu. The script stops there and loads again when the spectator
-- is back in, on some other server. So every join is written down before it is sent (the server, where
-- it was sent from, and when). A script that loads with such a join on record and is not on that server
-- knows the join threw it out: that server is left out of searches for two hours (Finder.avoid) and
-- the join is never sent a second time.

local SWEEPS = 2 -- full passes over the server list before giving up
local CONNECT_TRIES = 6 -- join requests per server before calling it unreachable and moving to the next number
local RETRY_GAP = 2 -- seconds between refused join requests
local TRAVEL_NO_SIGN = 10 -- accepted join, but nothing at all changed for this long: server is not running, move on
local TRAVEL_MAX = 45 -- longest wait for a server change that did start
local SETTLE = 3 -- seconds on a server before its player list is trusted (august.matchmaker value)
local DWELL_MAX = 8 -- longest wait for a player list that stays empty/unchanged
local EMPTY_FLIP_MAX = 20 -- same, when the server name changed instantly and we cannot tell if it is still loading
local RESUME_WAIT = 8 -- after a script reload, wait this long to see the expected server name
local SAVE_SETTLE = 0.75 -- pause between saving progress and asking to change servers
local RESUME_WINDOW = 240 -- a saved search older than this many seconds is dropped, not resumed
local MAX_RESUMES = 6 -- reload-loop breaker per server
local MAX_DETOURS = 2 -- times a join is re-sent after landing on an unexpected server, per target server
local KICK_GAP = 20 -- loaded this long after a join was sent, and still on the server it was sent from: thrown out, not a server change
local AVOID_SECONDS = 2 * 60 * 60 -- a server that threw the spectator out is left out of searches this long
local SEEN_PLAYERS = 8 -- usual servers are remembered for this many players (the most recently seen ones)
local SEEN_MAX = 99 -- highest count kept for one server
local AVOID_STOP = 2 -- with this many servers already left out, another one throwing the spectator out ends the search
local LOG_LINES = 16

local Finder = { log = {} }

local cfg = nil
local save = nil

local function resetRuntime()
	Finder.state = "idle" -- "idle" | "confirm" | "searching"
	Finder.status = ""
	Finder.name = ""
	Finder.station = ""
	Finder.serverNumber = -1 -- number of the server being checked now (-1 = the home server)
	Finder.step = 0 -- position in the search plan (see stepInfo)
	Finder.startNumber = 0 -- where in the list the first sweep starts (0 = its first entry)
	Finder.list = {} -- the matchmaking numbers this search sweeps (your list, or every number 0..max)
	Finder.rest = {} -- with your own list: the other numbers, checked once at the very end (optional)
	Finder.custom = false -- true when the list was typed in
	Finder.loaded = Finder.loaded or {} -- numbers that really loaded in recent searches (set)
	Finder.homeFirst = false -- this search looks at the home server before sweep 1 (opt-in, see Finder.start)
	Finder.seenOn = "" -- server the target was last actually seen on by this script
	Finder.maxServer = 20
	Finder.sweep = 1
	Finder.sweeps = SWEEPS
	Finder.phase = "" -- "connect" | "send" | "retry" | "travel" | "dwell" | "catchup" | "resume"
	Finder.checkedHere = "" -- name of the last server whose player list was properly examined
	Finder.skipped = {} -- servers given up on as "not running": lower-case name -> { step }
	Finder.patient = false -- true once a "dead" join turned out to be a slow, silent server change
	Finder.timer = 0
	Finder.tries = 0
	Finder.detours = 0
	Finder.resumes = 0
	Finder.reissues = 0
	Finder.preName = ""
	Finder.preSig = nil
	Finder.sawTransition = false
	Finder.otherTimer = 0
	Finder.travelTime = math.huge -- seconds between asking for a server and its name appearing
	Finder.loadSeen = 0 -- longest observed wait for a new server's own player list (instant-name engines)
	Finder.afterReload = false
	Finder.unavailable = 0
	Finder.origin = ""
	Finder.joining = nil -- station a join is being sent to (saved with where it was sent from and when)
	Finder.joinFrom = ""
	Finder.joinStamp = 0
	Finder.pendingJoin = nil -- after a script load: the join that was on record { station, from, stamp, age, timer }
	Finder.avoid = Finder.avoid or {} -- servers that threw the spectator out: number -> when (os.time)
	Finder.seen = Finder.seen or { order = {}, counts = {} } -- usual servers: player key -> { number -> times seen }
	Finder.order1, Finder.order2 = nil, nil -- the order the two sweeps of THIS search ask for the list in
	Finder.sightTimer = 0
	-- Auto-follow (opt-in): armed once the target has been seen on the current server.
	Finder.armed = false
	Finder.missing = 0
	Finder.watching = ""
	Finder.rosterServer = nil
	Finder.rosterSeen = false
	Finder.auto = false
	-- Set when the target was found; main.luau consumes it to move the camera to them.
	Finder.arrived = false
end
resetRuntime()

local function note(message)
	table.insert(Finder.log, message)
	while #Finder.log > LOG_LINES do table.remove(Finder.log, 1) end
	pcall(print, "[Streamer Cam server search] " .. message)
end

local function trim(text)
	if type(text) ~= "string" then return "" end
	return (text:match("^%s*(.-)%s*$")) or ""
end

local function now()
	local ok, value = pcall(os.time)
	return if ok and type(value) == "number" then value else 0
end

local function homeServer()
	return if cfg ~= nil and type(cfg.targetFinderHome) == "string" then cfg.targetFinderHome else ""
end

local function isMatchmakingStation(name)
	return string.sub(string.lower(name), 1, 11) == "matchmaking"
end

-- Server -1 is the remembered home/hub server (checked first when a search starts from a match server).
local function stationName(serverNumber)
	if serverNumber < 0 then return homeServer() end
	if serverNumber == 0 then return "Matchmaking" end
	return "Matchmaking_" .. tostring(serverNumber)
end

-- "Matchmaking" -> 0, "Matchmaking_7" -> 7, anything else -> nil
local function stationNumber(name)
	local lower = string.lower(name or "")
	if lower == "matchmaking" then return 0 end
	local digits = string.match(lower, "^matchmaking_(%d+)$")
	return if digits ~= nil then tonumber(digits) else nil
end

local function readMaxServer()
	local value = if cfg ~= nil then tonumber(cfg.targetFinderMaxServer) else nil
	if value == nil or value ~= value then return 20 end
	return math.clamp(math.floor(value + 0.5), 1, 60)
end

local function available()
	return Network ~= nil and Network.connectToServer ~= nil and Network.getCurrentServer ~= nil
end

local function currentServer()
	local ok, value = pcall(function() return Network.getCurrentServer() end)
	return if ok and type(value) == "string" then value else ""
end

-- Only an explicit false (or an error) counts as refused. The travel phase verifies the rest.
local function connect(station)
	local ok, accepted = pcall(function() return Network.connectToServer(station) end)
	return ok and accepted ~= false
end

local function sameServer(a, b)
	return a ~= "" and b ~= "" and string.lower(a) == string.lower(b)
end

-- Player count plus an order-independent fingerprint of the names, used to tell a server's own
-- player list apart from a stale copy of the previous server's list.
local function roster()
	local ok, count, mix = pcall(function()
		local n, sum = 0, 0
		for _, player in pairs(getGameData().players) do
			local name = tostring(player.playerName or player.playerId or player.id or "?")
			local h = #name
			for i = 1, #name do h = (h * 31 + string.byte(name, i)) % 1000003 end
			sum = (sum + h) % 2147483647
			n += 1
		end
		return n, sum
	end)
	if not ok or type(count) ~= "number" then return 0, "0:0" end
	return count, tostring(count) .. ":" .. tostring(mix)
end

local function persist()
	if cfg == nil then return end
	local searching = Finder.state == "searching"
	cfg.targetFinderActive = searching
	cfg.targetFinderServerNumber = nil -- (field of an older version)
	cfg.targetFinderStep = if searching then Finder.step else nil
	cfg.targetFinderStart = if searching then Finder.startNumber else nil
	-- the list this search was started with, so a reload (or editing the box) mid-search changes nothing
	cfg.targetFinderPlan = if searching and Finder.custom then table.concat(Finder.list, ",") else nil
	cfg.targetFinderPlanRest = if searching and Finder.custom then #Finder.rest > 0 else nil
	cfg.targetFinderHomeStep = if searching then Finder.homeFirst else nil
	cfg.targetFinderName = if searching then Finder.name else nil
	cfg.targetFinderOrigin = if searching then Finder.origin else nil
	cfg.targetFinderStamp = if searching then now() else nil
	cfg.targetFinderUptime = nil -- (old restart guard, removed: it could cancel a live search)
	cfg.targetFinderArmedName, cfg.targetFinderArmedStamp = nil, nil -- old marker, replaced by "armed by default"
	cfg.targetFinderSweep = if searching then Finder.sweep else nil
	cfg.targetFinderResumes = if searching then Finder.resumes else nil
	cfg.targetFinderReissues = if searching then Finder.reissues else nil
	cfg.targetFinderPreSig = if searching then Finder.preSig else nil
	cfg.targetFinderChecked = if searching then Finder.checkedHere else nil
	cfg.targetFinderPatient = if searching then Finder.patient else nil
	-- the order this search was started with (see buildOrders), so a reload carries on in the same order
	cfg.targetFinderOrder = if searching and Finder.order1 ~= nil and Finder.order2 ~= nil
		then table.concat(Finder.order1, ",") .. "|" .. table.concat(Finder.order2, ",") .. "|" .. table.concat(Finder.rest, ",") else nil
	local joining = searching and Finder.joining ~= nil
	cfg.targetFinderJoin = if joining then Finder.joining else nil
	cfg.targetFinderJoinFrom = if joining then Finder.joinFrom else nil
	cfg.targetFinderJoinStamp = if joining then Finder.joinStamp else nil
	-- The log survives a script reload so it is still readable afterwards. Saved as ONE string:
	-- everything else in config is a plain value, and a nested table might not be saved at all.
	local lines = {}
	for i = 1, #Finder.log do lines[i] = (string.gsub(tostring(Finder.log[i]), "\n", " ")) end
	cfg.targetFinderLog = table.concat(lines, "\n")
	cfg.targetFinderStatus = Finder.status
	cfg.targetFinderStatusStamp = now()
	if save ~= nil then pcall(save) end
end

-- Returns the player on the CURRENT server whose name matches (case-insensitive), or nil.
function Finder.findPlayer(name)
	local wanted = string.lower(trim(name))
	if wanted == "" then return nil end
	local ok, found = pcall(function()
		local data = getGameData()
		if data == nil or data.players == nil then return nil end
		for _, player in pairs(data.players) do
			if player ~= nil and type(player.playerName) == "string" and string.lower(trim(player.playerName)) == wanted then
				return player
			end
		end
		return nil
	end)
	return if ok then found else nil
end

-- Auto-follow is ARMED BY DEFAULT: with auto-follow on and a target selected, the target not
-- being on this server is enough to start a search. Nothing has to be "seen" first, so a script
-- reload on a server change can never leave it disarmed.
-- The only thing that disarms it is a search that ended without finding the target (two full
-- sweeps, Stop pressed, or an error). That is remembered in config, so it also holds across a
-- reload, and it is cleared as soon as the target is seen again or you re-arm by hand.
local function gaveUpOn(name)
	if cfg == nil or type(cfg.targetFinderGaveUp) ~= "string" or cfg.targetFinderGaveUp == "" then return false end
	return cfg.targetFinderGaveUp == string.lower(trim(name))
end

local function setGaveUp(name)
	if cfg == nil then return end
	local value = nil
	if name ~= nil and trim(name) ~= "" then value = string.lower(trim(name)) end
	if cfg.targetFinderGaveUp ~= value then
		cfg.targetFinderGaveUp = value
		if save ~= nil then pcall(save) end
	end
end

-- Servers tried for the current target since they were last seen (or since you re-armed by hand).
-- It is kept in config, apart from the search record, so a search that gets restarted over and
-- over still ends: the total is capped at two whole plans' worth of servers.
local function clearTried()
	if cfg ~= nil then cfg.targetFinderTried, cfg.targetFinderTriedName = nil, nil end
end

local function countTried(name)
	if cfg == nil then return 0 end
	local key = string.lower(trim(name))
	if cfg.targetFinderTriedName ~= key then cfg.targetFinderTriedName, cfg.targetFinderTried = key, 0 end
	cfg.targetFinderTried = (tonumber(cfg.targetFinderTried) or 0) + 1
	return cfg.targetFinderTried
end

-- Re-arm by hand: picking a target, ticking the auto-follow box, or starting a search.
function Finder.rearm()
	Finder.missing = 0
	clearTried()
	setGaveUp(nil)
end

-- One line on what auto-follow is doing, so "why is it not scanning" is visible in the GUI.
function Finder.autoText()
	if cfg == nil or cfg.targetFinderAutoFollow ~= true then return "off" end
	local name = trim(cfg.selectedTargetName)
	if name == "" then return "on, but no target is selected" end
	if Finder.state == "searching" then return "searching for " .. Finder.name end
	if Finder.findPlayer(name) ~= nil then return "armed, watching " .. name .. " (will search if they leave)" end
	if gaveUpOn(name) then
		return "stopped: the last search for " .. name .. " ended without finding them. Pick the target again or press Find target's server to re-arm."
	end
	local delay = math.max(tonumber(cfg.targetFinderAutoDelay) or 8, 3)
	return "armed, " .. name .. " is not on this server: search starts in " .. tostring(math.max(0, math.ceil(delay - Finder.missing))) .. "s"
end

-- Short description of what the search is doing right now, for the GUI.
function Finder.phaseText()
	if Finder.phase == "connect" or Finder.phase == "send" or Finder.phase == "retry" then
		return if Finder.tries > 1 then "join refused, retrying (" .. tostring(Finder.tries) .. "/" .. tostring(CONNECT_TRIES) .. ")" else "joining"
	elseif Finder.phase == "travel" then
		return "waiting to arrive"
	elseif Finder.phase == "dwell" or Finder.phase == "catchup" then
		return "checking players"
	elseif Finder.phase == "resume" then
		return "continuing after reload"
	end
	return ""
end

-- USUAL SERVERS (see the top of this file). Saved as one string: "ducky=2:1,5:4|ghost=7:2"
-- (player = server number : times seen), most recently seen player first.
local function seenKey(name)
	return (string.gsub(string.lower(trim(name)), "[|=%c]", "_"))
end

local function saveSeen()
	if cfg == nil then return end
	local parts = {}
	for _, key in ipairs(Finder.seen.order) do
		local counts = Finder.seen.counts[key] or {}
		local numbers, entries = {}, {}
		for n in pairs(counts) do numbers[#numbers + 1] = n end
		table.sort(numbers)
		for i, n in ipairs(numbers) do entries[i] = tostring(n) .. ":" .. tostring(counts[n]) end
		if #entries > 0 then parts[#parts + 1] = key .. "=" .. table.concat(entries, ",") end
	end
	cfg.targetFinderSeen = if #parts > 0 then table.concat(parts, "|") else nil
end

local function loadSeen()
	Finder.seen = { order = {}, counts = {} }
	if cfg == nil then return end
	if type(cfg.targetFinderSeen) == "string" then
		for part in string.gmatch(cfg.targetFinderSeen, "[^|]+") do
			local key, list = string.match(part, "^(.-)=(.*)$")
			if key ~= nil and key ~= "" and Finder.seen.counts[key] == nil and #Finder.seen.order < SEEN_PLAYERS then
				local counts, any = {}, false
				for number, count in string.gmatch(list, "(%d+):(%d+)") do
					local n, c = tonumber(number), tonumber(count)
					if #number <= 3 and #count <= 3 and n ~= nil and n <= 60 and c ~= nil and c >= 1 then
						counts[n] = math.min(c, SEEN_MAX)
						any = true
					end
				end
				if any then
					table.insert(Finder.seen.order, key)
					Finder.seen.counts[key] = counts
				end
			end
		end
	end
	saveSeen() -- (also tidies a value that could not be read)
end

-- One more sighting of this player on this server (matchmaking servers only: the hub is not swept).
local function recordSighting(name, server)
	local n = stationNumber(server)
	local key = seenKey(name)
	if n == nil or n > 60 or key == "" then return end
	local counts = Finder.seen.counts[key]
	if counts == nil then
		counts = {}
		Finder.seen.counts[key] = counts
	end
	counts[n] = math.min((counts[n] or 0) + 1, SEEN_MAX)
	-- most recently seen player first; only the last SEEN_PLAYERS players are kept
	for i = #Finder.seen.order, 1, -1 do
		if Finder.seen.order[i] == key then table.remove(Finder.seen.order, i) end
	end
	table.insert(Finder.seen.order, 1, key)
	while #Finder.seen.order > SEEN_PLAYERS do
		Finder.seen.counts[table.remove(Finder.seen.order)] = nil
	end
	saveSeen()
end

-- "name@server" of the sighting that was counted last, so standing on a server with the player
-- counts once, not every frame, and not again after a script reload.
local function sightingMark(name, server)
	return seenKey(name) .. "@" .. string.lower(server)
end

-- `numbers` in the order a search should ask for them: this player's usual servers first (most
-- often seen first), then servers other remembered players were seen on, then the rest. Servers
-- that are equal keep the order they came in. Returns a new array with the same members.
local function frequentFirst(numbers, name)
	local own = Finder.seen.counts[seenKey(name)] or {}
	local total = {}
	for _, counts in pairs(Finder.seen.counts) do
		for n, count in pairs(counts) do total[n] = (total[n] or 0) + count end
	end
	local sorted, position = {}, {}
	for i, n in ipairs(numbers) do
		sorted[i] = n
		position[n] = i
	end
	table.sort(sorted, function(a, b)
		local ownA, ownB = own[a] or 0, own[b] or 0
		if ownA ~= ownB then return ownA > ownB end
		local totalA, totalB = total[a] or 0, total[b] or 0
		if totalA ~= totalB then return totalA > totalB end
		return position[a] < position[b]
	end)
	return sorted
end

-- The servers this player has been seen on, most often first, as text: "Matchmaking_5 (4), Matchmaking_2 (1)".
function Finder.usualText(name)
	local own = Finder.seen.counts[seenKey(name)]
	if own == nil then return "" end
	local numbers, names = {}, {}
	for n in pairs(own) do numbers[#numbers + 1] = n end
	table.sort(numbers, function(a, b)
		if own[a] ~= own[b] then return own[a] > own[b] end
		return a < b
	end)
	for i, n in ipairs(numbers) do names[i] = (if n == 0 then "Matchmaking" else "Matchmaking_" .. tostring(n)) .. " (" .. tostring(own[n]) .. ")" end
	return table.concat(names, ", ")
end

-- How many players have servers remembered.
function Finder.seenPlayers()
	return #Finder.seen.order
end

-- "Forget remembered servers" in the menu.
function Finder.forgetSeen()
	Finder.seen = { order = {}, counts = {} }
	if cfg ~= nil then
		cfg.targetFinderSeen, cfg.targetFinderCounted = nil, nil
		if save ~= nil then pcall(save) end
	end
end

-- outcome: "found" keeps auto-follow armed; "gaveup" disarms it for this target until they are
-- seen again; nil leaves it as it is.
local function stop(message, outcome)
	if message ~= nil and message ~= "" then note(message) end
	local name = Finder.name
	Finder.state = "idle"
	Finder.phase = ""
	Finder.joining = nil
	Finder.status = message or ""
	if outcome == "found" then
		if cfg ~= nil then cfg.targetFinderGaveUp = nil end
		clearTried()
	elseif outcome == "gaveup" and cfg ~= nil and trim(name) ~= "" then
		cfg.targetFinderGaveUp = string.lower(trim(name))
	end
	persist()
end

local function found(player, where)
	-- Re-point the saved target at this server's copy of the player so follow resumes at once.
	if cfg ~= nil then
		cfg.selectedTargetName = player.playerName
		cfg.selectedTargetId = player.playerId or player.id
	end
	Finder.arrived = true
	Finder.seenOn = where
	Finder.markLoaded(where)
	-- a search only runs after the player left, so finding them is always a new visit
	recordSighting(tostring(player.playerName), where)
	if cfg ~= nil then cfg.targetFinderCounted = sightingMark(tostring(player.playerName), where) end
	stop("Found " .. tostring(player.playerName) .. " on " .. (if where ~= "" then where else "this server") .. ".", "found")
end

-- Reads a typed server list: "1, 2, 3", "1 2 3", "1-4", "0,2,5-7" (0 is the server that is just
-- called "Matchmaking"). Order is kept, repeats are dropped, anything that is not a number from
-- 0 to 60 is ignored. Returns an array of numbers (empty when nothing usable was typed).
function Finder.parseList(text)
	local numbers, seen = {}, {}
	if type(text) ~= "string" then return numbers end
	local function add(n)
		if n ~= nil and n >= 0 and n <= 60 and not seen[n] then
			seen[n] = true
			numbers[#numbers + 1] = n
		end
	end
	local position = 1
	for _ = 1, 200 do
		local from, to, first = string.find(text, "(%d+)", position)
		if from == nil then break end
		local low = if #first <= 3 then tonumber(first) else nil
		local rangeFrom, rangeTo, second = string.find(text, "^%s*%-%s*(%d+)", to + 1)
		if rangeFrom ~= nil then
			local high = if #second <= 3 then tonumber(second) else nil
			-- (a range that runs past 60 is taken to be a typo and left out, not stretched to 60)
			if low ~= nil and high ~= nil and low <= 60 and high <= 60 then
				for n = low, high, (if high >= low then 1 else -1) do add(n) end
			end
			position = rangeTo + 1
		else
			add(low)
			position = to + 1
		end
	end
	return numbers
end

local function buildPlan(listText, withRest)
	local list = Finder.parseList(listText)
	Finder.custom = #list > 0
	if not Finder.custom then
		for n = 0, Finder.maxServer do list[#list + 1] = n end
	end
	Finder.list, Finder.rest = list, {}
	Finder.order1, Finder.order2 = nil, nil -- (set by buildOrders or restoreOrders; without them: the plain order)
	if Finder.custom and withRest then
		local listed = {}
		for _, n in ipairs(list) do listed[n] = true end
		for n = 0, Finder.maxServer do
			if not listed[n] then table.insert(Finder.rest, n) end
		end
	end
end

-- What a search started now would sweep, for the GUI.
function Finder.planPreview()
	local numbers = Finder.parseList(if cfg ~= nil then cfg.targetFinderServerList else nil)
	if #numbers == 0 then
		local top = readMaxServer()
		return "every server, Matchmaking 0-" .. tostring(top) .. " (" .. tostring(top + 1) .. " servers per sweep)"
	end
	local names = {}
	for i, n in ipairs(numbers) do names[i] = if n == 0 then "Matchmaking" else "Matchmaking_" .. tostring(n) end
	return table.concat(names, ", ") .. " (" .. tostring(#numbers) .. (if #numbers == 1 then " server" else " servers") .. " per sweep)"
end

-- The numbers that really loaded in recent searches, lowest first, as text ("0, 1, 2, 5").
function Finder.loadedText()
	local numbers = {}
	for n in pairs(Finder.loaded) do numbers[#numbers + 1] = n end
	table.sort(numbers)
	return table.concat(numbers, ", ")
end

function Finder.markLoaded(name)
	local n = stationNumber(name)
	if n ~= nil and not Finder.loaded[n] then
		Finder.loaded[n] = true
		if cfg ~= nil then cfg.targetFinderLoaded = Finder.loadedText() end
	end
end

-- SERVERS LEFT OUT (they threw the spectator out). Saved as one string, "2:1759870000,7:1759871000"
-- (server number : when), so it survives the script load that follows being thrown out.
local function saveAvoid()
	if cfg == nil then return end
	local numbers, parts = {}, {}
	for n in pairs(Finder.avoid) do numbers[#numbers + 1] = n end
	table.sort(numbers)
	for i, n in ipairs(numbers) do parts[i] = tostring(n) .. ":" .. tostring(Finder.avoid[n]) end
	cfg.targetFinderAvoid = if #parts > 0 then table.concat(parts, ",") else nil
end

-- Drops the entries that are older than AVOID_SECONDS. (With no clock they stay until cleared by hand.)
local function pruneAvoid()
	local t, changed = now(), false
	for n, stamp in pairs(Finder.avoid) do
		if t > 0 and stamp > 0 and (t - stamp < 0 or t - stamp > AVOID_SECONDS) then
			Finder.avoid[n] = nil
			changed = true
		end
	end
	if changed then saveAvoid() end
end

local function loadAvoid()
	Finder.avoid = {}
	if cfg == nil then return end
	if type(cfg.targetFinderAvoid) == "string" then
		for number, stamp in string.gmatch(cfg.targetFinderAvoid, "(%d+):(%d+)") do
			local n, s = tonumber(number), tonumber(stamp)
			if #number <= 3 and n ~= nil and n <= 60 and s ~= nil then Finder.avoid[n] = s end
		end
	end
	pruneAvoid()
	saveAvoid() -- (also tidies a value that could not be read)
end

local function avoidCount()
	local count = 0
	for _ in pairs(Finder.avoid) do count += 1 end
	return count
end

-- The servers that are being left out, as text ("Matchmaking_2, Matchmaking_7"), "" when none.
function Finder.avoidText()
	local numbers, names = {}, {}
	for n in pairs(Finder.avoid) do numbers[#numbers + 1] = n end
	table.sort(numbers)
	for i, n in ipairs(numbers) do names[i] = if n == 0 then "Matchmaking" else "Matchmaking_" .. tostring(n) end
	return table.concat(names, ", ")
end

-- "Check those servers again" in the menu.
function Finder.clearAvoid()
	if next(Finder.avoid) == nil then return end
	Finder.avoid = {}
	saveAvoid()
	note("Servers that were left out will be checked again.")
	if save ~= nil then pcall(save) end
end

-- Was the join on record a join that threw the spectator out? Yes when the script has come back on
-- a server that is neither the one it asked for nor the one it asked from, or on the one it asked
-- from but long after (a script reload that is part of a server change comes straight away).
local function wasThrownOut(pending, here)
	if here == "" or sameServer(here, pending.station) then return false end
	return not sameServer(here, pending.from) or pending.age >= KICK_GAP
end

-- Records it. Returns true when so many servers are doing it that the search should stop.
local function thrownOut(pending, here)
	local n = stationNumber(pending.station)
	if n == nil then
		note(pending.station .. ": the join was sent, but the spectator came back on " .. here .. " instead. Not asking for it again.")
		return false
	end
	local already = avoidCount()
	Finder.avoid[n] = if pending.stamp > 0 then pending.stamp else now()
	saveAvoid()
	note(pending.station .. ": the join was sent, but the spectator came back on " .. here .. " instead (thrown out to the menu?). Leaving it out of searches for 2 hours.")
	return already >= AVOID_STOP
end

local TOO_MANY = tostring(AVOID_STOP + 1) .. " or more servers have thrown the spectator out in the last 2 hours, so it is probably not those servers. Search stopped. (The 'extra seconds on each server' slider may help.)"

-- The plan for one search, as numbered steps. "The list" is every matchmaking number 0..max, or
-- the numbers typed into the server list. N = how many are in it.
--   steps 0 .. N-1    sweep 1: EVERY server in the list once. It starts just after the server
--                     the search began on (at the top when it began on a hub) and wraps round, so a
--                     search that is restarted part-way carries on forward instead of starting over.
--   step  N           the home server, and only now, after a complete sweep has failed.
--   steps N+1 .. 2N   sweep 2: the list again, top to bottom.
--   then, only with a typed list and the option on: every OTHER number 0..max, once.
-- A server that cannot be joined is skipped and the plan moves to the next one, however many
-- fail in a row. Only after the last step does the search stop, disarm and go home.
-- (With the opt-in "check home first" there is one extra step in front: the home server.)
local function stepInfo(step)
	local list = Finder.list
	local n = #list
	if n == 0 then return nil, 2 end
	if Finder.homeFirst then
		if step == 0 then return -1, 1 end
		step -= 1
	end
	local first, second = Finder.order1, Finder.order2
	if step < n then
		if first ~= nil and #first == n then return first[step + 1], 1 end
		return list[((Finder.startNumber + step) % n) + 1], 1
	end
	if step == n then return -1, 1 end
	if step <= 2 * n then
		if second ~= nil and #second == n then return second[step - n], 2 end
		return list[step - n], 2
	end
	local extra = step - 2 * n
	if extra <= #Finder.rest then return Finder.rest[extra], 3 end
	return nil, 3
end

-- Fixes the order of this search: sweep 1 (starting after the server the search began on), sweep 2
-- (top to bottom) and the extra pass, each with the player's usual servers moved to the front when
-- the setting is on.
local function buildOrders(name)
	local n = #Finder.list
	local first, second = {}, {}
	for i = 1, n do
		first[i] = Finder.list[((Finder.startNumber + i - 1) % n) + 1]
		second[i] = Finder.list[i]
	end
	if cfg ~= nil and cfg.targetFinderFrequentFirst ~= false then
		first, second = frequentFirst(first, name), frequentFirst(second, name)
		Finder.rest = frequentFirst(Finder.rest, name)
	end
	Finder.order1, Finder.order2 = first, second
end

-- After a script reload: the order the search was started with, if what was saved is still the
-- same set of servers. (Otherwise the plain order is used.)
local function restoreOrders(text)
	if type(text) ~= "string" then return end
	local a, b, c = string.match(text, "^([%d,]*)|([%d,]*)|([%d,]*)$")
	if a == nil then return end
	local function sameMembers(order, list)
		if #order ~= #list then return false end
		local members = {}
		for _, n in ipairs(list) do members[n] = true end
		for _, n in ipairs(order) do
			if not members[n] then return false end
		end
		return true
	end
	local first, second, rest = Finder.parseList(a), Finder.parseList(b), Finder.parseList(c)
	if sameMembers(first, Finder.list) and sameMembers(second, Finder.list) and sameMembers(rest, Finder.rest) then
		Finder.order1, Finder.order2, Finder.rest = first, second, rest
	end
end

function Finder.progressText()
	local n = #Finder.list
	local index = Finder.step - (if Finder.homeFirst then 1 else 0)
	if Finder.serverNumber < 0 then
		return if index < 0 then "checking the home server first" else "sweep 1 done, checking the home server before sweep 2"
	end
	if Finder.sweep >= 3 then
		return "not on your list: checking the other servers, " .. tostring(index - 2 * n) .. " of " .. tostring(#Finder.rest)
	end
	if Finder.sweep > 1 then index -= n + 1 end
	return "sweep " .. tostring(Finder.sweep) .. " of " .. tostring(SWEEPS) .. ", server " .. tostring(index + 1) .. " of " .. tostring(n) .. (if Finder.custom then " (your list)" else "")
end

-- The search is over without finding the target: stop, disarm, and go back to the hub (or wherever
-- a non-matchmaking search started) instead of stranding the spectator.
local function finish(message)
	local destination = homeServer()
	if destination == "" and not isMatchmakingStation(Finder.origin) then destination = Finder.origin end
	-- Stop (and save) first: the server change below may reload this script.
	stop(message, "gaveup")
	if destination ~= "" and not sameServer(currentServer(), destination) then
		local going = connect(destination)
		Finder.status = message .. (if going then " Returning to " .. destination .. "." else " Could not return to " .. destination .. ".")
		note(if going then "Returning to " .. destination else "Could not return to " .. destination)
		persist()
	end
end

local function beginServer(step)
	local serverNumber, sweep = stepInfo(step)
	-- skipped: the home step when no home server is known, and servers that threw the spectator out
	while serverNumber ~= nil and ((serverNumber == -1 and homeServer() == "") or (serverNumber >= 0 and Finder.avoid[serverNumber] ~= nil)) do
		step += 1
		serverNumber, sweep = stepInfo(step)
	end
	if serverNumber == nil then
		if Finder.custom then
			finish(Finder.name .. " was not found on your server list (" .. table.concat(Finder.list, ", ") .. ") in " .. tostring(SWEEPS) .. " sweeps"
				.. (if #Finder.rest > 0 then ", or on the other servers" else "") .. ". Search stopped.")
		else
			finish(Finder.name .. " was not found on Matchmaking 0-" .. tostring(Finder.maxServer) .. " in " .. tostring(SWEEPS) .. " full sweeps. Search stopped.")
		end
		return
	end
	local tried = countTried(Finder.name)
	if tried > 2 * (2 * (Finder.maxServer + 1) + 2) then
		finish(Finder.name .. " was not found after trying " .. tostring(tried - 1) .. " servers (the search was restarted part-way). Search stopped.")
		return
	end
	if serverNumber == -1 and step == 0 then
		note(Finder.name .. " was on this match server and left: checking " .. homeServer() .. " first, then every matchmaking server.")
	elseif serverNumber == -1 then
		note("Sweep 1 done: every matchmaking server tried, " .. Finder.name .. " not found. Checking " .. homeServer() .. " before sweep 2.")
	elseif sweep > Finder.sweep and sweep >= 3 then
		note(Finder.name .. " is not on your list after " .. tostring(SWEEPS) .. " sweeps. Checking the other " .. tostring(#Finder.rest) .. " servers once.")
	elseif sweep > Finder.sweep then
		note("Starting sweep 2 of " .. tostring(SWEEPS) .. ".")
	end
	Finder.step = step
	Finder.sweep = sweep
	Finder.serverNumber = serverNumber
	Finder.station = stationName(serverNumber)
	Finder.phase = "connect"
	Finder.timer = 0
	Finder.tries = 0
	Finder.detours = 0
	Finder.resumes = 0
	Finder.reissues = 0
	Finder.preSig = nil
	Finder.sawTransition = false
	Finder.otherTimer = 0
	Finder.travelTime = math.huge
	Finder.afterReload = false
	Finder.joining = nil
	persist()
end

-- We are standing on a server that was earlier written off as "not running": server changes here
-- are slow and give no sign while they load. Stop trusting the short no-sign timeout, and go back
-- to the server after this one so nothing that was skipped in the meantime stays unchecked.
local function lateArrival(here)
	local entry = Finder.skipped[string.lower(here)]
	if entry == nil then return false end
	Finder.skipped = {}
	Finder.patient = true
	note(here .. " loaded after it was skipped: server changes are slow here. Waiting longer per server and re-checking the ones after it.")
	beginServer(entry.step + 1) -- redo everything that was skipped after it
	return true
end

-- Called once when the script loads. A search that was in progress (the server change reloaded the
-- script) continues from the saved server; anything stale is dropped so a fresh launch never hops.
function Finder.init(configTable, saveFunction)
	cfg, save = configTable, saveFunction
	resetRuntime()
	Finder.log = {}
	if cfg == nil then return end
	if type(cfg.targetFinderLog) == "string" then
		for line in string.gmatch(cfg.targetFinderLog, "[^\n]+") do
			if #Finder.log < LOG_LINES then table.insert(Finder.log, line) end
		end
	elseif type(cfg.targetFinderLog) == "table" then -- log saved in the older format
		for _, line in ipairs(cfg.targetFinderLog) do
			if type(line) == "string" and #Finder.log < LOG_LINES then table.insert(Finder.log, line) end
		end
		cfg.targetFinderLog = nil
	end
	Finder.maxServer = readMaxServer()
	Finder.loaded = {}
	for _, n in ipairs(Finder.parseList(cfg.targetFinderLoaded)) do Finder.loaded[n] = true end
	buildPlan(nil, false)
	loadAvoid()
	loadSeen()
	-- A join that was on record when the script stopped (see the top of this file).
	local onRecord = nil
	if type(cfg.targetFinderJoin) == "string" and cfg.targetFinderJoin ~= "" then
		local stamp = tonumber(cfg.targetFinderJoinStamp) or 0
		local age = if stamp > 0 and now() > 0 then now() - stamp else 0
		if age >= 0 and age <= AVOID_SECONDS then
			onRecord = { station = cfg.targetFinderJoin, from = if type(cfg.targetFinderJoinFrom) == "string" then cfg.targetFinderJoinFrom else "",
				stamp = stamp, age = age, timer = 0 }
		end
	end
	Finder.pendingJoin = onRecord
	-- Keep the last result visible across a reload (for example "Found ..." or "... Search stopped.").
	local statusAge = now() - (tonumber(cfg.targetFinderStatusStamp) or 0)
	if type(cfg.targetFinderStatus) == "string" and statusAge >= 0 and statusAge <= 600 then
		Finder.status = cfg.targetFinderStatus
	end
	if cfg.targetFinderActive ~= true then return end

	local name = trim(cfg.targetFinderName)
	local savedStep = tonumber(cfg.targetFinderStep)
	local age = now() - (tonumber(cfg.targetFinderStamp) or 0)
	if name == "" or savedStep == nil or savedStep ~= savedStep or age < 0 or age > RESUME_WINDOW then
		note("A saved search was not continued after the script reloaded (" .. (if name == "" then "no name saved" elseif savedStep == nil or savedStep ~= savedStep then "no position saved" else "saved " .. tostring(age) .. "s ago") .. ").")
		persist() -- state is idle: clears the saved search (auto-follow stays armed and will start a new one)
		return
	end

	Finder.state = "searching"
	Finder.status = ""
	Finder.name = name
	Finder.origin = if type(cfg.targetFinderOrigin) == "string" then cfg.targetFinderOrigin else ""
	buildPlan(cfg.targetFinderPlan, cfg.targetFinderPlanRest == true) -- the list the search was started with
	Finder.startNumber = math.clamp(math.floor(tonumber(cfg.targetFinderStart) or 0), 0, #Finder.list - 1)
	restoreOrders(cfg.targetFinderOrder)
	Finder.homeFirst = cfg.targetFinderHomeStep == true
	local resumeAt = math.max(0, math.floor(savedStep))
	local resumeNumber, resumeSweep = stepInfo(resumeAt)
	local resumes = (tonumber(cfg.targetFinderResumes) or 0) + 1
	local reissues = tonumber(cfg.targetFinderReissues) or 0
	if resumeNumber == nil or (resumeNumber == -1 and homeServer() == "") then
		beginServer(resumeAt) -- past the end of the plan, or a home step with no home: let the plan sort it out
		return
	end
	if resumes > MAX_RESUMES then
		note(stationName(resumeNumber) .. ": script reloaded " .. tostring(resumes) .. " times here, skipping")
		beginServer(resumeAt + 1)
		return
	end
	Finder.step = resumeAt
	Finder.sweep = resumeSweep
	Finder.serverNumber = resumeNumber
	Finder.station = stationName(resumeNumber)
	Finder.resumes = resumes
	Finder.reissues = reissues
	-- The roster seen just before the hop, so a leftover copy of the old server's list is recognised.
	Finder.preSig = if type(cfg.targetFinderPreSig) == "string" then cfg.targetFinderPreSig else nil
	Finder.checkedHere = if type(cfg.targetFinderChecked) == "string" then cfg.targetFinderChecked else ""
	Finder.patient = cfg.targetFinderPatient == true
	Finder.phase = "resume"
	Finder.timer = 0
	Finder.afterReload = true
	-- (the join on record stays on record until it is known how it ended)
	if onRecord ~= nil then Finder.joining, Finder.joinFrom, Finder.joinStamp = onRecord.station, onRecord.from, onRecord.stamp end
	persist()
end

-- First click: validate and ask for confirmation (a search moves the spectator between servers).
function Finder.request(name)
	name = trim(name)
	if name == "" then
		Finder.status = "Pick a target or type a name in Search player first."
		return
	end
	if not available() then
		Finder.status = "Server switching is not available in this Orion build."
		return
	end
	if Finder.findPlayer(name) ~= nil then
		Finder.status = name .. " is already on this server."
		return
	end
	Finder.name = name
	Finder.status = ""
	Finder.state = "confirm"
end

function Finder.start(name)
	name = trim(name)
	if name == "" or not available() then
		Finder.name = name
		stop("Could not start the server search.", "gaveup")
		return
	end
	local auto = Finder.auto
	Finder.auto = false
	Finder.name = name
	Finder.origin = currentServer()
	Finder.status = ""
	Finder.state = "searching"
	Finder.armed = false
	Finder.missing = 0
	Finder.arrived = false
	Finder.sweep = 1
	Finder.unavailable = 0
	Finder.checkedHere = Finder.origin -- the search starts because the target is not on this server
	if cfg ~= nil then cfg.targetFinderGaveUp = nil end -- a new search (manual or auto) is a fresh start
	if not auto then clearTried() end -- (an auto search keeps the count: it may be a restart)
	Finder.skipped = {}
	Finder.patient = false
	Finder.maxServer = readMaxServer()
	pruneAvoid()
	-- Remember the last non-matchmaking server as "home" (the hub you queue from).
	if cfg ~= nil and Finder.origin ~= "" and not isMatchmakingStation(Finder.origin) then
		cfg.targetFinderHome = Finder.origin
	end
	-- Started on a matchmaking server (the target's match ended, or a search was interrupted and
	-- is starting again): carry on with the NEXT number and go all the way round. The home server
	-- is only visited after that complete sweep.
	buildPlan(if cfg ~= nil then cfg.targetFinderServerList else nil, cfg ~= nil and cfg.targetFinderListFallback ~= false)
	if not Finder.custom then
		Finder.loaded = {} -- a search of everything re-learns which servers are running
		if cfg ~= nil then cfg.targetFinderLoaded = nil end
	end
	local originNumber = stationNumber(Finder.origin)
	Finder.startNumber = 0
	for index, n in ipairs(Finder.list) do
		if n == originNumber then Finder.startNumber = index % #Finder.list end -- the entry AFTER the one we are on
	end
	-- Opt-in shortcut (off by default): if the target was actually seen on this match server and
	-- then left it, their match is over and they are most likely back at the hub, so look there
	-- before the sweep. It never applies to a search that restarts on a server the target was not on.
	Finder.homeFirst = cfg ~= nil and cfg.targetFinderHomeFirst == true and homeServer() ~= ""
		and isMatchmakingStation(Finder.origin) and sameServer(Finder.seenOn, Finder.origin)
	note((if auto then "Auto search" else "Search") .. " for " .. name .. " started from " .. (if Finder.origin ~= "" then Finder.origin else "(unknown server)")
		.. (if Finder.custom then " | your list: " .. table.concat(Finder.list, ", ") else "")
		.. (if originNumber ~= nil and not Finder.homeFirst then ": carrying on at " .. stationName(Finder.list[Finder.startNumber + 1]) .. ", home only after the full sweep" else ""))
	buildOrders(name)
	if cfg ~= nil and cfg.targetFinderFrequentFirst ~= false then
		local usual = Finder.usualText(name)
		if usual ~= "" then note("Checking first, where " .. name .. " has been seen before: " .. usual) end
	end
	if next(Finder.avoid) ~= nil then note("Leaving out (they threw the spectator out earlier): " .. Finder.avoidText()) end
	beginServer(0)
end

function Finder.cancel()
	local wasSearching = Finder.state == "searching"
	Finder.armed = false
	Finder.missing = 0
	local here = if wasSearching then currentServer() else ""
	if wasSearching then
		stop("Server search stopped" .. (if here ~= "" then " on " .. here else "") .. ".", "gaveup")
	else
		stop("", nil)
	end
end

function Finder.fail(reason)
	stop("Server search error: " .. tostring(reason), "gaveup")
end

-- Opt-in auto-follow (armed by default, see above): whenever the selected target is not on this
-- server for targetFinderAutoDelay seconds, start a search without a click.
local function autoFollow(dt)
	if cfg == nil or cfg.targetFinderAutoFollow ~= true then
		Finder.armed, Finder.missing = false, 0
		return
	end
	local name = trim(cfg.selectedTargetName)
	if name == "" then
		Finder.armed, Finder.missing = false, 0
		return
	end
	if string.lower(name) ~= Finder.watching then
		Finder.watching, Finder.missing = string.lower(name), 0 -- a different target: start the count again
	end
	if not available() then return end -- Network can be missing briefly after a load: keep counting later
	if Finder.findPlayer(name) ~= nil then
		Finder.armed, Finder.missing = true, 0
		Finder.rosterServer, Finder.rosterSeen = currentServer(), true
		Finder.seenOn = Finder.rosterServer
		if cfg.targetFinderTried ~= nil then clearTried() end
		if gaveUpOn(name) then setGaveUp(nil) end -- seen again: armed again
		return
	end
	if gaveUpOn(name) then
		Finder.armed, Finder.missing = false, 0
		return
	end
	Finder.armed = true
	-- Until this server's player list has shown up at least once, an empty list most likely means
	-- "still loading", so it counts at a third of the speed. Once players have been seen here, an
	-- empty list is real (the target was the last one on it) and counts normally.
	local count = roster()
	local here = currentServer()
	if here ~= Finder.rosterServer then Finder.rosterServer, Finder.rosterSeen = here, false end
	if count > 0 then Finder.rosterSeen = true end
	local step = math.min(dt, 0.25)
	Finder.missing += if count > 0 or Finder.rosterSeen then step else step / 3
	if Finder.missing >= math.max(tonumber(cfg.targetFinderAutoDelay) or 8, 3) then
		Finder.auto = true
		Finder.start(name)
	end
end

-- The join that was on record when the script loaded, when no resumed search is dealing with it:
-- wait for the server name to settle, then see how it ended.
local function checkPendingJoin(dt, here, atOnce)
	local pending = Finder.pendingJoin
	if pending == nil then return end
	if sameServer(here, pending.station) then
		Finder.pendingJoin = nil -- arrived: the reload was the server change itself
		return
	end
	pending.timer += math.min(dt, 0.25)
	if pending.timer < RESUME_WAIT and not atOnce then return end
	Finder.pendingJoin = nil
	if wasThrownOut(pending, here) then
		local tooMany = thrownOut(pending, here)
		if tooMany and Finder.state == "searching" then
			stop(TOO_MANY, "gaveup")
		elseif save ~= nil then
			pcall(save)
		end
	end
end

-- About once a second while no search runs: is the selected player on this server? The first time
-- they are seen on a server (after being seen somewhere else, or not at all) counts as one visit.
local function trackSighting(dt)
	Finder.sightTimer += math.min(dt, 0.25)
	if Finder.sightTimer < 1 then return end
	Finder.sightTimer = 0
	if cfg == nil or not available() then return end
	local name = trim(cfg.selectedTargetName)
	if name == "" then return end
	local here = currentServer()
	if here == "" or Finder.findPlayer(name) == nil then return end
	local mark = sightingMark(name, here)
	if cfg.targetFinderCounted == mark then return end
	cfg.targetFinderCounted = mark
	recordSighting(name, here) -- (does nothing for a hub; the mark above still moves on)
	if save ~= nil then pcall(save) end
end

function Finder.update(dt)
	if Finder.state == "idle" then trackSighting(dt) end
	if Finder.pendingJoin ~= nil and not (Finder.state == "searching" and Finder.phase == "resume") and available() then
		checkPendingJoin(dt, currentServer(), false)
	end
	if Finder.state == "idle" then autoFollow(dt) return end
	if Finder.state ~= "searching" then return end

	-- Network can be missing for a moment while the script loads after a hop. Wait, do not skip.
	if not available() then
		Finder.unavailable += math.min(dt, 0.25)
		if Finder.unavailable >= 15 then stop("Server switching is not available in this Orion build.", "gaveup") end
		return
	end
	Finder.unavailable = 0

	-- Server loads can hitch: one long frame only ever counts as a quarter second.
	Finder.timer += math.min(dt, 0.25)
	local here = currentServer()
	local nextServer = Finder.step + 1 -- next step of the plan
	-- Standing on a server that is on the left-out list: it loads after all, so it comes off the list.
	if next(Finder.avoid) ~= nil then
		local hereNumber = stationNumber(here)
		if hereNumber ~= nil and Finder.avoid[hereNumber] ~= nil then
			Finder.avoid[hereNumber] = nil
			saveAvoid()
			note(here .. " loaded, so it is not left out any more.")
		end
	end

	if Finder.phase == "resume" then
		-- The script was reloaded mid-search (normally by the server change itself).
		local hereNumber = stationNumber(here)
		-- Are we on a server that comes LATER in this sweep than the saved record says? (The last
		-- save had not been written when the script reloaded.) Then carry on from where we really
		-- are instead of going back.
		local ahead = nil
		if hereNumber ~= nil and not sameServer(here, Finder.station) then
			for candidate = Finder.step + 1, Finder.step + #Finder.list + 1 do
				local number, sweep = stepInfo(candidate)
				if number == nil or sweep ~= Finder.sweep then break end
				if number == hereNumber then ahead = candidate break end
			end
		end
		if sameServer(here, Finder.station) then
			local hadJoin = Finder.joining ~= nil
			Finder.pendingJoin, Finder.joining = nil, nil
			Finder.phase, Finder.timer = "dwell", 0
			if hadJoin then persist() end -- arrived: the join is off the record
		elseif ahead ~= nil then
			Finder.pendingJoin, Finder.joining = nil, nil
			Finder.step = ahead
			Finder.serverNumber = hereNumber
			Finder.station = stationName(hereNumber)
			Finder.phase, Finder.timer, Finder.preSig = "dwell", 0, nil
			persist()
		elseif Finder.timer >= RESUME_WAIT then
			local pending = Finder.pendingJoin
			Finder.pendingJoin, Finder.joining = nil, nil
			-- The join for this server was sent and the script has come back somewhere else: it threw the
			-- spectator out. Also when that has now happened twice running (the join was sent again
			-- after the first reload). It is never sent again; the server is left out and the search moves on.
			if pending ~= nil and sameServer(pending.station, Finder.station) and here ~= ""
				and (wasThrownOut(pending, here) or Finder.reissues >= 1) then
				if thrownOut(pending, here) then
					stop(TOO_MANY, "gaveup")
				else
					beginServer(nextServer)
				end
			elseif Finder.reissues >= 1 then
				note(Finder.station .. ": could not confirm arrival after a reload (server name reads '" .. here .. "'), skipping")
				beginServer(nextServer)
			else
				Finder.reissues += 1
				Finder.afterReload = false
				Finder.phase, Finder.timer = "connect", 0
			end
		end
		return
	end

	if Finder.phase == "retry" then
		if Finder.timer >= RETRY_GAP then Finder.phase, Finder.timer = "connect", 0 end
		return
	end

	if Finder.phase == "connect" then
		-- The target may be right here (late player list, or they came back).
		local player = Finder.findPlayer(Finder.name)
		if player ~= nil then found(player, here) return end
		if Finder.station == "" then beginServer(nextServer) return end
		-- A join still on record from before the script loaded is settled before another one is sent.
		if Finder.pendingJoin ~= nil then
			checkPendingJoin(dt, here, true)
			if Finder.state ~= "searching" then return end
			if Finder.serverNumber >= 0 and Finder.avoid[Finder.serverNumber] ~= nil then beginServer(Finder.step) return end
		end
		-- Optional pause on each server before the first join for the next one (a setting, 0 = none).
		if Finder.tries == 0 and Finder.timer < math.clamp(tonumber(cfg ~= nil and cfg.targetFinderHopPause) or 0, 0, 60) then return end
		-- We are standing on a server whose list was never properly examined (a join that looked
		-- dead actually went through late). Check it fully before asking to go anywhere else.
		if here ~= "" and not sameServer(here, Finder.checkedHere) and not sameServer(here, Finder.station) and Finder.detours < MAX_DETOURS + 2 then
			Finder.detours += 1
			Finder.phase, Finder.timer, Finder.preSig = "catchup", 0, nil
			return
		end
		if sameServer(here, Finder.station) then
			if sameServer(here, Finder.checkedHere) then
				local count = roster()
				note(Finder.station .. ": already here, " .. tostring(count) .. " players, target not here")
				beginServer(nextServer)
			else
				Finder.phase, Finder.timer, Finder.preSig = "dwell", 0, nil -- arrived late: examine it properly
			end
			return
		end
		local _, signature = roster()
		Finder.preName, Finder.preSig, Finder.sawTransition, Finder.otherTimer = here, signature, false, 0
		Finder.tries += 1
		-- Save progress, then give the save a moment to be written before asking to change
		-- servers: the change may reload this script, and it must find this record afterwards.
		-- The join itself goes on record too: which server, from where, and when.
		Finder.joining, Finder.joinFrom, Finder.joinStamp = Finder.station, here, now()
		persist()
		Finder.phase, Finder.timer = "send", 0
		return
	end

	if Finder.phase == "send" then
		if Finder.timer < SAVE_SETTLE then return end
		local lastLook = Finder.findPlayer(Finder.name) -- one more look before leaving this server
		if lastLook ~= nil then found(lastLook, here) return end
		if connect(Finder.station) then
			Finder.phase, Finder.timer = "travel", 0
		elseif Finder.tries >= CONNECT_TRIES then
			note(Finder.station .. ": join refused " .. tostring(Finder.tries) .. " times, skipping")
			beginServer(nextServer)
		else
			Finder.joining = nil -- refused: nothing is in flight
			persist()
			Finder.phase, Finder.timer = "retry", 0
		end
		return
	end

	if Finder.phase == "travel" then
		if sameServer(here, Finder.station) then
			Finder.travelTime = Finder.timer
			Finder.phase, Finder.timer = "dwell", 0
			Finder.joining = nil -- arrived: the join is off the record
			persist()
			return
		end
		-- Sitting on some OTHER server (a late arrival from an earlier join, or a redirect): look for
		-- the target there too, and if we stay there, ask for the intended server again.
		if here ~= "" and Finder.preName ~= "" and not sameServer(here, Finder.preName) then
			Finder.sawTransition = true
			Finder.otherTimer += math.min(dt, 0.25)
			if Finder.otherTimer >= SETTLE then
				local player = Finder.findPlayer(Finder.name)
				if player ~= nil then found(player, here) return end
			end
			if Finder.otherTimer >= DWELL_MAX and Finder.detours < MAX_DETOURS then
				Finder.detours += 1
				Finder.checkedHere = here
				note(here .. ": landed here on the way to " .. Finder.station .. ", target not here; asking for " .. Finder.station .. " again")
				if lateArrival(here) then return end
				Finder.phase, Finder.timer = "connect", 0
				return
			end
		else
			Finder.otherTimer = 0
		end
		if not Finder.sawTransition then
			local _, signature = roster()
			if here ~= Finder.preName or dt >= 0.5 or signature ~= Finder.preSig then Finder.sawTransition = true end
		end
		if not Finder.sawTransition and not Finder.patient and Finder.timer >= TRAVEL_NO_SIGN then
			note(Finder.station .. ": join accepted but nothing changed in " .. tostring(TRAVEL_NO_SIGN) .. "s (server probably not running), skipping")
			Finder.skipped[string.lower(Finder.station)] = { step = Finder.step }
			beginServer(nextServer)
		elseif Finder.timer >= TRAVEL_MAX then
			note(Finder.station .. ": did not arrive in " .. tostring(TRAVEL_MAX) .. "s (server name reads '" .. here .. "'), skipping")
			beginServer(nextServer)
		end
		return
	end

	if Finder.phase == "catchup" then
		local count = roster()
		if count > 0 or Finder.timer >= SETTLE then
			local player = Finder.findPlayer(Finder.name)
			if player ~= nil then found(player, here) return end
		end
		if (count > 0 and Finder.timer >= SETTLE) or Finder.timer >= DWELL_MAX then
			if here ~= "" then
				Finder.checkedHere = here
				note(here .. ": arrived late, " .. tostring(count) .. " players, target not here")
				if lateArrival(here) then return end
			end
			Finder.phase, Finder.timer = "connect", 0
		end
		return
	end

	if Finder.phase == "dwell" then
		local count, signature = roster()
		-- fresh: this is the new server's own list. stale: still showing the previous server's
		-- players (two different servers never have the same non-empty roster), so keep waiting.
		local stale = count > 0 and Finder.preSig ~= nil and signature == Finder.preSig
		local fresh = count > 0 and not stale
		if fresh or Finder.timer >= SETTLE then
			local player = Finder.findPlayer(Finder.name)
			if player ~= nil then found(player, here) return end
		end
		-- If the server NAME changed the instant we asked, the name does not tell us when loading
		-- finished. A list that then stays empty may just mean "still loading", so wait longer:
		-- as long as loads have been seen to take here, or EMPTY_FLIP_MAX until one was seen.
		local instantName = Finder.travelTime < 0.5
		if instantName and fresh then Finder.loadSeen = math.max(Finder.loadSeen, Finder.timer) end
		local emptyLimit = DWELL_MAX
		if instantName and count == 0 then
			emptyLimit = if Finder.loadSeen > 0 then math.max(DWELL_MAX, Finder.loadSeen * 1.5 + SETTLE) else EMPTY_FLIP_MAX
		end
		local limit = if stale then TRAVEL_MAX else emptyLimit
		if (fresh and Finder.timer >= SETTLE) or Finder.timer >= limit then
			note(Finder.station .. ": " .. (if stale then "player list never refreshed, " else tostring(count) .. " players, ") .. "target not here" .. (if Finder.afterReload then " (script reloaded on arrival)" else ""))
			Finder.checkedHere = Finder.station
			if not stale and sameServer(here, Finder.station) then Finder.markLoaded(Finder.station) end
			beginServer(nextServer)
		end
		return
	end

	-- Unknown phase (should not happen): restart this server cleanly rather than stalling.
	Finder.phase, Finder.timer = "connect", 0
end

return Finder
