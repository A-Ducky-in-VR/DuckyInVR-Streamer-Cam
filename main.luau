-- Streamer Cam (public release) v1.0.0
-- Package: duckyinvr.streamercam.public
--
-- A spectator camera for Orion Drift. Pick a player and it follows them, and changes camera by
-- itself when they go into an arena. It also has ball cams, a free cam, goal explosions, kickoff
-- graphics, ball trails and a pet that follows the player around.
--
-- How to use it, credits and licences: README.md (and THIRD-PARTY-NOTICES.md).
-- Most of this code was written with AI assistance; see README.md.
--
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
-- None of his code is copied into this file. Taken from Caster Camera: the rule for telling a match
-- ball from a toy ball, the rule for who "has the ball", and the names and values of the game's
-- post-processing settings. The modules that use more of his material say so at their own top.

local ParticleSystem = require("particlesystem")
local GoalContext = require("goalcontext")
local TargetFinder = require("targetfinder")
local ArenaMap = require("arenamap")
local GoalEffects = require("goaleffects")
local BallTrails = require("balltrails")
local SpecPets = require("specpets")
local Kickoff = require("kickoff")
local Overlay = require("overlay")

local VERSION = "1.0.0"

-- =========================
-- Settings
-- =========================

-- Every setting and its value on a fresh install. A value that was saved before always wins.
-- (The selected player's id, the saved Fixed Camera spot and the overlay data have no default.)
local DEFAULTS = {
	-- Target and camera modes
	selectedTargetName = "", autoCasterEnabled = true, outsideArenaMode = "Third Person - Head Movement", insideArenaMode = "Third Person - Ball Look",
	cameraFov = 90, snapDistance = 650,
	-- Third person and first person
	thirdPersonDistance = 120, thirdPersonHeight = 35, followSpeed = 22, firstPersonForwardOffset = 2, firstPersonHeightOffset = 0,
	firstPersonSpeed = 22,
	-- Third Person - Ball Look, and Fixed Camera
	ballLookDistance = 155, ballLookHeight = 50, ballLookSpeed = 28, fixedCamLookAtBall = true,
	-- Vlog Camera (works with Follow+ when it is installed)
	vlogFollowPlusEnabled = true, vlogFollowRadius = 35, vlogFollowSmoothing = 0.08, vlogFov = 95, vlogGrabLookAtTarget = true, vlogGrabRadius = 42,
	vlogGrabReleaseRadius = 85, vlogNativeGrabEnabled = true,
	-- Free Cam
	freeCamCollisionSafety = false, freeCamControllerDeadzone = 0.12, freeCamControllerForwardUsesCameraFacing = true, freeCamControllerLookSpeed = 115,
	freeCamControllerMoveMultiplier = 1, freeCamGravityAlignedLook = true, freeCamGravityChaseSpeed = 5, freeCamGroundPlaneMovement = true,
	freeCamInvertControllerMoveY = false, freeCamInvertControllerY = false, freeCamLookSensitivity = 0.12, freeCamMoveSpeed = 650, freeCamNoClip = true,
	freeCamSlowMultiplier = 0.25, freeCamSprintMultiplier = 3,
	-- SpecPet: pet choice, and the Kitty / Pidgeon settings
	specPetEatBalls = true, specPetHeadpats = true, specPetRest = true, specPetRestSeconds = 10, specPetSpeed = 3, specPetType = "Duckling",
	specPetWalkCycle = true, specPetWalkHeight = 30,
	-- SpecPet: Duckling
	ducklingDistance = 125, ducklingFacePetHoldSeconds = 1.6, ducklingFacePlayerSpeed = 70, ducklingFeedingDuration = 1.2,
	ducklingFeedingEnabled = true, ducklingFeedingHandRadius = 40, ducklingFollowLeashDistance = 165, ducklingHappyEmoteHoldSeconds = 3,
	ducklingHeadpatRadius = 30, ducklingHeadpatReleaseGrace = 0.25,
	ducklingHeadpatsEnabled = true, ducklingHeight = 10, ducklingInteractEveryone = true, ducklingPersonalSpace = 70, ducklingRuffleDuration = 0.7,
	ducklingRuffleMaxTilt = 0.22, ducklingRuffleSpeed = 45, ducklingSpeed = 10, ducklingTreatCooldown = 1, ducklingTreatRadius = 35,
	ducklingTreatRequireHandNear = true, ducklingTreatsEnabled = true,
	-- Ball cams: Simple Ball Cam, Ball Carrier, goal cam
	simpleBallCamCatchupMultiplier = 10, simpleBallCamCatchupSmoothBoost = 28, simpleBallCamCatchupStartDistance = 300,
	simpleBallCamDirectionSmoothSpeed = 4, simpleBallCamDistance = 620, simpleBallCamFocusSmoothSpeed = 5, simpleBallCamFollowSpeed = 16,
	simpleBallCamFov = 96, simpleBallCamHeight = 260, simpleBallCamLead = 0.22, simpleBallCamMaxCatchupStepPerSecond = 12000,
	simpleBallCamMaxStepPerSecond = 4200, ballCamStayInArena = true, carrierCamDistance = 230, carrierCamHeight = 75, carrierContactDistance = 45,
	carrierHoldSeconds = 0.35, carrierLooseSeconds = 0.35, goalCamDistance = 1300, goalCamEnabled = true, goalCamFov = 90, goalCamHeight = 420,
	goalExplosionHoldCamera = true, goalExplosionHoldMaxSeconds = 6, autoCastArenaLockGraceSeconds = 8, autoCastArenaLockRadius = 1800,
	autoCastBallSearchRadius = 1600, autoCastLockToSelectedArena = true, ballCamArenaReleaseSeconds = 60,
	-- Graphics: ball outline, ball trail, markers
	graphicsBallOutlineEnabled = true, graphicsBallOutlineSize = 1.3, graphicsBallOutlineThickness = 2.5, graphicsBallTrailBlueSpeed = 300,
	graphicsBallTrailCoreWidth = 0.72, graphicsBallTrailEnabled = true, graphicsBallTrailGlowWidth = 2.2, graphicsBallTrailRedSpeed = 2200,
	graphicsBallTrailSpeedColorEnabled = false, graphicsBallTrailStyle = "Boost Ribbon", graphicsClearBeforeDraw = false, graphicsDrawLifetime = 0.18,
	graphicsEnabled = true, graphicsLineToBallEnabled = false, graphicsTargetMarkerEnabled = true, graphicsTargetMarkerShape = "Diamond",
	graphicsTargetMarkerSize = 18, graphicsTeamMarkerHeight = 58, graphicsTeamMarkerSize = 12, graphicsTeamMarkersEnabled = false,
	graphicsTeamMarkersSameTeamOnly = true, graphicsTeamMarkersShowTarget = false, graphicsTeamMarkersUniqueColors = true, graphicsTrailDuration = 1.15,
	graphicsTrailThickness = 4, graphicsVibrance = 1.2,
	-- Goal explosions
	customGoalExplosionsEnabled = true, goalExplosionArenaGraceSeconds = 3, goalExplosionAssignment1Player = "",
	goalExplosionAssignment1Type = "Ducky Spirit", goalExplosionAssignment2Player = "", goalExplosionAssignment2Type = "Dueling Dragons",
	goalExplosionAssignment3Player = "", goalExplosionAssignment3Type = "Claw Strike", goalExplosionAssignment4Player = "",
	goalExplosionAssignment4Type = "Crumble", goalExplosionAssignment5Player = "", goalExplosionAssignment5Type = "Basic Burst",
	goalExplosionColorMode = "Default", goalExplosionCustomB = 1, goalExplosionCustomG = 0.65, goalExplosionCustomR = 0,
	goalExplosionDebounceSeconds = 2, goalExplosionDramaticScale = 1.35, goalExplosionDrawLifetime = 0.08, goalExplosionEmberCollisionEnabled = false,
	goalExplosionFallbackType = "Ripple Wave", goalExplosionLifetime = 1.35, goalExplosionMaxActiveParticles = 120, goalExplosionMaxLinesPerTick = 256,
	goalExplosionOnlyClosestArena = true, goalExplosionParticleCount = 110, goalExplosionRingCount = 3, goalExplosionRingSegments = 32,
	goalExplosionRippleMaxRadius = 760, goalExplosionRippleRise = 10, goalExplosionRippleThickness = 7, goalExplosionScorePollSeconds = 0.1,
	goalExplosionTouchMaxAgeSeconds = 4, goalExplosionTouchRadius = 95, goalExplosionType = "Ripple Wave", goalExplosionUseCasterParticles = false,
	goalExplosionVibrance = 1.35, goalTestSide = 0,
	-- Kickoff graphics and kickoff cam
	kickoffCamAfterGoSeconds = 3, kickoffCamDistance = 1900, kickoffCamEnabled = true, kickoffCamFov = 100, kickoffCamHeight = 450,
	kickoffCamOrbitSpeed = 22, kickoffCamStyle = "Sideline", kickoffColorMode = "Team Color", kickoffCountdownSeconds = 5,
	kickoffEveryCountdown = false, kickoffGraphicScale = 1, kickoffGraphicStyle = "Countdown Ring", kickoffGraphicsEnabled = true,
	kickoffShowNumbers = true,
	-- Picture filter (off until switched on)
	visualApplyEnginePostProcessing = true, visualBloom = 1, visualChromaticAberration = 0, visualContrast = 1.35, visualExposure = 1.15,
	visualFilmGrain = 0, visualFilterPreset = "Punchy Broadcast", visualGamma = 0.9, visualMotionBlur = 0, visualSaturation = 1.45,
	visualSettingsEnabled = false, visualShaderStrength = 1, visualSharpness = 0.25, visualTemperature = 0, visualTint = 0, visualUsePresetFov = true,
	visualUsePresetGraphics = true, visualVignette = 0.12,
	-- Server search (experimental)
	targetFinderAutoDelay = 8, targetFinderAutoFollow = false, targetFinderHomeFirst = false, targetFinderListFallback = true,
	targetFinderMaxServer = 20, targetFinderServerList = "", targetFinderHopPause = 0, targetFinderFrequentFirst = true,
	-- Send Overlay Info for OD Caster Bridge (off until switched on)
	sendOverlayInfo = false, overlayClearAfterMatch = true,
	overlayClearOutsideArena = true, overlayOutsideSeconds = 2, overlayOutsideMargin = 2500,
}
for key, value in pairs(DEFAULTS) do
	if config[key] == nil then config[key] = value end
end

-- Saved choices are checked, so a value that is not on its list any more cannot get in the way.
if config.specPetType ~= "Kitty" and config.specPetType ~= "Pidgeon" then config.specPetType = "Duckling" end
if config.kickoffCamStyle ~= "Orbit" and config.kickoffCamStyle ~= "Top Down" then config.kickoffCamStyle = "Sideline" end
if type(config.kickoffGraphicStyle) ~= "string" then config.kickoffGraphicStyle = "Countdown Ring" end
if type(config.kickoffColorMode) ~= "string" then config.kickoffColorMode = "Team Color" end
if type(config.targetFinderServerList) ~= "string" then config.targetFinderServerList = "" end
config.kickoffEveryCountdown = config.kickoffEveryCountdown == true
config.targetFinderHomeFirst = config.targetFinderHomeFirst == true
config.goalTestSide = if config.goalTestSide == 1 then 1 else 0
-- The explosion preview camera never survives a restart: a session that was left in it starts in
-- the mode it was switched from.
config.goalTestLoop = false
if config.insideArenaMode == "Goal Explosion Test Cam" then
	config.insideArenaMode = if type(config.goalTestPreviousMode) == "string" and config.goalTestPreviousMode ~= "Goal Explosion Test Cam"
		then config.goalTestPreviousMode else "Autocast - Simple Ball Cam"
end
-- Send Overlay Info is off unless ticked. Off: nothing of it is left in the settings file.
-- On: rounds that already finished survive a script reload.
config.sendOverlayInfo = config.sendOverlayInfo == true
if config.sendOverlayInfo then pcall(Overlay.restore, config.api, config.apiHeld) else config.api, config.apiHeld = nil, nil end
-- (The save function is looked up each time it is called, in case saveConfig is not defined yet
-- while the script is still loading.)
pcall(TargetFinder.init, config, function() saveConfig() end)
if TargetFinder.state == "searching" then alwaysTick = true end -- resumed after a server change

-- =========================
-- Runtime state
-- =========================

local targetSearch = ""
local statusText = "Loaded. Pick a target player."
local visualStatus = "not applied yet" -- picture filter: what happened the last time it was applied
local visualEffectiveFov = nil -- the FOV a filter preset is showing right now, if it sets one
local lastTargetId = nil
local wasInsideArena = false
local simpleBallSmoothFocus = nil
local simpleBallSmoothBackDir = nil
local simpleBallCamCurrentBall = nil
-- Ball cam arena lock. The ball cams (Simple Ball Cam, Ball Carrier) cast ONE arena: the selected
-- target's arena, or with no target on this server the arena they were already casting (the first
-- time: the arena whose ball is nearest the camera). arenaPin.ball is that arena's ball, and
-- arenaPin.key the arena. While it is locked the camera never takes a ball from another arena.
local arenaPin = { ball = nil, started = false, key = nil, ballPos = nil, ballTime = -math.huge, time = 0, challenger = 0, id = nil, emptyTime = 0, goneTime = 0 }
local arenaLockCenter = nil
local arenaLockLastSeen = 0
local goalExplosionParticles = {}
local goalRuntime = { ball = nil, ballKnown = false, lines = 0, attempts = 0, dropped = 0,
	status = "Waiting for first tick", pendingTest = nil, enabled = false, simpleActive = false }
local graphicsTrail = {}
local graphicsTrailTimer = 0
local lastGraphicsTrailBallPosition = nil
local graphicsFailureCount = 0
local lastGraphicsDrawOkTime = 0
local freeCamInitialized = false
local freeCamRotEuler = nil
local freeCamGravityChaser = nil
local freeCamPersistentGravityRotation = nil
local followPlusCam = nil
local followPlusTick = nil
local followPlusVersion = ""
local vlogBridgeActive = false
local vlogNativeGrabActive = false
local vlogNativeGrabLeftHand = false

local duckState = {
	lastTargetPosition = nil,
	ruffleTimer = 0,
	happyEmoteTimer = 0,
	headpatCooldown = 0,
	headpatTouching = false,
	headpatReleaseTimer = 0,
	faceHoldTimer = 0,
	treatCooldown = 0,
	feedTimer = 0,
	feedCooldown = 0,
	idleTime = 0,
	idleAnchorPosition = nil,
}

local OUTSIDE_MODES = {
	"Third Person - Head Movement",
	"First Person POV",
	"Vlog Camera (Follow+)",
	"Free Cam",
	"SpecPet",
}

local INSIDE_MODES = {
	"Third Person - Head Movement",
	"First Person POV",
	"Vlog Camera (Follow+)",
	"Free Cam",
	"SpecPet",
	"Third Person - Ball Look",
	"Autocast - Simple Ball Cam",
	"Autocast - Simple Ball Cam + Goal Cam", -- same ball cam; cuts to the goal cam for each goal explosion
	"Autocast - Ball Carrier",
	"Fixed Camera",
}
-- "Goal Explosion Test Cam" is also an inside mode, but it is not on the list: the preview
-- buttons in the goal explosion menu switch it on and off.

-- A saved mode that is not on its list falls back to the default one.
-- (The 0.1 public beta called its ball cam "Basic Ball Follow".)
if config.insideArenaMode == "Basic Ball Follow" then config.insideArenaMode = "Autocast - Simple Ball Cam" end
do
	local function known(list, value)
		for _, name in ipairs(list) do
			if name == value then return true end
		end
		return false
	end
	if not known(OUTSIDE_MODES, config.outsideArenaMode) then config.outsideArenaMode = DEFAULTS.outsideArenaMode end
	if config.insideArenaMode ~= "Goal Explosion Test Cam" and not known(INSIDE_MODES, config.insideArenaMode) then
		config.insideArenaMode = DEFAULTS.insideArenaMode
	end
end

local TARGET_MARKER_SHAPES = {
	"Diamond",
	"Yellow Ducky",
}

local BALL_TRAIL_STYLES = {
	"Boost Ribbon",
	"Rocket League Boost",
	"Comet Tail",
	"Plasma Beam",
	"Sparkle Stream",
	"Classic Line",
}
-- Styles drawn by balltrails.luau (Comet Tail and Sparkle Stream above are drawn there too).
for _, styleName in ipairs(BallTrails.newStyles) do table.insert(BALL_TRAIL_STYLES, styleName) end

local VISUAL_FILTER_PRESET_NAMES = {
	"Custom",
	"Punchy Broadcast",
	"Cinematic",
	"Cyberpunk Blue",
	"Anime Pop",
	"Warm Sunset",
	"Cool Arena",
	"Noir",
}

local VISUAL_FILTER_PRESETS = {
	["Punchy Broadcast"] = { exposure = 1.15, gamma = 0.9, contrast = 1.35, saturation = 1.45, bloom = 1.0, vignette = 0.12, chromaticAberration = 0.0, filmGrain = 0.0, sharpness = 0.25, temperature = 0.0, tint = 0.0, shader = "Broadcast", fov = 94, graphicsVibrance = 1.45, trailThickness = 1.15 },
	["Cinematic"] = { exposure = 0.55, gamma = 0.82, contrast = 1.65, saturation = 1.08, bloom = 0.75, vignette = 0.32, chromaticAberration = 0.04, filmGrain = 0.18, sharpness = 0.18, temperature = -0.08, tint = 0.03, shader = "Cinematic", fov = 78, graphicsVibrance = 1.05, trailThickness = 0.9 },
	["Cyberpunk Blue"] = { exposure = 0.9, gamma = 0.78, contrast = 1.75, saturation = 1.8, bloom = 1.8, vignette = 0.18, chromaticAberration = 0.08, filmGrain = 0.08, sharpness = 0.35, temperature = -0.45, tint = 0.22, shader = "Cyberpunk", fov = 100, graphicsVibrance = 2.0, trailThickness = 1.25 },
	["Anime Pop"] = { exposure = 1.25, gamma = 0.92, contrast = 1.28, saturation = 2.2, bloom = 1.35, vignette = 0.05, chromaticAberration = 0.02, filmGrain = 0.0, sharpness = 0.45, temperature = 0.06, tint = 0.0, shader = "Anime", fov = 92, graphicsVibrance = 2.2, trailThickness = 1.2 },
	["Warm Sunset"] = { exposure = 0.75, gamma = 0.9, contrast = 1.4, saturation = 1.55, bloom = 1.1, vignette = 0.2, chromaticAberration = 0.02, filmGrain = 0.08, sharpness = 0.2, temperature = 0.55, tint = -0.06, shader = "Warm", fov = 86, graphicsVibrance = 1.55, trailThickness = 1.0 },
	["Cool Arena"] = { exposure = 0.65, gamma = 0.95, contrast = 1.25, saturation = 1.25, bloom = 0.8, vignette = 0.12, chromaticAberration = 0.02, filmGrain = 0.0, sharpness = 0.3, temperature = -0.38, tint = 0.04, shader = "Cool", fov = 96, graphicsVibrance = 1.3, trailThickness = 1.05 },
	["Noir"] = { exposure = 0.2, gamma = 0.78, contrast = 2.05, saturation = 0.0, bloom = 0.35, vignette = 0.52, chromaticAberration = 0.0, filmGrain = 0.35, sharpness = 0.28, temperature = 0.0, tint = 0.0, shader = "Noir", fov = 82, graphicsVibrance = 0.25, trailThickness = 0.8 },
}

local TEAM_NO_TEAM = -1

local function saveSafe()
	local ok = pcall(function()
		saveConfig()
	end)

	if not ok then
		print("[Streamer Cam] saveConfig failed")
	end
end

local function clamp01(value)
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

local function safeDistance(a, b)
	if a == nil or b == nil then
		return math.huge
	end

	local ok, dist = pcall(function()
		return Vec3.distance(a, b)
	end)

	if ok and dist ~= nil then
		return dist
	end

	return math.huge
end

local function safeNormalize(vec, fallback)
	if vec == nil then
		return fallback
	end

	local ok, result = pcall(function()
		if vec == Vec3.zeroVector then
			return fallback
		end
		return vec:normalize()
	end)

	if ok and result ~= nil and result ~= Vec3.zeroVector then
		return result
	end

	return fallback
end

local function vec3ToConfigTable(vec)
	if vec == nil then
		return nil
	end

	return {
		x = vec.x,
		y = vec.y,
		z = vec.z,
	}
end

local function configTableToVec3(t)
	if t == nil or t.x == nil or t.y == nil or t.z == nil then
		return nil
	end

	return Vec3.new(t.x, t.y, t.z)
end

local function quatToEulerConfigTable(quat)
	if quat == nil then
		return nil
	end

	local ok, euler = pcall(function()
		return quat:euler()
	end)

	if not ok or euler == nil then
		return nil
	end

	return vec3ToConfigTable(euler)
end

local function configTableToQuat(t)
	local euler = configTableToVec3(t)
	if euler == nil then
		return nil
	end

	return Quat.fromEuler(euler.x, euler.y, euler.z)
end

local function getData()
	local ok, data = pcall(function()
		return getGameData()
	end)

	if ok and data ~= nil then
		return data
	end

	return nil
end

local function tableToArray(t)
	local result = {}

	if t == nil or type(t) ~= "table" then
		return result
	end

	for _, value in pairs(t) do
		table.insert(result, value)
	end

	return result
end

local function getPlayers()
	local data = getData()

	if data == nil or data.players == nil then
		return {}
	end

	return tableToArray(data.players)
end

local function getBalls()
	local data = getData()

	if data == nil or data.balls == nil then
		return {}
	end

	return tableToArray(data.balls)
end

local function getPlayerName(player)
	if player == nil then
		return "Unknown"
	end

	return player.playerName or player.name or player.username or tostring(player.playerId or player.id or "Unknown")
end

local function getPlayerId(player)
	if player == nil then
		return nil
	end

	return player.playerId or player.id
end

local function findTargetPlayer()
	local players = getPlayers()

	-- Prefer ID because names can collide/change.
	if config.selectedTargetId ~= nil then
		for i = 1, #players do
			if getPlayerId(players[i]) == config.selectedTargetId then
				return players[i]
			end
		end
	end

	-- Fall back to saved name if IDs changed between sessions.
	if config.selectedTargetName ~= nil and config.selectedTargetName ~= "" then
		for i = 1, #players do
			if getPlayerName(players[i]) == config.selectedTargetName then
				config.selectedTargetId = getPlayerId(players[i])
				return players[i]
			end
		end
	end

	return nil
end

local function hasSavedTargetSelection()
	return (config.selectedTargetId ~= nil) or (config.selectedTargetName ~= nil and config.selectedTargetName ~= "")
end

local function isArenaPlayer(player)
	if player == nil or player.teamIndex == nil then
		return false
	end

	return player.teamIndex ~= TEAM_NO_TEAM
end

local function getArenaPlayers()
	local arenaPlayers = {}
	local players = getPlayers()

	for i = 1, #players do
		if isArenaPlayer(players[i]) then
			table.insert(arenaPlayers, players[i])
		end
	end

	return arenaPlayers
end

local function findAutoCasterPlayer(selectedTarget)
	-- The inside mode is only for the SELECTED target: while your chosen target is outside an
	-- arena the camera stays on them in the outside mode, whoever else is playing.
	if isArenaPlayer(selectedTarget) then
		return selectedTarget
	end

	return nil
end

local function isLikelyArenaBall(ball)
	-- Match balls are white/white (the rule Caster Camera's Util.isArenaBall uses).
	-- Heart balls / toy balls are not, so the ball cams and graphics leave those alone.
	if ball == nil or ball.color1 == nil or ball.color2 == nil then
		return true
	end

	local ok, result = pcall(function()
		local white = Color.new(255, 255, 255, 255)
		return ball.color1 == white and ball.color2 == white
	end)

	if ok then
		return result
	end

	return true
end

local function isLikelyHeartBall(ball)
	if ball == nil or ball.color1 == nil or ball.color2 == nil then
		return false
	end

	return not isLikelyArenaBall(ball)
end

local function getClosestBallTo(position, maxDistance, includeNonArenaBalls)
	local balls = getBalls()
	local closestBall = nil
	local closestDistance = maxDistance or math.huge

	for i = 1, #balls do
		local ball = balls[i]
		if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil then
			if includeNonArenaBalls or isLikelyArenaBall(ball) then
				local ballPos = ball.transform.position
				local insideArenaLock = true
				if config.autoCastLockToSelectedArena and arenaLockCenter ~= nil and not includeNonArenaBalls then
					insideArenaLock = safeDistance(ballPos, arenaLockCenter) <= (config.autoCastArenaLockRadius or 1800)
				end
				local distance = safeDistance(position, ballPos)
				if insideArenaLock and distance < closestDistance then
					closestDistance = distance
					closestBall = ball
				end
			end
		end
	end

	return closestBall
end

local function getBestAutoCastBall(anchorPosition)
	-- Prefer a ball near the anchor (the followed player), if one is given.
	local ball = nil
	if anchorPosition ~= nil then
		ball = getClosestBallTo(anchorPosition, config.autoCastBallSearchRadius)
	end

	if ball ~= nil then
		return ball
	end

	-- Fallback: closest likely arena ball to the current camera, no selected-target leash.
	return getClosestBallTo(camera.position, nil)
end

local function getBallVelocity(ball)
	if ball ~= nil and ball.velocity ~= nil then
		return ball.velocity
	end

	return Vec3.zeroVector
end

local function horizontalize(vec, upDir, fallback)
	if vec == nil then
		return fallback
	end

	local flat = vec - (upDir * vec:dot(upDir))
	return safeNormalize(flat, fallback)
end

local function limitCameraStep(fromPosition, targetPosition, maxStep)
	if fromPosition == nil or targetPosition == nil or maxStep == nil or maxStep <= 0 then
		return targetPosition
	end

	local delta = targetPosition - fromPosition
	local dist = delta:length()
	if dist > maxStep then
		return fromPosition + safeNormalize(delta, Vec3.forwardVector) * maxStep
	end

	return targetPosition
end

local function getWorldHandPosition(player, leftHand)
	if player == nil or player.root == nil or player.root.position == nil or player.root.rotation == nil then
		return nil
	end

	local hand = if leftHand then player.leftHand else player.rightHand
	if hand == nil or hand.position == nil then
		return nil
	end

	local ok, result = pcall(function()
		return player.root.position + player.root.rotation:rotateVector(hand.position)
	end)
	if ok then
		return result
	end

	return nil
end

local function getWorldHandRotation(player, leftHand)
	if player == nil or player.root == nil or player.root.rotation == nil then
		return nil
	end

	local hand = if leftHand then player.leftHand else player.rightHand
	if hand == nil or hand.rotation == nil then
		return nil
	end

	local ok, result = pcall(function()
		return player.root.rotation * hand.rotation
	end)
	if ok then
		return result
	end

	return nil
end

local function getUpDir(player)
	if gravity ~= nil and gravity.upDirection ~= nil and gravity.upDirection ~= Vec3.zeroVector then
		return safeNormalize(gravity.upDirection, Vec3.upVector)
	end

	if player ~= nil and player.root ~= nil and player.root.rotation ~= nil then
		return safeNormalize(player.root.rotation:getUpVector(), Vec3.upVector)
	end

	return Vec3.upVector
end

local function getHeadPosition(player)
	if player == nil then
		return nil
	end

	if player.head ~= nil and player.head.position ~= nil then
		return player.head.position
	end

	if player.root ~= nil and player.root.position ~= nil then
		return player.root.position + (getUpDir(player) * 55)
	end

	return nil
end

local function getHeadRotation(player)
	if player == nil then
		return nil
	end

	if player.head ~= nil and player.head.rotation ~= nil then
		return player.head.rotation
	end

	if player.root ~= nil and player.root.rotation ~= nil then
		return player.root.rotation
	end

	return nil
end

local function getPlayerDirs(player)
	local upDir = getUpDir(player)
	local headRot = getHeadRotation(player)
	local headForward = if headRot ~= nil then headRot:getForwardVector() else Vec3.forwardVector

	-- Project head forward onto the movement plane so looking straight up/down doesn't destroy follow math.
	local planarForward = headForward - (upDir * headForward:dot(upDir))
	planarForward = safeNormalize(planarForward, Vec3.forwardVector)

	local dirRight = safeNormalize(planarForward:cross(upDir), Vec3.rightVector)
	local dirForward = safeNormalize(upDir:cross(dirRight), planarForward)

	return upDir, dirRight, dirForward
end

local applyCameraVisualSettings

local function setCameraFov()
	if config.cameraFov ~= nil then
		camera.fieldOfView = config.cameraFov
	end
	if applyCameraVisualSettings ~= nil then
		applyCameraVisualSettings()
	end
end

local function setCameraField(name, value)
	pcall(function()
		camera[name] = value
	end)
end

local function setCameraPostField(name, value)
	-- The current dennssen.caster 2.6.4 script applies real visual settings through
	-- the global `postProcessSettings` object. Writing guessed fields onto `camera`
	-- does not visibly affect recent Orion builds.
	if not config.visualApplyEnginePostProcessing then
		return
	end

	pcall(function()
		if postProcessSettings ~= nil then
			postProcessSettings[name] = value
		end
	end)
end

local function applyCasterPostProcessing(bloom, vignette, chromaticAberration, motionBlur, exposureBias)
	if not config.visualApplyEnginePostProcessing then
		return
	end

	pcall(function()
		if postProcessSettings ~= nil then
			postProcessSettings.bloomIntensity = bloom
			postProcessSettings.bloomThreshold = -1
			postProcessSettings.depthOfFieldFstop = 4
			postProcessSettings.depthOfFieldFocalDistance = 0
			postProcessSettings.depthOfFieldSensorWidth = 24.576
			postProcessSettings.chromaticAberrationIntensity = chromaticAberration
			postProcessSettings.motionBlurAmount = motionBlur
			postProcessSettings.vignetteIntensity = vignette
			postProcessSettings.autoExposureBias = exposureBias
			visualStatus = "applied"
		end
	end)
end

local function filterValue(preset, key, customValue, neutralValue)
	local strength = clamp01(config.visualShaderStrength or 1)
	if preset == nil or preset[key] == nil then
		return customValue
	end
	return neutralValue + ((preset[key] - neutralValue) * strength)
end

local function applyVisibleLensPreset(preset)
	if preset == nil then
		visualEffectiveFov = nil
		return
	end

	local strength = clamp01(config.visualShaderStrength or 1)
	if config.visualUsePresetFov and preset.fov ~= nil then
		local baseFov = config.cameraFov or camera.fieldOfView or 90
		local effectiveFov = baseFov + ((preset.fov - baseFov) * strength)
		visualEffectiveFov = effectiveFov
		setCameraField("fieldOfView", effectiveFov)
	else
		visualEffectiveFov = nil
	end

	if config.visualUsePresetGraphics then
		if preset.graphicsVibrance ~= nil then
			config.graphicsVibrance = 1 + ((preset.graphicsVibrance - 1) * strength)
		end
		if preset.trailThickness ~= nil then
			config.graphicsTrailThickness = math.max(0.5, 4 * (1 + ((preset.trailThickness - 1) * strength)))
		end
	end
end

local function applyShaderName(shaderName)
	if shaderName == nil or shaderName == "" then
		return
	end
	setCameraPostField("shader", shaderName)
	setCameraPostField("shaderPreset", shaderName)
	setCameraPostField("filter", shaderName)
	setCameraPostField("filterPreset", shaderName)
	setCameraPostField("colorGradingPreset", shaderName)
	setCameraPostField("look", shaderName)
	setCameraPostField("lut", shaderName)
	setCameraPostField("lutName", shaderName)
end

applyCameraVisualSettings = function()
	if not config.visualSettingsEnabled then
		return
	end

	local preset = VISUAL_FILTER_PRESETS[config.visualFilterPreset or "Custom"]
	local exposure = filterValue(preset, "exposure", config.visualExposure, 0)
	local gamma = filterValue(preset, "gamma", config.visualGamma, 1)
	local contrast = filterValue(preset, "contrast", config.visualContrast, 1)
	local saturation = filterValue(preset, "saturation", config.visualSaturation, 1)
	local bloom = filterValue(preset, "bloom", config.visualBloom, 0)
	local vignette = filterValue(preset, "vignette", config.visualVignette, 0)
	local chromaticAberration = filterValue(preset, "chromaticAberration", config.visualChromaticAberration, 0)
	local motionBlur = filterValue(preset, "motionBlur", config.visualMotionBlur, 0)
	local filmGrain = filterValue(preset, "filmGrain", config.visualFilmGrain, 0)
	local sharpness = filterValue(preset, "sharpness", config.visualSharpness, 0)
	local temperature = filterValue(preset, "temperature", config.visualTemperature, 0)
	local tint = filterValue(preset, "tint", config.visualTint, 0)

	-- The parts of a preset that are sure to show are the camera FOV and the graphics styling.
	-- The post-process fields are sent below as well; the game may ignore some of them.
	applyVisibleLensPreset(preset)
	applyShaderName(if preset ~= nil then preset.shader else nil)
	-- This is the important Caster 2.6.4 mechanism: global postProcessSettings.
	applyCasterPostProcessing(bloom, vignette, chromaticAberration, motionBlur, exposure)
	setCameraPostField("exposure", exposure)
	setCameraPostField("postExposure", exposure)
	setCameraPostField("exposureCompensation", exposure)
	setCameraPostField("exposureBias", exposure)
	setCameraPostField("autoExposureBias", exposure)
	setCameraPostField("brightness", exposure)
	setCameraPostField("gamma", gamma)
	setCameraPostField("contrast", contrast)
	setCameraPostField("colorContrast", contrast)
	setCameraPostField("saturation", saturation)
	setCameraPostField("colorSaturation", saturation)
	setCameraPostField("bloom", bloom)
	setCameraPostField("bloomIntensity", bloom)
	setCameraPostField("vignette", vignette)
	setCameraPostField("vignetteIntensity", vignette)
	setCameraPostField("chromaticAberration", chromaticAberration)
	setCameraPostField("chromaticAberrationIntensity", chromaticAberration)
	setCameraPostField("filmGrain", filmGrain)
	setCameraPostField("filmGrainIntensity", filmGrain)
	setCameraPostField("grain", filmGrain)
	setCameraPostField("sharpness", sharpness)
	setCameraPostField("sharpen", sharpness)
	setCameraPostField("temperature", temperature)
	setCameraPostField("whiteBalanceTemperature", temperature)
	setCameraPostField("tint", tint)
	setCameraPostField("whiteBalanceTint", tint)
end

local function lerpCameraPosition(targetPosition, speed, dt)
	local alpha = clamp01(speed * dt)

	if safeDistance(camera.position, targetPosition) > config.snapDistance then
		camera.position = targetPosition
	else
		camera.position = Vec3.lerp(camera.position, targetPosition, alpha)
	end
end

-- =========================
-- Third Person - Head Movement
-- =========================

local function followThirdPersonHeadMovement(player, dt)
	local headPos = getHeadPosition(player)
	local headRot = getHeadRotation(player)

	if headPos == nil or headRot == nil then
		statusText = "Target missing head/root data."
		return false
	end

	local upDir = getUpDir(player)
	local forward = safeNormalize(headRot:getForwardVector(), Vec3.forwardVector)

	local targetPosition =
		headPos
		+ (forward * -config.thirdPersonDistance)
		+ (upDir * config.thirdPersonHeight)

	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	setCameraFov()

	lerpCameraPosition(targetPosition, config.followSpeed, dt)
	camera:lookAt(headPos, upDir)

	return true
end

-- =========================
-- First Person POV
-- =========================

local function followFirstPersonPOV(player, dt)
	local headPos = getHeadPosition(player)
	local headRot = getHeadRotation(player)

	if headPos == nil or headRot == nil then
		statusText = "Target missing head/root data."
		return false
	end

	local upDir = getUpDir(player)
	local forward = safeNormalize(headRot:getForwardVector(), Vec3.forwardVector)

	local targetPosition =
		headPos
		+ (forward * config.firstPersonForwardOffset)
		+ (upDir * config.firstPersonHeightOffset)

	camera.positionSmoothing = 0.01
	camera.rotationSmoothing = 0.01
	setCameraFov()

	local alpha = clamp01(config.firstPersonSpeed * dt)
	lerpCameraPosition(targetPosition, config.firstPersonSpeed, dt)
	camera.rotation = Quat.slerp(camera.rotation, headRot, alpha)

	return true
end

-- =========================
-- SpecPet: the Duckling
-- =========================

local function groundProject(position, upDir, height)
	local ok, groundCast = pcall(function()
		return camera:castRay(position + (upDir * 80), position + ((upDir * -1) * 500))
	end)

	if ok and groundCast ~= nil and groundCast.successful then
		return groundCast.position + (upDir * height)
	end

	return position
end

-- Duckling face ("optics") change, same calls as Layna's SpecPet: camera:setEmote(9) is the
-- happy / gleam face, camera:setEmote(11) the standard face. The happy face is held for a few
-- seconds after the last pat, as SpecPet does.
local function setDucklingFace(happy)
	local ok, err = pcall(function()
		camera:setEmote(if happy then 9 else 11)
	end)
	duckState.faceHappy = happy
	duckState.emoteOk = ok
	if not ok then duckState.emoteError = tostring(err) end
end

local function triggerDucklingHappyReaction(duration, reason)
	duckState.lastReason = reason or "manual test"
	duckState.ruffleTimer = math.min(duration or config.ducklingRuffleDuration, math.max(config.ducklingFeedingDuration or 1.2, config.ducklingRuffleDuration or 0.7))
	duckState.happyEmoteTimer = math.max(duckState.happyEmoteTimer or 0, config.ducklingHappyEmoteHoldSeconds or 3)
	duckState.reactionCount = (duckState.reactionCount or 0) + 1
	duckState.reactionClock = os.clock()
	setDucklingFace(true)
end

-- Counts the happy face down and puts the standard face back. Called every tick, including
-- ticks where the Duckling is not the running mode, so the face can never get stuck on happy.
local function setDucklingNeutralFaceIfReady(dt)
	duckState.happyEmoteTimer = math.max((duckState.happyEmoteTimer or 0) - dt, 0)
	if duckState.happyEmoteTimer > 0 then
		setDucklingFace(true) -- re-assert, in case the first call landed during a transition
	elseif duckState.faceHappy ~= false then
		setDucklingFace(false)
	end
end

-- True when a real hand is within `radius` of `position`. Also returns whose hand and how far,
-- so it is known exactly what set a reaction off.
-- A hand that is not tracked reports (0,0,0) relative to the body, which would place it at the
-- player's root: that is just a person standing nearby, not a hand, so it is ignored.
-- `owner`: when "only the owner can interact" is on, pass the followed player and nobody else's
-- hands are considered.
local function getAnyHandNear(position, radius, owner)
	local players = getPlayers()
	local ownerOnly = owner ~= nil and config.ducklingInteractEveryone == false
	local ownerId = if ownerOnly then getPlayerId(owner) else nil
	for i = 1, #players do
		local player = players[i]
		local allowed = not ownerOnly or (ownerId ~= nil and getPlayerId(player) == ownerId)
		for side = 1, (if allowed then 2 else 0) do
			local hand = if side == 1 then player.leftHand else player.rightHand
			local world = getWorldHandPosition(player, side == 1)
			if world ~= nil and hand ~= nil and hand.position ~= nil then
				local okLength, reach = pcall(function() return hand.position:length() end)
				local distance = safeDistance(position, world)
				if okLength and reach > 8 and distance < radius then
					return true, getPlayerName(player) .. "'s " .. (if side == 1 then "left" else "right") .. " hand, " .. tostring(math.floor(distance)) .. " units away"
				end
			end
		end
	end
	return false, nil
end

local function senseDucklingHeadpats(dt, owner)
	if not config.ducklingHeadpatsEnabled then
		duckState.headpatTouching = false
		duckState.headpatReleaseTimer = 0
		return
	end

	duckState.headpatReleaseTimer = math.max((duckState.headpatReleaseTimer or 0) - dt, 0)
	-- A pat is a hand actually ON the duckling (SpecPet uses 30 units from the camera). Standing
	-- next to it is not a pat. While a hand is already on it the radius is a little bigger so a
	-- stroking hand does not count as leaving on every stroke.
	local radius = math.clamp(config.ducklingHeadpatRadius or 30, 10, 60)
	if duckState.headpatTouching then radius = radius * 1.4 end
	local touching, who = getAnyHandNear(camera.position, radius, owner)
	if touching then
		duckState.headpatReleaseTimer = config.ducklingHeadpatReleaseGrace or 0.25
	end

	local stableTouching = touching or (duckState.headpatReleaseTimer or 0) > 0
	if stableTouching then
		-- Petting can go on as long as you like: the happy face stays on for the whole pet and
		-- the wiggle starts again each time the previous one finishes.
		if not duckState.headpatTouching or (duckState.ruffleTimer or 0) <= 0 then
			triggerDucklingHappyReaction(config.ducklingRuffleDuration, "headpat: " .. (who or "hand still on it"))
			duckState.faceHoldTimer = config.ducklingFacePetHoldSeconds or 1.25
		else
			duckState.happyEmoteTimer = math.max(duckState.happyEmoteTimer or 0, config.ducklingHappyEmoteHoldSeconds or 3)
		end
	end

	duckState.headpatTouching = stableTouching
end

local function senseDucklingTreats(dt, owner)
	if not config.ducklingTreatsEnabled then
		return
	end

	duckState.treatCooldown = math.max((duckState.treatCooldown or 0) - dt, 0)
	duckState.feedCooldown = math.max((duckState.feedCooldown or 0) - dt, 0)
	if duckState.treatCooldown > 0 then
		return
	end

	-- A treat only counts when the ball is right at the duckling AND a hand is holding it there.
	local ballRadius = math.clamp(config.ducklingTreatRadius or 35, 10, 45)
	local handRadius = math.clamp(config.ducklingFeedingHandRadius or 40, 10, 45)
	local balls = getBalls()
	for i = 1, #balls do
		local ball = balls[i]
		if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil and isLikelyHeartBall(ball) then
			local ballPos = ball.transform.position
			local ballDistance = safeDistance(camera.position, ballPos)
			if ballDistance <= ballRadius then
				local held, who = getAnyHandNear(ballPos, handRadius, owner)
				if held or not config.ducklingTreatRequireHandNear then
					local reason = "treat: ball " .. tostring(math.floor(ballDistance)) .. " units away" .. (if who ~= nil then ", held by " .. who else ", no hand")
					if held and config.ducklingFeedingEnabled then
						triggerDucklingHappyReaction(config.ducklingFeedingDuration or 1.2, reason)
						duckState.feedTimer = config.ducklingFeedingDuration or 1.2
						duckState.faceHoldTimer = config.ducklingFacePetHoldSeconds or 1.25
						statusText = "Duckling fed a treat."
					else
						triggerDucklingHappyReaction((config.ducklingRuffleDuration or 0.7) * 1.15, reason)
					end
					duckState.treatCooldown = math.max(config.ducklingTreatCooldown or 1, 0.5)
					duckState.feedCooldown = duckState.treatCooldown
					return
				end
			end
		end
	end
end

-- The Duckling: waddles along behind the player on the ground, keeps a little personal space,
-- and holds still in front of them after a pat or a treat so it stays pettable.
local function followDuckling(player, dt)
	if player == nil or player.root == nil or player.root.position == nil then
		statusText = "Target missing root data."
		return false
	end

	local upDir, dirRight, dirForward = getPlayerDirs(player)

	local playerPos = player.root.position
	local duckHeight = config.ducklingHeight or 10
	local personalSpace = config.ducklingPersonalSpace or 70
	-- restDistance: where it settles after catching up. leashDistance: how far you can get before it moves.
	local restDistance = math.max(config.ducklingDistance or 125, personalSpace)
	local leashDistance = math.max(config.ducklingFollowLeashDistance or 165, restDistance + 25)

	duckState.faceHoldTimer = math.max((duckState.faceHoldTimer or 0) - dt, 0)
	local playerSpeed = if player.velocity ~= nil then player.velocity:length() else 0
	local beingPetted = duckState.headpatTouching == true or (duckState.feedTimer or 0) > 0
		or (duckState.faceHoldTimer > 0 and playerSpeed <= (config.ducklingFacePlayerSpeed or 70))

	-- Where the duckling is relative to the player, split into floor-plane and vertical parts
	-- (the root can sit well above the floor, so 3D distance alone would never settle).
	local offset = camera.position - playerPos
	local verticalOffset = offset:dot(upDir)
	local flatOffset = offset - (upDir * verticalOffset)
	local flatDistance = flatOffset:length()
	local awayDir = safeNormalize(flatOffset, dirForward * -1)
	local playerFacingDuck = dirForward:dot(awayDir) >= 0.35

	-- Calm zone: inside the leash the duckling does not move at all, it only looks at you, so you
	-- can turn around and pet it. Past the leash it waddles straight toward you and stops at
	-- restDistance ON ITS OWN SIDE. While you travel that naturally puts it behind you, but it
	-- never circles around to get exactly behind your head.
	if flatDistance > leashDistance or math.abs(verticalOffset) > leashDistance then
		duckState.leashActive = true
	end
	local targetPosition = groundProject(playerPos + (awayDir * restDistance) + (upDir * duckHeight), upDir, duckHeight)
	local distanceToTarget = safeDistance(camera.position, targetPosition)
	if duckState.leashActive and flatDistance <= restDistance + 10 and (math.abs(verticalOffset) <= leashDistance or distanceToTarget <= 12) then
		duckState.leashActive = false
	end

	-- Personal space: back off if the player walks into it, but let them lean in close when they
	-- are facing it or petting/feeding it.
	local currentDistance = safeDistance(camera.position, playerPos)
	local closeLimit = if playerFacingDuck or beingPetted then personalSpace * 0.4 else personalSpace
	local tooClose = currentDistance < closeLimit
	if tooClose then
		local awayFromPlayer = offset
		if currentDistance < 1 then
			awayFromPlayer = dirForward * -1
			currentDistance = 1
		end
		local pushedPosition = playerPos + (awayFromPlayer * (closeLimit / currentDistance))
		targetPosition = groundProject(pushedPosition + (upDir * duckHeight), upDir, duckHeight)
	end

	duckState.lastTargetPosition = playerPos

	local shouldFollow = tooClose or duckState.leashActive == true

	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	setCameraFov()

	if shouldFollow then
		lerpCameraPosition(targetPosition, config.ducklingSpeed or 10, dt)
	end

	senseDucklingHeadpats(dt, player)
	senseDucklingTreats(dt, player)

	-- Ruffle/wiggle after headpats or a nearby heart-ball treat.
	local tiltAmount = 0
	duckState.feedTimer = math.max((duckState.feedTimer or 0) - dt, 0)
	if duckState.feedTimer > 0 then
		local feedProgress = duckState.feedTimer / math.max(config.ducklingFeedingDuration or 1.2, 0.1)
		tiltAmount = math.sin(duckState.feedTimer * (config.ducklingRuffleSpeed or 45) * 1.25) * (config.ducklingRuffleMaxTilt or 0.22) * 1.2 * feedProgress
	elseif duckState.ruffleTimer ~= nil and duckState.ruffleTimer > 0 then
		duckState.ruffleTimer = math.max(duckState.ruffleTimer - dt, 0)
		local ruffleProgress = duckState.ruffleTimer / math.max(config.ducklingRuffleDuration or 0.7, 0.1)
		tiltAmount = math.sin(duckState.ruffleTimer * config.ducklingRuffleSpeed) * config.ducklingRuffleMaxTilt * ruffleProgress
	end
	duckState.ranThisTick = true

	local tiltedUp = upDir + (dirRight * tiltAmount)

	-- Aim low, like the duckling pet.
	camera:lookAt(player.root.position + (upDir * 5), tiltedUp)

	return true
end

-- The SpecPet mode: whichever pet is picked follows the player. "Duckling" is the pet above;
-- "Kitty" and "Pidgeon" are Layna's two original Spectator Pets (specpets.luau).
local function followSpecPet(player, dt)
	if config.specPetType == "Kitty" or config.specPetType == "Pidgeon" then
		return SpecPets.tick(config.specPetType, player, dt, config)
	end
	return followDuckling(player, dt)
end

-- =========================
-- Inside Arena Autocaster Modes
-- =========================

local function followThirdPersonBallLook(player, dt)
	local headPos = getHeadPosition(player)
	local headRot = getHeadRotation(player)

	if headPos == nil or headRot == nil then
		statusText = "Arena target missing head/root data."
		return false
	end

	local upDir = getUpDir(player)
	local forward = safeNormalize(headRot:getForwardVector(), Vec3.forwardVector)
	local ball = getClosestBallTo(headPos)
	goalRuntime.ball, goalRuntime.ballKnown = ball, true
	local lookTarget = headPos

	if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil then
		lookTarget = ball.transform.position
	end

	local targetPosition =
		headPos
		+ (forward * -config.ballLookDistance)
		+ (upDir * config.ballLookHeight)

	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	setCameraFov()

	lerpCameraPosition(targetPosition, config.ballLookSpeed, dt)
	camera:lookAt(lookTarget, upDir)

	return true
end

local function getSimpleBallCamBall()
	if arenaPin.ball ~= nil then return arenaPin.ball end -- the ball of the arena being cast
	-- Locked on an arena that has no ball right now (a goal, a break): there is nothing to follow.
	-- Taking the nearest ball here is what used to throw the camera into another arena.
	if arenaPin.started then return nil end
	local balls = getBalls()
	local closestBall = nil
	local closestDistance = math.huge
	for i = 1, #balls do
		local ball = balls[i]
		if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil and isLikelyArenaBall(ball) then
			local distance = safeDistance(camera.position, ball.transform.position)
			if distance < closestDistance then
				closestDistance = distance
				closestBall = ball
			end
		end
	end
	return closestBall
end

-- Keeps a ball-cam position inside the arena the ball is in: never behind a goal line, outside a
-- side wall or above the ceiling (where the shot is just a wall). Recognised arenas only.
local function keepCameraInArena(position, ballPos)
	if config.ballCamStayInArena == false then return position end
	local ok, inside = pcall(ArenaMap.keepInside, position, ballPos, 90, 380, 70)
	return if ok and inside ~= nil then inside else position
end

local function followSimpleBallCam(dt)
	local ball = getSimpleBallCamBall()
	if ball == nil or ball.transform == nil or ball.transform.position == nil then
		statusText = "Simple Ball Cam: no arena ball found."
		return false
	end
	simpleBallCamCurrentBall = ball

	local upDir = getUpDir(nil)
	local ballPos = ball.transform.position
	local ballVel = getBallVelocity(ball)
	local rawFocusPoint = ballPos + (ballVel * (config.simpleBallCamLead or 0.22))

	-- Smooth the focus point itself. This is the important anti-shake knob:
	-- lower = more cinematic/smooth, higher = more responsive.
	local focusAlpha = clamp01((config.simpleBallCamFocusSmoothSpeed or 5) * dt)
	if simpleBallSmoothFocus == nil then
		simpleBallSmoothFocus = rawFocusPoint
	else
		simpleBallSmoothFocus = Vec3.lerp(simpleBallSmoothFocus, rawFocusPoint, focusAlpha)
	end
	local focusPoint = simpleBallSmoothFocus

	local motionDir = horizontalize(ballVel, upDir, nil)
	if motionDir == nil then
		motionDir = horizontalize(ballPos - camera.position, upDir, nil)
	end
	motionDir = safeNormalize(motionDir, Vec3.forwardVector)

	local rawBackDir = motionDir * -1
	local dirAlpha = clamp01((config.simpleBallCamDirectionSmoothSpeed or 4) * dt)
	if simpleBallSmoothBackDir == nil then
		simpleBallSmoothBackDir = rawBackDir
	else
		simpleBallSmoothBackDir = safeNormalize(Vec3.lerp(simpleBallSmoothBackDir, rawBackDir, dirAlpha), rawBackDir)
	end
	local backDir = simpleBallSmoothBackDir

	local targetPosition = focusPoint + (backDir * (config.simpleBallCamDistance or 620)) + (upDir * (config.simpleBallCamHeight or 260))
	targetPosition = keepCameraInArena(targetPosition, ballPos) -- e.g. a rebound off the goal must not park the camera behind it

	-- Catch-up ramp: when the cam falls behind a clear/shot, temporarily let it move faster
	-- instead of staying pretty-but-late.
	local cameraLag = safeDistance(camera.position, targetPosition)
	local catchupStart = config.simpleBallCamCatchupStartDistance or 300
	local catchupExcess = math.max(0, cameraLag - catchupStart)
	local catchupFactor = clamp01(catchupExcess / 900)
	local dynamicMaxStepPerSecond = math.min(
		(config.simpleBallCamMaxStepPerSecond or 4200) + (catchupExcess * (config.simpleBallCamCatchupMultiplier or 10)),
		config.simpleBallCamMaxCatchupStepPerSecond or 12000
	)
	targetPosition = limitCameraStep(camera.position, targetPosition, dynamicMaxStepPerSecond * dt)

	camera.positionSmoothing = 0.01
	camera.rotationSmoothing = 0.01
	camera.fieldOfView = config.simpleBallCamFov or 96
	local dynamicFollowSpeed = (config.simpleBallCamFollowSpeed or 16) + (catchupFactor * (config.simpleBallCamCatchupSmoothBoost or 28))
	lerpCameraPosition(targetPosition, dynamicFollowSpeed, dt)
	camera:lookAt(focusPoint, upDir)

	return true
end

-- =========================
-- Autocast - Ball Carrier
-- Player cam on whoever has the ball; Simple Ball Cam while the ball is loose (pass, shot, rebound).
-- "Has the ball" is Caster's rule: the nearest head or hand is within contact distance of the ball.
-- Short touches do not cut to a player, and a brief loss of contact does not cut away from one.
-- =========================
local carrierCam = { mode = "ball", carrierId = nil, candidateId = nil, candidateTime = 0, looseTime = 0, modeTime = 0, smoothBack = nil, label = "" }

local function findBallHolder(ball)
	local ballPos = ball.transform.position
	local best, bestDistance = nil, config.carrierContactDistance or 45
	local players = getArenaPlayers()
	for i = 1, #players do
		local player = players[i]
		local nearest = math.huge
		local head = getHeadPosition(player)
		if head ~= nil then nearest = math.min(nearest, safeDistance(ballPos, head)) end
		local left, right = getWorldHandPosition(player, true), getWorldHandPosition(player, false)
		if left ~= nil then nearest = math.min(nearest, safeDistance(ballPos, left)) end
		if right ~= nil then nearest = math.min(nearest, safeDistance(ballPos, right)) end
		if nearest < bestDistance then best, bestDistance = player, nearest end
	end
	return best
end

local function resetCarrierCam()
	carrierCam.mode, carrierCam.carrierId, carrierCam.candidateId = "ball", nil, nil
	carrierCam.candidateTime, carrierCam.looseTime, carrierCam.modeTime, carrierCam.smoothBack = 0, 0, 0, nil
end

local function followBallCarrierCam(dt)
	local ball = getSimpleBallCamBall()
	if ball == nil or ball.transform == nil or ball.transform.position == nil then
		resetCarrierCam()
		statusText = "Ball Carrier: no arena ball found."
		return false
	end
	local ballPos = ball.transform.position
	local holder = findBallHolder(ball)
	local holderId = if holder ~= nil then getPlayerId(holder) else nil
	carrierCam.modeTime += dt
	if holderId ~= nil then
		carrierCam.looseTime = 0
		if holderId == carrierCam.candidateId then
			carrierCam.candidateTime += dt
		else
			carrierCam.candidateId, carrierCam.candidateTime = holderId, 0
		end
	else
		carrierCam.looseTime += dt
		carrierCam.candidateId, carrierCam.candidateTime = nil, 0
	end

	local held = holderId ~= nil and carrierCam.candidateTime >= (config.carrierHoldSeconds or 0.35)
	if carrierCam.mode == "ball" then
		if held and carrierCam.modeTime >= 0.6 then
			carrierCam.mode, carrierCam.carrierId, carrierCam.modeTime, carrierCam.smoothBack = "carrier", holderId, 0, nil
		end
	elseif held and holderId ~= carrierCam.carrierId then
		carrierCam.carrierId, carrierCam.modeTime = holderId, 0 -- steal / hand-off: follow the new carrier
	elseif holderId == nil and carrierCam.looseTime >= (config.carrierLooseSeconds or 0.35) then
		carrierCam.mode, carrierCam.carrierId, carrierCam.modeTime = "ball", nil, 0
	end

	local carrier = nil
	if carrierCam.mode == "carrier" then
		if holder ~= nil and holderId == carrierCam.carrierId then
			carrier = holder
		else
			local players = getPlayers()
			for i = 1, #players do
				if getPlayerId(players[i]) == carrierCam.carrierId then carrier = players[i] end
			end
		end
		if carrier == nil or getHeadPosition(carrier) == nil or getHeadRotation(carrier) == nil then
			carrierCam.mode, carrierCam.carrierId, carrierCam.modeTime, carrier = "ball", nil, 0, nil
		end
	end

	if carrier == nil then
		carrierCam.label = "loose ball"
		return followSimpleBallCam(dt)
	end

	-- Player cam: behind and above the carrier, turning smoothly with where they face, looking at
	-- a point between their head and the ball.
	local headPos = getHeadPosition(carrier)
	local upDir = getUpDir(carrier)
	local facing = horizontalize(getHeadRotation(carrier):getForwardVector(), upDir, nil)
	local rawBack = if facing ~= nil then facing * -1 else (carrierCam.smoothBack or Vec3.forwardVector)
	if carrierCam.smoothBack == nil then
		carrierCam.smoothBack = rawBack
	else
		carrierCam.smoothBack = safeNormalize(Vec3.lerp(carrierCam.smoothBack, rawBack, clamp01(5 * dt)), rawBack)
	end
	local targetPosition = headPos + (carrierCam.smoothBack * (config.carrierCamDistance or 230)) + (upDir * (config.carrierCamHeight or 75))
	targetPosition = keepCameraInArena(targetPosition, ballPos)
	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	camera.fieldOfView = config.simpleBallCamFov or 96 -- same lens as the ball cam, so cuts do not pop
	lerpCameraPosition(targetPosition, 12, dt)
	camera:lookAt(headPos + ((ballPos - headPos) * 0.5), upDir)
	-- the ball cam starts fresh when the ball is released
	simpleBallSmoothFocus, simpleBallSmoothBackDir = nil, nil
	simpleBallCamCurrentBall = ball
	carrierCam.label = getPlayerName(carrier) .. " has the ball"
	return true
end

local function refreshFollowPlusBridge()
	if followPlusCam ~= nil then
		return followPlusCam
	end

	if not config.vlogFollowPlusEnabled then
		return nil
	end

	local ok, cam = pcall(function()
		return getCameraById("dennssen.followpluss")
	end)

	if ok and cam ~= nil then
		followPlusCam = cam
		pcall(function()
			sendMessage(followPlusCam, {
				getMainProcessCallback = function(fn)
					followPlusTick = fn
				end,
				versionCallback = function(v)
					followPlusVersion = v or ""
				end,
			})
		end)
	end

	return followPlusCam
end

local function stopVlogBridge()
	if not vlogBridgeActive then
		return
	end

	vlogBridgeActive = false

	if followPlusCam ~= nil then
		pcall(function()
			camera.position = followPlusCam:getSmoothedPosition()
			camera.rotation = followPlusCam:getSmoothedRotation()
		end)
	end
end

local function followVlogNativeGrab(player, dt)
	if not config.vlogNativeGrabEnabled then
		vlogNativeGrabActive = false
		return false
	end

	local leftPos = getWorldHandPosition(player, true)
	local rightPos = getWorldHandPosition(player, false)
	if leftPos == nil and rightPos == nil then
		vlogNativeGrabActive = false
		return false
	end

	local leftDistance = safeDistance(camera.position, leftPos)
	local rightDistance = safeDistance(camera.position, rightPos)
	local grabRadius = config.vlogGrabRadius or 42
	local releaseRadius = config.vlogGrabReleaseRadius or 85

	if not vlogNativeGrabActive then
		if leftDistance <= grabRadius or rightDistance <= grabRadius then
			vlogNativeGrabActive = true
			vlogNativeGrabLeftHand = leftDistance <= rightDistance
		else
			return false
		end
	end

	local handPos = if vlogNativeGrabLeftHand then leftPos else rightPos
	local distance = if vlogNativeGrabLeftHand then leftDistance else rightDistance
	if handPos == nil or distance > releaseRadius then
		vlogNativeGrabActive = false
		return false
	end

	stopVlogBridge()
	camera.positionSmoothing = 0
	camera.rotationSmoothing = 0
	camera.hideNearestHead = false
	camera.fieldOfView = config.vlogFov or config.cameraFov
	if applyCameraVisualSettings ~= nil then
		applyCameraVisualSettings()
	end
	camera.position = handPos

	local upDir = getUpDir(player)
	local headPos = getHeadPosition(player)
	if config.vlogGrabLookAtTarget and headPos ~= nil and safeDistance(handPos, headPos) > 10 then
		camera:lookAt(headPos, upDir)
	else
		local handRot = getWorldHandRotation(player, vlogNativeGrabLeftHand)
		if handRot ~= nil then
			camera.rotation = handRot
		else
			local headRot = getHeadRotation(player)
			if headRot ~= nil then
				camera.rotation = headRot
			end
		end
	end

	statusText = "Vlog camera grabbed by " .. (if vlogNativeGrabLeftHand then "left" else "right") .. " hand."
	return true
end

local function followVlogCamera(player, dt)
	if followVlogNativeGrab(player, dt) then
		return true
	end

	local bridge = refreshFollowPlusBridge()
	if bridge == nil then
		vlogBridgeActive = false
		statusText = "Follow+ missing; using normal follow."
		return followThirdPersonHeadMovement(player, dt)
	end

	local targetId = getPlayerId(player)
	if targetId == nil then
		statusText = "Vlog mode target missing player ID."
		return followThirdPersonHeadMovement(player, dt)
	end

	setCameraFov()
	camera.fieldOfView = config.vlogFov or config.cameraFov
	if applyCameraVisualSettings ~= nil then
		applyCameraVisualSettings()
	end
	camera.hideNearestHead = false

	-- Bridge into FollowPlus instead of reimplementing its handheld/vlog logic.
	-- gestureControls=true is the important bit for the grab-out / vlog-cam feel.
	pcall(function()
		sendMessage(bridge, {
			readLocation = 0,
			showNameTags = true,
			muteSelf = false,
			isBallOutlineEnabled = true,
			targetPlayer = player,
			cameraFOV = config.vlogFov or config.cameraFov,
			cameraMode = 1,
			radius = config.vlogFollowRadius,
			threshold = 5,
			positionSmoothing = config.vlogFollowSmoothing,
			cameraPositionOffset = Vec3.zeroVector,
			cameraRotationOffset = Quat.identity,
			gestureControls = true,
			autoBall = false,
			autoGoalCam = false,
			showQuests = false,
			autoRecordReplays = false,
			mouseSensitivity = 1,
			controllerSensitivity = 1,
			controllerDeadzone = 0.1,
		})
	end)

	if followPlusTick ~= nil then
		pcall(function()
			followPlusTick(dt, camera)
		end)
	end

	local ok = pcall(function()
		camera:followCamera(bridge)
	end)

	if not ok then
		vlogBridgeActive = false
		statusText = "Follow+ bridge failed; using normal follow."
		return followThirdPersonHeadMovement(player, dt)
	end

	vlogBridgeActive = true
	return true
end

local function storeFixedCameraHere()
	config.fixedCamPosition = vec3ToConfigTable(camera.position)
	config.fixedCamRotation = quatToEulerConfigTable(camera.rotation)
	saveSafe()
	statusText = "Fixed camera position saved."
end

local function runFixedCamera(player)
	local fixedPosition = configTableToVec3(config.fixedCamPosition)
	local fixedRotation = configTableToQuat(config.fixedCamRotation)
	local headPos = getHeadPosition(player)
	local upDir = getUpDir(player)

	if fixedPosition == nil then
		storeFixedCameraHere()
		fixedPosition = configTableToVec3(config.fixedCamPosition)
	end

	if fixedPosition == nil then
		statusText = "No fixed camera position saved."
		return false
	end

	camera.positionSmoothing = 0
	camera.rotationSmoothing = 0
	setCameraFov()
	camera.position = fixedPosition

	if config.fixedCamLookAtBall then
		local ball = getClosestBallTo(fixedPosition)
		goalRuntime.ball, goalRuntime.ballKnown = ball, true
		if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil then
			camera:lookAt(ball.transform.position, upDir)
		elseif headPos ~= nil then
			camera:lookAt(headPos, upDir)
		elseif fixedRotation ~= nil then
			camera.rotation = fixedRotation
		end
	elseif fixedRotation ~= nil then
		camera.rotation = fixedRotation
	elseif headPos ~= nil then
		camera:lookAt(headPos, upDir)
	end

	return true
end

local function getGamepadAnalog(name)
	if Input.Gamepad == nil or Input.Gamepad[name] == nil then
		return 0
	end

	local ok, value = pcall(function()
		return Input.getAnalog(Input.Gamepad[name])
	end)

	if ok and typeof(value) == "number" then
		return value
	end

	return 0
end

local function getGamepadKeyHeld(name)
	if Input.Gamepad == nil or Input.Gamepad[name] == nil then
		return false
	end

	local ok, held = pcall(function()
		return Input.getKey(Input.Gamepad[name])
	end)

	return ok and held == true
end

local function applyFreeCamDeadzone(value)
	local deadzone = config.freeCamControllerDeadzone or 0.12
	local absValue = math.abs(value)
	if absValue < deadzone then
		return 0
	end

	local sign = if value < 0 then -1 else 1
	return ((absValue - deadzone) / math.max(1 - deadzone, 0.001)) * sign
end

local function getFreeCamGravityRotation()
	if gravity ~= nil and gravity.upRotation ~= nil then
		local strength = gravity.strength or 1
		if strength > 0 then
			freeCamPersistentGravityRotation = gravity.upRotation
		end
	end

	return freeCamPersistentGravityRotation or Quat.identity
end

local function initializeFreeCamRotationState()
	local okEuler, euler = pcall(function()
		return camera.rotation:euler()
	end)
	if okEuler and euler ~= nil then
		freeCamRotEuler = Vec3.new(0, euler.y, euler.z)
	else
		freeCamRotEuler = Vec3.zeroVector
	end
	freeCamGravityChaser = getFreeCamGravityRotation()
end

local function runFreeCam(dt)
	stopVlogBridge()

	if not freeCamInitialized then
		freeCamInitialized = true
		graphicsTrail = {}
		initializeFreeCamRotationState()
	end

	setCameraFov()
	camera.positionSmoothing = 0
	camera.rotationSmoothing = 0

	local mouse = Input.getMouseDelta()
	local lookSensitivity = config.freeCamLookSensitivity or 0.12
	local controllerLookX = applyFreeCamDeadzone(getGamepadAnalog("RightX"))
	local controllerLookY = applyFreeCamDeadzone(getGamepadAnalog("RightY"))
	if config.freeCamInvertControllerY then
		controllerLookY = -controllerLookY
	end

	if freeCamRotEuler == nil then
		initializeFreeCamRotationState()
	end

	freeCamRotEuler.z = freeCamRotEuler.z + mouse.x * lookSensitivity + controllerLookX * (config.freeCamControllerLookSpeed or 115) * dt
	freeCamRotEuler.y = freeCamRotEuler.y + mouse.y * lookSensitivity + controllerLookY * (config.freeCamControllerLookSpeed or 115) * dt
	freeCamRotEuler.y = math.clamp(freeCamRotEuler.y, -89.5, 89.5)

	if config.freeCamGravityAlignedLook then
		local targetGravityRot = getFreeCamGravityRotation()
		if freeCamGravityChaser == nil then
			freeCamGravityChaser = targetGravityRot
		else
			freeCamGravityChaser = Quat.slerp(freeCamGravityChaser, targetGravityRot, clamp01((config.freeCamGravityChaseSpeed or 5) * dt))
		end
		camera.rotation = freeCamGravityChaser * Quat.fromEuler(freeCamRotEuler.x, freeCamRotEuler.y, freeCamRotEuler.z)
	else
		camera.rotation = Quat.fromEuler(freeCamRotEuler.x, freeCamRotEuler.y, freeCamRotEuler.z)
	end

	local move = Vec3.zeroVector
	local upDir = getUpDir(nil)
	local rawCameraForward = camera.rotation:getForwardVector()
	local rawCameraRight = camera.rotation:getRightVector()
	local freeCamForward = rawCameraForward
	local freeCamRight = rawCameraRight
	local freeCamUp = camera.rotation:getUpVector()
	if config.freeCamGroundPlaneMovement then
		-- Match the normal caster/third-person feel: forward/back/strafe move along the arena floor,
		-- not upward/downward when the camera is pitched. Vertical movement stays on gravity up/down.
		freeCamForward = horizontalize(freeCamForward, upDir, Vec3.forwardVector)
		freeCamRight = horizontalize(freeCamRight, upDir, Vec3.rightVector)
		freeCamUp = upDir
	end

	local controllerForward = applyFreeCamDeadzone(getGamepadAnalog("LeftY"))
	if config.freeCamInvertControllerMoveY then
		controllerForward = -controllerForward
	end
	local controllerRight = applyFreeCamDeadzone(getGamepadAnalog("LeftX"))
	local controllerUp = applyFreeCamDeadzone(getGamepadAnalog("RightTriggerAxis")) - applyFreeCamDeadzone(getGamepadAnalog("LeftTriggerAxis"))
	local controllerForwardDir = if config.freeCamControllerForwardUsesCameraFacing then rawCameraForward else freeCamForward
	local controllerRightDir = if config.freeCamControllerForwardUsesCameraFacing then rawCameraRight else freeCamRight

	if controllerForward ~= 0 then
		move = move + controllerForwardDir * controllerForward * (config.freeCamControllerMoveMultiplier or 1)
	end
	if controllerRight ~= 0 then
		move = move + controllerRightDir * controllerRight * (config.freeCamControllerMoveMultiplier or 1)
	end
	if controllerUp ~= 0 then
		move = move + freeCamUp * controllerUp * (config.freeCamControllerMoveMultiplier or 1)
	end

	if Input.getKey(Input.Key.W) then
		move = move + freeCamForward
	end
	if Input.getKey(Input.Key.S) then
		move = move - freeCamForward
	end
	if Input.getKey(Input.Key.D) then
		move = move + freeCamRight
	end
	if Input.getKey(Input.Key.A) then
		move = move - freeCamRight
	end
	if Input.getKey(Input.Key.SpaceBar) then
		move = move + freeCamUp
	end
	if Input.getKey(Input.Key.LeftControl) or Input.getKey(Input.Key.RightControl) then
		move = move - freeCamUp
	end

	local speed = config.freeCamMoveSpeed or 650
	local controllerSprint = getGamepadKeyHeld("RightShoulder")
	local controllerSlow = getGamepadKeyHeld("LeftShoulder")
	if Input.getKey(Input.Key.LeftShift) or Input.getKey(Input.Key.RightShift) or controllerSprint then
		speed = speed * (config.freeCamSprintMultiplier or 3)
	end
	if Input.getKey(Input.Key.LeftAlt) or Input.getKey(Input.Key.RightAlt) or controllerSlow then
		speed = speed * (config.freeCamSlowMultiplier or 0.25)
	end

	if move ~= Vec3.zeroVector then
		local desiredPosition = camera.position + safeNormalize(move, Vec3.zeroVector) * speed * dt
		if config.freeCamCollisionSafety and not config.freeCamNoClip then
			local okHit, hit = pcall(function()
				return camera:castRay(camera.position, desiredPosition)
			end)
			if okHit and hit ~= nil and hit.successful then
				camera.position = hit.position
			else
				camera.position = desiredPosition
			end
		else
			camera.position = desiredPosition
		end
	end

	return true
end

local function clampColor(value)
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

local function drawSafe(fn)
	local ok = pcall(fn)
	if ok then
		lastGraphicsDrawOkTime = os.clock()
	else
		graphicsFailureCount = (graphicsFailureCount or 0) + 1
	end
	return ok
end

local function getGraphicsDrawLifetime()
	return math.max(config.graphicsDrawLifetime or 0.08, 0.01)
end

local function getTeamGraphicsColor(player)
	if player ~= nil and player.teamIndex == 0 then
		return 0.2, 0.55, 1.0
	elseif player ~= nil and player.teamIndex == 1 then
		return 1.0, 0.35, 0.25
	end

	return 0.25, 0.85, 1.0
end

local function applyVibrance(r, g, b, alpha)
	local boost = config.graphicsVibrance or 1.2
	local fade = alpha or 1
	return clampColor(r * boost * fade), clampColor(g * boost * fade), clampColor(b * boost * fade)
end

local function updateGraphicsTrail(ball, dt)
	goalRuntime.trailClock = (goalRuntime.trailClock or 0) + dt -- the trail's own clock (for the animated styles)
	if ball == nil or ball.transform == nil or ball.transform.position == nil then
		local j = 1
		while j <= #graphicsTrail do
			graphicsTrail[j].life = graphicsTrail[j].life - (dt * 0.2)
			if graphicsTrail[j].life <= 0 then table.remove(graphicsTrail, j) else j = j + 1 end
		end
		return
	end
	local ballPos = ball.transform.position
	-- (down to 0.03s)
	local duration = math.max(config.graphicsTrailDuration or 1.25, 0.03)
	if lastGraphicsTrailBallPosition ~= nil and safeDistance(lastGraphicsTrailBallPosition, ballPos) > 2500 then
		graphicsTrail = {}
	end
	lastGraphicsTrailBallPosition = ballPos
	graphicsTrailTimer = (graphicsTrailTimer or 0) + dt
	-- a very short trail records the ball every tick, so it still has a few points to draw
	local shouldAdd = (#graphicsTrail == 0) or graphicsTrailTimer >= (if duration < 0.3 then 0 else 0.02)
	if not shouldAdd and #graphicsTrail > 0 then
		shouldAdd = safeDistance(graphicsTrail[#graphicsTrail].position, ballPos) >= 4
	end
	if shouldAdd then
		graphicsTrailTimer = 0
		table.insert(graphicsTrail, { position = ballPos, life = duration, speed = getBallVelocity(ball):length(), born = goalRuntime.trailClock })
	end
	local maxPoints = 140
	local i = 1
	while i <= #graphicsTrail do
		graphicsTrail[i].life = graphicsTrail[i].life - dt
		-- (the newest three points are always kept, so even the shortest fade time leaves a stub
		-- of trail behind the ball instead of nothing)
		if (graphicsTrail[i].life <= 0 and #graphicsTrail > 3) or #graphicsTrail > maxPoints then table.remove(graphicsTrail, i) else i = i + 1 end
	end
end

local function getBallTrailColorForSpeed(speed, fade)
	if not config.graphicsBallTrailSpeedColorEnabled then
		return applyVibrance(0.2, 0.65, 1.0, fade)
	end
	local lowSpeed = config.graphicsBallTrailBlueSpeed or 300
	local highSpeed = math.max(config.graphicsBallTrailRedSpeed or 2200, lowSpeed + 1)
	local t = clamp01(((speed or 0) - lowSpeed) / (highSpeed - lowSpeed))
	-- Light blue at slow speed, hot orange/red at high speed.
	local r = 0.2 + (0.95 * t)
	local g = 0.75 - (0.55 * t)
	local b = 1.0 - (0.95 * t)
	return applyVibrance(r, g, b, fade)
end

local function drawBallTrail()
	if not config.graphicsBallTrailEnabled then return end
	if #graphicsTrail < 2 then
		-- Ball trail fallback glow: one point is enough to prove graphics are alive.
		if #graphicsTrail == 1 then
			local p = graphicsTrail[1]
			local r, g, b = getBallTrailColorForSpeed(p.speed or 0, 0.8)
			drawSafe(function()
				WorldDraw.drawLine(p.position + Vec3.new(0, 8, 0), p.position - Vec3.new(0, 8, 0), r, g, b, math.max(2, config.graphicsTrailThickness or 4), getGraphicsDrawLifetime())
			end)
		end
		return
	end
	local duration = math.max(config.graphicsTrailDuration or 1.25, 0.03)
	local style = config.graphicsBallTrailStyle or "Boost Ribbon"
	if BallTrails.handles[style] then
		-- Animated styles live in balltrails.luau. A drawing error there only costs this tick's trail.
		drawSafe(function()
			local lifetime = getGraphicsDrawLifetime()
			BallTrails.draw(style, graphicsTrail, {
				line = function(a, c, r, g, b, thickness) WorldDraw.drawLine(a, c, r, g, b, thickness, lifetime) end,
				duration = duration,
				thickness = config.graphicsTrailThickness or 4,
				time = goalRuntime.trailClock or 0,
				up = getUpDir(nil),
				colour = getBallTrailColorForSpeed,
			})
		end)
		return
	end
	for i = 2, #graphicsTrail do
		local previousPoint = graphicsTrail[i - 1]
		local currentPoint = graphicsTrail[i]
		local seg = safeDistance(previousPoint.position, currentPoint.position)
		if seg <= 2500 then
			local fade = clamp01(currentPoint.life / duration)
			local r, g, b = getBallTrailColorForSpeed(currentPoint.speed or 0, math.max(fade, 0.25))
			local thickness = math.max(1.2, (config.graphicsTrailThickness or 4) * math.max(fade, 0.32))
			local coreWidth = config.graphicsBallTrailCoreWidth or 0.72
			local glowWidth = config.graphicsBallTrailGlowWidth or 2.2
			drawSafe(function()
				if style == "Classic Line" then
					WorldDraw.drawLine(previousPoint.position, currentPoint.position, r, g, b, thickness, getGraphicsDrawLifetime())
				elseif style == "Plasma Beam" then
					WorldDraw.drawLine(previousPoint.position, currentPoint.position, r, g, b, thickness * glowWidth, getGraphicsDrawLifetime())
					WorldDraw.drawLine(previousPoint.position, currentPoint.position, 1, 1, 1, thickness * coreWidth, getGraphicsDrawLifetime())
				elseif style == "Rocket League Boost" then
					WorldDraw.drawLine(previousPoint.position, currentPoint.position, r, g, b, thickness * glowWidth, getGraphicsDrawLifetime())
					WorldDraw.drawLine(previousPoint.position, currentPoint.position, 1.0, 0.85, 0.25, thickness * coreWidth, getGraphicsDrawLifetime())
				else
					WorldDraw.drawLine(previousPoint.position, currentPoint.position, r, g, b, thickness * glowWidth, getGraphicsDrawLifetime())
					WorldDraw.drawLine(previousPoint.position, currentPoint.position, clampColor(r * 1.3), clampColor(g * 1.3), clampColor(b * 1.3), thickness * coreWidth, getGraphicsDrawLifetime())
				end
			end)
		end
	end
end

local function drawBallOutline(ball)
	if not config.graphicsBallOutlineEnabled or ball == nil or ball.transform == nil or ball.transform.position == nil then
		return
	end

	local ballPos = ball.transform.position
	local distance = safeDistance(camera.position, ballPos)
	if distance < 30 then
		return
	end

	local toBall = safeNormalize(ballPos - camera.position, camera.rotation:getForwardVector())
	local right = safeNormalize(toBall:cross(camera.rotation:getUpVector()), camera.rotation:getRightVector())
	local up = safeNormalize(right:cross(toBall), camera.rotation:getUpVector())
	local radius = 17.5 * (config.graphicsBallOutlineSize or 1.3)
	local segments = 28
	local thickness = math.max(0.4, (config.graphicsBallOutlineThickness or 2.5) * math.min(2.5, 450 / math.max(distance, 1)))
	local r, g, b = applyVibrance(0.95, 0.95, 1.0, 1)
	local previousPoint = ballPos + (right * radius)

	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local currentPoint = ballPos + (right * math.cos(angle) * radius) + (up * math.sin(angle) * radius)
		drawSafe(function()
			WorldDraw.drawLine(previousPoint, currentPoint, r, g, b, thickness, getGraphicsDrawLifetime())
		end)
		previousPoint = currentPoint
	end
end

local function drawTargetMarker(player)
	if not config.graphicsTargetMarkerEnabled or player == nil then
		return
	end

	local headPos = getHeadPosition(player)
	if headPos == nil then
		return
	end

	local upDir = getUpDir(player)
	local right = if player.root ~= nil and player.root.rotation ~= nil then player.root.rotation:getRightVector() else camera.rotation:getRightVector()
	local size = config.graphicsTargetMarkerSize or 18
	local center = headPos + (upDir * (30 + math.sin(os.clock() * 5) * 4))
	local shape = config.graphicsTargetMarkerShape or "Diamond"
	local r, g, b = getTeamGraphicsColor(player)
	local thickness = 2.5

	if shape == "Yellow Ducky" then
		r, g, b = applyVibrance(1.0, 0.86, 0.08, 1)
		thickness = 3.0
	else
		r, g, b = applyVibrance(r, g, b, 1)
	end

	local lifetime = getGraphicsDrawLifetime()

	drawSafe(function()
		if shape == "Yellow Ducky" then
			local bodyCenter = center - (upDir * size * 0.1)
			local headCenter = center + (upDir * size * 0.55) + (right * size * 0.35)
			local tail = bodyCenter - (right * size * 1.05) + (upDir * size * 0.15)
			local bodyFront = bodyCenter + (right * size * 0.7)
			local bodyTop = bodyCenter + (upDir * size * 0.35)
			local bodyBottom = bodyCenter - (upDir * size * 0.45)
			local beak = headCenter + (right * size * 0.55)
			local eye = headCenter + (upDir * size * 0.12)

			WorldDraw.drawLine(tail, bodyTop, r, g, b, thickness, lifetime)
			WorldDraw.drawLine(bodyTop, bodyFront, r, g, b, thickness, lifetime)
			WorldDraw.drawLine(bodyFront, bodyBottom, r, g, b, thickness, lifetime)
			WorldDraw.drawLine(bodyBottom, tail, r, g, b, thickness, lifetime)
			WorldDraw.drawLine(bodyTop, headCenter - (right * size * 0.25), r, g, b, thickness, lifetime)
			WorldDraw.drawLine(headCenter - (right * size * 0.25), headCenter + (upDir * size * 0.35), r, g, b, thickness, lifetime)
			WorldDraw.drawLine(headCenter + (upDir * size * 0.35), headCenter + (right * size * 0.35), r, g, b, thickness, lifetime)
			WorldDraw.drawLine(headCenter + (right * size * 0.35), bodyFront, r, g, b, thickness, lifetime)
			WorldDraw.drawLine(headCenter + (right * size * 0.25), beak, 1.0, 0.45, 0.0, thickness, lifetime)
			WorldDraw.drawLine(beak, headCenter + (right * size * 0.25) - (upDir * size * 0.18), 1.0, 0.45, 0.0, thickness, lifetime)
			WorldDraw.drawLine(eye, eye, 0.05, 0.05, 0.05, thickness * 1.4, lifetime)
		else
			local top = center + (upDir * size)
			local bottom = center - (upDir * size * 0.75)
			local left = center - (right * size * 0.6)
			local rightPoint = center + (right * size * 0.6)
			WorldDraw.drawLine(top, rightPoint, r, g, b, thickness, lifetime)
			WorldDraw.drawLine(rightPoint, bottom, r, g, b, thickness, lifetime)
			WorldDraw.drawLine(bottom, left, r, g, b, thickness, lifetime)
			WorldDraw.drawLine(left, top, r, g, b, thickness, lifetime)
		end
	end)
end

local TEAM_MARKER_COLORS = {
	{ r = 0.1, g = 0.75, b = 1.0 },
	{ r = 1.0, g = 0.85, b = 0.05 },
	{ r = 1.0, g = 0.25, b = 0.55 },
	{ r = 0.35, g = 1.0, b = 0.25 },
	{ r = 0.85, g = 0.45, b = 1.0 },
	{ r = 1.0, g = 0.45, b = 0.05 },
}

local function getStablePlayerColorIndex(player, fallbackIndex)
	local seed = fallbackIndex or 1
	local id = getPlayerId(player)
	if typeof(id) == "number" then
		seed = id
	else
		local name = getPlayerName(player)
		seed = 0
		for i = 1, string.len(name) do
			seed = seed + string.byte(name, i)
		end
	end

	return (math.abs(seed) % #TEAM_MARKER_COLORS) + 1
end

local function getTeamMarkerColor(player, index)
	if not config.graphicsTeamMarkersUniqueColors then
		local r, g, b = getTeamGraphicsColor(player)
		return applyVibrance(r, g, b, 1)
	end

	local color = TEAM_MARKER_COLORS[getStablePlayerColorIndex(player, index)]
	return applyVibrance(color.r, color.g, color.b, 1)
end

local function drawTeamMarkerForPlayer(player, index, activePlayerId)
	if player == nil or not isArenaPlayer(player) then
		return
	end

	if not config.graphicsTeamMarkersShowTarget and activePlayerId ~= nil and getPlayerId(player) == activePlayerId then
		return
	end

	local headPos = getHeadPosition(player)
	if headPos == nil then
		return
	end

	local upDir = getUpDir(player)
	local right = if player.root ~= nil and player.root.rotation ~= nil then player.root.rotation:getRightVector() else camera.rotation:getRightVector()
	local forward = safeNormalize(right:cross(upDir), camera.rotation:getForwardVector())
	local size = config.graphicsTeamMarkerSize or 12
	local center = headPos + (upDir * (config.graphicsTeamMarkerHeight or 58))
	local r, g, b = getTeamMarkerColor(player, index)
	local lifetime = getGraphicsDrawLifetime()

	drawSafe(function()
		local top = center + (upDir * size)
		local bottom = center - (upDir * size)
		local left = center - (right * size)
		local rightPoint = center + (right * size)
		local front = center + (forward * size * 0.75)
		local back = center - (forward * size * 0.75)
		WorldDraw.drawLine(top, rightPoint, r, g, b, 2.2, lifetime)
		WorldDraw.drawLine(rightPoint, bottom, r, g, b, 2.2, lifetime)
		WorldDraw.drawLine(bottom, left, r, g, b, 2.2, lifetime)
		WorldDraw.drawLine(left, top, r, g, b, 2.2, lifetime)
		WorldDraw.drawLine(front, back, r, g, b, 1.4, lifetime)
		WorldDraw.drawLine(center, headPos + (upDir * 12), r, g, b, 1.2, lifetime)
	end)
end

local function drawTeamMarkers(activePlayer)
	if not config.graphicsTeamMarkersEnabled or activePlayer == nil then
		return
	end

	local activeTeamIndex = activePlayer.teamIndex
	local activePlayerId = getPlayerId(activePlayer)
	local players = getArenaPlayers()
	local markerIndex = 1
	for i = 1, #players do
		local player = players[i]
		if player ~= nil and (not config.graphicsTeamMarkersSameTeamOnly or player.teamIndex == activeTeamIndex) then
			drawTeamMarkerForPlayer(player, markerIndex, activePlayerId)
			markerIndex = markerIndex + 1
		end
	end
end

local function drawLineToBall(player, ball)
	if not config.graphicsLineToBallEnabled or player == nil or ball == nil or ball.transform == nil or ball.transform.position == nil then
		return
	end

	local headPos = getHeadPosition(player)
	if headPos == nil then
		return
	end

	local r, g, b = applyVibrance(0.15, 0.75, 1.0, 0.65)
	drawSafe(function()
		WorldDraw.drawLine(headPos, ball.transform.position, r, g, b, 1.5, getGraphicsDrawLifetime())
	end)
end

local function colorComponentsNormalized(color, fallbackR, fallbackG, fallbackB)
	if color == nil then
		return fallbackR or 1, fallbackG or 1, fallbackB or 1
	end

	local r = color.R or color.r or fallbackR or 1
	local g = color.G or color.g or fallbackG or 1
	local b = color.B or color.b or fallbackB or 1
	if r > 1 or g > 1 or b > 1 then
		r = r / 255
		g = g / 255
		b = b / 255
	end
	return clampColor(r), clampColor(g), clampColor(b)
end

local GOAL_EXPLOSION_TYPES = {
	"Basic Burst",
	"Crumble",
	"Claw Strike",
	"Ripple Wave",
	"Implosion",
	"Ducky Spirit",
	"Dueling Dragons",
	"Caster Burst",
}
for _, effectName in ipairs(GoalEffects.newTypes) do table.insert(GOAL_EXPLOSION_TYPES, effectName) end

local GOAL_EXPLOSION_COLORS = {
	"Default",
	"Team Color",
	"Blue",
	"Orange",
	"Black",
	"Titanium White",
	"Crimson",
	"Lime",
	"Sky Blue",
	"Purple",
	"Gold",
	"Custom RGB",
}

local function getNamedGoalExplosionColor(colorMode, teamIndex)
	local mode = colorMode or "Default"
	if mode == "Default" or mode == "Team Color" then
		if teamIndex == 0 then
			return 0.2, 0.55, 1.0
		elseif teamIndex == 1 then
			return 1.0, 0.35, 0.25
		else
			return 0.0, 0.65, 1.0
		end
	elseif mode == "Blue" or mode == "Custom Blue" then
		return 0.0, 0.65, 1.0
	elseif mode == "Orange" then
		return 1.0, 0.42, 0.05
	elseif mode == "Black" then
		return 0.015, 0.015, 0.025
	elseif mode == "Titanium White" then
		return 0.95, 0.95, 1.0
	elseif mode == "Crimson" then
		return 1.0, 0.05, 0.08
	elseif mode == "Lime" then
		return 0.35, 1.0, 0.08
	elseif mode == "Sky Blue" then
		return 0.25, 0.8, 1.0
	elseif mode == "Purple" then
		return 0.65, 0.25, 1.0
	elseif mode == "Gold" then
		return 1.0, 0.78, 0.08
	elseif mode == "Custom RGB" then
		return config.goalExplosionCustomR or 0, config.goalExplosionCustomG or 0.65, config.goalExplosionCustomB or 1
	end
	return 0.0, 0.65, 1.0
end

local function getGoalExplosionColor(teamIndex, options)
	local mode = (options and options.colorMode) or config.goalExplosionColorMode
	local r, g, b = getNamedGoalExplosionColor(mode, teamIndex)
	if (mode == "Default" or mode == "Team Color") and options and options.teamColor then
		r, g, b = colorComponentsNormalized(options.teamColor, r, g, b)
	end
	-- Keep true black usable by drawing it as a very dark blue/gray instead of invisible black.
	if (r + g + b) < 0.06 then
		r, g, b = 0.035, 0.045, 0.07
	end
	return clampColor(r), clampColor(g), clampColor(b)
end

local function goalColorObject(r, g, b)
	return Color.new(clampColor(r), clampColor(g), clampColor(b), 1)
end

local function normalizePlayerName(name)
	return string.lower(tostring(name or ""))
end

local function getAssignedGoalExplosionType(scorerName)
	local scorer = normalizePlayerName(scorerName)
	if scorer ~= "" and scorer ~= "n/a" and scorer ~= "unknown" then
		local assignments = {
			{ player = config.goalExplosionAssignment1Player, effect = config.goalExplosionAssignment1Type },
			{ player = config.goalExplosionAssignment2Player, effect = config.goalExplosionAssignment2Type },
			{ player = config.goalExplosionAssignment3Player, effect = config.goalExplosionAssignment3Type },
			{ player = config.goalExplosionAssignment4Player, effect = config.goalExplosionAssignment4Type },
			{ player = config.goalExplosionAssignment5Player, effect = config.goalExplosionAssignment5Type },
		}
		for i = 1, #assignments do
			local entry = assignments[i]
			local assignedName = normalizePlayerName(entry.player)
			if assignedName ~= "" and assignedName == scorer then
				return entry.effect or config.goalExplosionFallbackType or config.goalExplosionType or "Ripple Wave"
			end
		end
	end
	return config.goalExplosionFallbackType or config.goalExplosionType or "Ripple Wave"
end

local function trimGoalExplosionParticles()
	local maxParticles = math.clamp(math.floor(config.goalExplosionMaxActiveParticles or 120), 1, 420)
	while #goalExplosionParticles > maxParticles do
		table.remove(goalExplosionParticles, 1)
	end
	if ParticleSystem ~= nil and ParticleSystem.particles ~= nil then
		while #ParticleSystem.particles > math.max(0, maxParticles - #goalExplosionParticles) do
			table.remove(ParticleSystem.particles, 1)
		end
	end
end

local function spawnGoalLineParticle(position, velocity, life, r, g, b, size)
	table.insert(goalExplosionParticles, {
		type = "Line Particle",
		position = position,
		lastPosition = position,
		velocity = velocity,
		life = life,
		maxLife = life,
		r = r,
		g = g,
		b = b,
		size = size or 3,
	})
end

local function spawnGoalExplosion(position, teamIndex, scorerName, goalForward, goalRight, goalUp, options)
	if not config.customGoalExplosionsEnabled or position == nil then
		return
	end

	-- A goal effect is a short animation, not a permanent particle storm.
	goalExplosionParticles = {}
	if ParticleSystem ~= nil then
		ParticleSystem.particles = {}
	end

	local r, g, b = getGoalExplosionColor(teamIndex, options)
	local effectType = (options and options.effectType) or getAssignedGoalExplosionType(scorerName)
	local life = math.max(0.2, config.goalExplosionLifetime or 1.1)
	local count = math.clamp(math.floor(config.goalExplosionParticleCount or 70), 1, math.clamp(math.floor(config.goalExplosionMaxActiveParticles or 120), 1, 420))
	local upDir = safeNormalize(goalUp or getUpDir(nil), getUpDir(nil))
	local forward = safeNormalize(goalForward or Vec3.forwardVector, Vec3.forwardVector)
	local right = safeNormalize(goalRight or forward:cross(upDir), Vec3.rightVector)

	local function moduleEffect(typeName)
		local effectLife = math.max(life, GoalEffects.minLife[typeName] or 1)
		table.insert(goalExplosionParticles, {
			type = typeName,
			center = position,
			forward = forward,
			right = right,
			upDir = upDir,
			life = effectLife,
			maxLife = effectLife,
			r = r,
			g = g,
			b = b,
			impact = options and options.impact, -- where the ball went in (may be nil)
			goalOrigin = options and options.goalOrigin, -- goal frame origin (nil for ball-position profiles)
			-- ball-spot effects that stand on the floor (Tornado): the floor under the ball
			ground = if GoalEffects.ballCentered[typeName] then goalRuntime.groundBelow(position, upDir, options and options.goalOrigin) else nil,
			-- a paint colour is selected (not Default / Team Color): the effect is drawn entirely in it
			painted = config.goalExplosionColorMode ~= nil and config.goalExplosionColorMode ~= "Default" and config.goalExplosionColorMode ~= "Team Color",
			seed = math.random(1, 9000),
		})
	end

	if effectType == "Ripple Wave" then
		table.insert(goalExplosionParticles, {
			type = "Ripple Wave",
			center = position,
			forward = forward,
			right = right,
			upDir = upDir,
			life = life,
			maxLife = life,
			maxRadius = config.goalExplosionRippleMaxRadius or 760,
			rings = math.max(3, math.floor(config.goalExplosionRingCount or 4)),
			thickness = config.goalExplosionRippleThickness or 7,
			rise = config.goalExplosionRippleRise or 10,
			r = r,
			g = g,
			b = b,
		})
	elseif GoalEffects.handles[effectType] then
		-- Line-drawn effects that live in goaleffects.luau (everything except Ripple Wave, Basic
		-- Burst and the Caster particles).
		moduleEffect(effectType)
	elseif effectType == "Caster Burst" and config.goalExplosionUseCasterParticles and ParticleSystem ~= nil then
		ParticleSystem.vibrance = config.goalExplosionVibrance or 1.15
		-- Thick, fast embers (a hair-thin ember cannot be seen at arena scale) and a
		-- line-drawn shockwave layer under the Caster particles. Same particle counts as before.
		for i = 1, count do
			local velocityVector = Vec3.new(math.random(-105, 105), math.random(-105, 105), math.random(-80, 130))
			ParticleSystem:createParticle(position, Quat.identity, 0.32 + math.random() * 0.2, velocityVector, goalColorObject(r, g, b), ParticleSystem.Variant.Embers, math.random(90, 170))
		end
		moduleEffect("Caster Shockwave")
		local ringLife = math.max(45, life * 60)
		for i = 1, math.clamp(math.floor(config.goalExplosionRingCount or 1), 0, 5) do
			ParticleSystem:createParticle(position, (options and options.rotation) or Quat.identity, 0.45 + (i * 0.18), Vec3.zeroVector, goalColorObject(r, g, b), ParticleSystem.Variant.Rings, ringLife + (i * 45))
		end
	else
		-- Basic Burst: short outward spray from the ball/goal position.
		local burstCount = count
		for i = 1, burstCount do
			local a = (i / burstCount) * math.pi * 2
			local spread = (math.random() - 0.5) * 0.9
			local dir = safeNormalize((right * math.cos(a)) + (upDir * (math.sin(a) * 0.55 + spread)) + (forward * (math.random() - 0.5)), upDir)
			spawnGoalLineParticle(position, dir * math.random(260, 760), math.max(0.8, life), r, g, b, math.random(6, 15))
		end
	end

	-- Freeze the resolved goal frame on every custom effect, including line particles.
	for _, effect in ipairs(goalExplosionParticles) do
		effect.forward, effect.right, effect.upDir = forward, right, upDir
	end
	trimGoalExplosionParticles()
end

local function drawWorldLine(a, b, r, g, bColor, thickness, lifetime)
	goalRuntime.drawLine(a, b, r, g, bColor, thickness, lifetime)
end

local function drawRippleRing(center, radius, upDir, r, g, b, thickness, lifetime, basisForward)
	if center == nil or radius <= 0 then
		return
	end
	local forward = horizontalize(basisForward or Vec3.forwardVector, upDir, Vec3.rightVector)
	forward = safeNormalize(forward, Vec3.forwardVector)
	local right = safeNormalize(forward:cross(upDir), Vec3.rightVector)
	local segments = 40
	local previousPoint = center + (right * radius)
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local currentPoint = center + (right * math.cos(angle) * radius) + (forward * math.sin(angle) * radius)
		drawWorldLine(previousPoint, currentPoint, r, g, b, thickness, lifetime)
		previousPoint = currentPoint
	end
end

-- (Ducky Spirit, Implosion and Dueling Dragons are drawn by goaleffects.luau.)

local function drawWaterRippleSphere(p, upDir, forward, right, baseT, fade)
	upDir=p.upDir or upDir; forward=p.forward or forward; right=p.right or right
	local vibrance=config.goalExplosionVibrance or 1.35; local r,g,b=clampColor(p.r*vibrance),clampColor(p.g*vibrance),clampColor(p.b*vibrance)
	local ringCount=math.max(2,p.rings or math.floor(config.goalExplosionRingCount or 3)); local maxRadius=p.maxRadius or 760
	for ring=1,ringCount do
		local offset=(ring-1)*0.16; local t=clamp01((baseT-offset)/math.max(1-offset,0.01))
		if t>0 and t<1 then local eased=1-((1-t)*(1-t)); local radius=eased*maxRadius; local ringFade=(1-t)*fade; drawRippleRing(p.center,radius,upDir,r,g,b,(p.thickness or 7)*ringFade,0.08,forward); drawRippleRing(p.center,radius*0.72,right,r,g,b,(p.thickness or 7)*ringFade*0.35,0.08,upDir); drawRippleRing(p.center,radius*0.72,forward,r,g,b,(p.thickness or 7)*ringFade*0.35,0.08,right) end
	end
end

local function updateGoalExplosionParticles(dt)
	if #goalExplosionParticles == 0 then
		return
	end

	local upDir = getUpDir(nil)
	local forward = Vec3.forwardVector
	forward = safeNormalize(forward, Vec3.forwardVector)
	local right = safeNormalize(forward:cross(upDir), Vec3.rightVector)
	local i = 1
	while i <= #goalExplosionParticles do
		local p = goalExplosionParticles[i]
		p.life = p.life - dt
		if p.life <= 0 then
			table.remove(goalExplosionParticles, i)
		else
			local upDir = p.upDir or upDir
			local forward = p.forward or forward
			local right = p.right or right
			local age = (p.maxLife or 1.0) - p.life
			local baseT = clamp01(age / math.max(p.maxLife or 1.0, 0.01))
			local fade = clamp01(p.life / math.max(p.maxLife or 1.0, 0.01))
			if p.type == "Ripple Wave" then
				drawWaterRippleSphere(p, upDir, forward, right, baseT, fade)
			elseif p.type == "Line Particle" then
				p.lastPosition = p.position
				p.velocity = p.velocity - ((p.upDir or upDir) * (dt * 260))
				p.position = p.position + (p.velocity * dt)
				-- streak: a fixed slice of its own speed, so it is a spark at any frame rate, not a dot
				drawWorldLine(p.position - (p.velocity * 0.07), p.position, clampColor(p.r * 1.2), clampColor(p.g * 1.2), clampColor(p.b * 1.2), (p.size or 3) * fade, 0.08)
			elseif GoalEffects.handles[p.type] then
				GoalEffects.draw(p, baseT, fade, drawWorldLine, {
					scale = config.goalExplosionDramaticScale or 1.35,
					vibrance = config.goalExplosionVibrance or 1.35,
					budget = (goalRuntime.limit or 256) - (goalRuntime.attempts or 0),
					eye = camera.position,
					fov = camera.fieldOfView,
				})
			end
			i = i + 1
		end
	end
end

local function goalNumber(value, default, minimum, maximum)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return default end
	return math.clamp(value, minimum, maximum)
end

function goalRuntime.settings()
	return {
		goalExplosionScorePollSeconds = goalNumber(config.goalExplosionScorePollSeconds, 0.1, 0.05, 2),
		goalExplosionArenaGraceSeconds = goalNumber(config.goalExplosionArenaGraceSeconds, 3, 0, 10),
		goalExplosionTouchMaxAgeSeconds = goalNumber(config.goalExplosionTouchMaxAgeSeconds, 4, 0, 15),
		goalExplosionDebounceSeconds = goalNumber(config.goalExplosionDebounceSeconds, 2, 0, 8),
		goalExplosionOnlyClosestArena = config.goalExplosionOnlyClosestArena ~= false,
		goalExplosionTouchRadius = goalNumber(config.goalExplosionTouchRadius, 95, 1, 220),
	}
end

function goalRuntime.clear(resetContext)
	goalExplosionParticles = {}
	ParticleSystem.particles = {}
	goalRuntime.pendingTest = nil
	goalRuntime.trail = {}
	goalRuntime.goalCam = nil
	goalRuntime.holdLeft = 0
	if resetContext then GoalContext:reset() end
end

function goalRuntime.drawLine(a, b, r, g, bColor, thickness, _lifetime)
	if goalRuntime.attempts >= (goalRuntime.limit or 256) then
		goalRuntime.dropped += 1
		return
	end
	goalRuntime.attempts += 1
	local ok, err = pcall(function()
		WorldDraw.drawLine(a, b, r, g, bColor, thickness, goalRuntime.drawLifetime or 0.08)
	end)
	if ok then goalRuntime.lines += 1 else goalRuntime.status = "Goal draw error: " .. tostring(err) end
end

-- The inside modes that are ball cams (ball-only routing, arena pin, goal cam).
goalRuntime.ballCamModes = { ["Autocast - Simple Ball Cam"] = true, ["Autocast - Simple Ball Cam + Goal Cam"] = true, ["Autocast - Ball Carrier"] = true }

-- Ball-centred effects are drawn where the ball was, not at the middle of the goal mouth.
goalRuntime.ballCentered = { ["Implosion"] = true, ["Caster Burst"] = true, ["Basic Burst"] = true }
for effectName in pairs(GoalEffects.ballCentered) do goalRuntime.ballCentered[effectName] = true end
goalRuntime.trail = {}
goalRuntime.clock = 0

-- Where the scoring ball was. Real goal: the recent ball sample closest to the scored-on goal
-- (the ball is often reset or removed by the time the score changes, so "current position" is
-- not good enough). Manual test: where the ball is right now. nil -> keep the goal position.
function goalRuntime.ballSpot(goalPosition, manual)
	local trail = goalRuntime.trail
	if #trail == 0 then return nil end
	if manual then
		local last = trail[#trail]
		return if goalRuntime.clock - last.t <= 0.5 then last.p else nil
	end
	local best, bestDistance = nil, 1200
	for i = 1, #trail do
		local distance = safeDistance(trail[i].p, goalPosition)
		if distance < bestDistance then best, bestDistance = trail[i].p, distance end
	end
	return best
end

-- The floor directly under `spot` (same side of the goal, same depth; only the height changes).
-- 1. A ray cast straight down from the spot (the same call the community scripts use to project
--    the ball onto the ground).
-- 2. If there is a goal frame: the height of the bottom edge of the goal mouth (52.4 below the
--    goal frame origin). Used when the ray finds nothing, or lands far from that height.
-- Returns nil when neither is available (the effect then stays at the ball, as before).
function goalRuntime.groundBelow(spot, upDir, goalOrigin)
	local okAll, result = pcall(function()
		local guess = nil
		if goalOrigin ~= nil then guess = spot - (upDir * ((spot - goalOrigin):dot(upDir) + 52.404)) end
		local okRay, hit = pcall(function() return camera:castRay(spot, spot - (upDir * 2500)) end)
		if okRay and hit ~= nil and hit.successful and hit.position ~= nil then
			local drop = (spot - hit.position):dot(upDir)
			if drop == drop and drop > 1 and drop <= 2500 then
				local floorPoint = spot - (upDir * drop) -- keep it exactly under the spot
				if guess == nil or math.abs((floorPoint - guess):dot(upDir)) <= 500 then return floorPoint end
			end
		end
		return guess
	end)
	return if okAll then result else nil
end

-- SEND OVERLAY INFO (overlay.luau) -----------------------------------------------------------
-- Name of the player the camera is on right now, "" when it is on the ball / free / fixed.
function goalRuntime.followedName()
	if config.insideArenaMode == "Goal Explosion Test Cam" then return "" end
	if goalRuntime.simpleActive == true then
		-- ball cams: only Ball Carrier is ever on a player (whoever has the ball)
		if config.insideArenaMode == "Autocast - Ball Carrier" and carrierCam.mode == "carrier" and carrierCam.carrierId ~= nil then
			for _, player in ipairs(getPlayers()) do
				if getPlayerId(player) == carrierCam.carrierId then return getPlayerName(player) end
			end
		end
		return ""
	end
	local target = findTargetPlayer()
	if target == nil then return "" end
	local mode = if config.autoCasterEnabled and wasInsideArena then config.insideArenaMode else config.outsideArenaMode
	if mode == "Free Cam" or mode == "Fixed Camera" then return "" end
	return getPlayerName(target)
end

-- Is the camera casting an arena right now? True for a ball cam that is on an arena (or waiting in
-- one with the target), and for any player cam on a target who is in an arena. Free Cam never is:
-- there the camera's own position decides. Used by Send Overlay Info only.
function goalRuntime.castingArena()
	if config.insideArenaMode == "Goal Explosion Test Cam" then return false end
	if goalRuntime.simpleActive == true then
		if arenaPin.started == true then return true end
		return isArenaPlayer(findTargetPlayer())
	end
	if wasInsideArena ~= true then return false end
	local mode = if config.autoCasterEnabled then config.insideArenaMode else config.outsideArenaMode
	return mode ~= "Free Cam"
end

-- Runs every tick while "Send Overlay Info" is ticked (never otherwise).
function goalRuntime.overlay(dt)
	-- the arena list is refreshed by the ball cams / kickoffs; do it here on ticks where they did not
	if ArenaMap.time == goalRuntime.overlayMapTime then pcall(ArenaMap.refresh, dt) end
	goalRuntime.overlayMapTime = ArenaMap.time
	local ball = goalRuntime.ball
	local anchor = if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil then ball.transform.position else camera.position
	Overlay.tick(dt, { map = ArenaMap, anchor = anchor, ball = ball, balls = getBalls(), isArenaBall = isLikelyArenaBall,
		players = getPlayers(), followed = goalRuntime.followedName(), castRay = goalRuntime.overlayRay,
		clearAfterMatch = config.overlayClearAfterMatch ~= false,
		-- the empty "no arena" table while the camera is outside every arena and is not casting one
		clearOutside = config.overlayClearOutsideArena ~= false, cameraPos = camera.position,
		casting = goalRuntime.castingArena(),
		outsideSeconds = config.overlayOutsideSeconds, outsideMargin = config.overlayOutsideMargin })
end

-- Ray cast for the match stats (a shot that goes in off a wall); same call the goal effects use.
function goalRuntime.overlayRay(from, to)
	return camera:castRay(from, to)
end

-- KICKOFFS (kickoff.luau) -------------------------------------------------------------------
-- The nearest arena ball to a point (plain distance; none of the old arena-lock filtering).
function goalRuntime.ballNear(point, maxDistance)
	local best, bestDistance = nil, maxDistance
	for _, candidate in ipairs(getBalls()) do
		if candidate ~= nil and candidate.transform ~= nil and candidate.transform.position ~= nil and isLikelyArenaBall(candidate) then
			local gap = safeDistance(candidate.transform.position, point)
			if gap < bestDistance then best, bestDistance = candidate, gap end
		end
	end
	return best
end

-- Runs every tick, after the camera: reads the kickoff countdown of the arena being watched and
-- draws the kickoff graphic (through the same line budget as the goal effects).
function goalRuntime.kickoff(dt)
	if config.kickoffGraphicsEnabled == false and config.kickoffCamEnabled == false and Kickoff.testLeft == nil and Kickoff.phase == "idle" then
		Kickoff.status = "Kickoff graphics and kickoff cam are both off"
		return
	end
	-- The ball cams refresh the arena list themselves; do it here on ticks where they did not run.
	if ArenaMap.time == goalRuntime.mapTime then pcall(ArenaMap.refresh, dt) end
	goalRuntime.mapTime = ArenaMap.time
	-- The ball being followed, or failing that the ball sitting at the kickoff spot.
	local ball = goalRuntime.ball
	if (ball == nil or ball.transform == nil or ball.transform.position == nil) and Kickoff.base ~= nil then
		ball = goalRuntime.ballNear(Kickoff.base, 700)
	end
	local ballPos = if ball ~= nil and ball.transform ~= nil then ball.transform.position else nil
	Kickoff.update(dt, camera.position, ballPos, ArenaMap, {
		window = goalNumber(config.kickoffCountdownSeconds, 5, 1, 15),
		every = config.kickoffEveryCountdown == true,
		afterGo = goalNumber(config.kickoffCamAfterGoSeconds, 3, 0, 6) })
	if config.kickoffGraphicsEnabled == false or Kickoff.phase == "idle" then return end
	local mode = config.kickoffColorMode or "Team Color"
	local colors = Kickoff.colors or {}
	local hr, hg, hb = getGoalExplosionColor(0, { colorMode = mode, teamColor = colors[1] })
	local ar, ag, ab = getGoalExplosionColor(1, { colorMode = mode, teamColor = colors[2] })
	local ink, dim = nil, nil
	if mode ~= "Default" and mode ~= "Team Color" then
		-- one paint for the whole graphic: the away side, the neutral parts and the lettering are a
		-- shade lighter, the faint parts a shade darker (never white, grey or gold)
		dim = { hr * 0.74, hg * 0.74, hb * 0.74 }
		ar, ag, ab = clampColor(ar + 0.12), clampColor(ag + 0.12), clampColor(ab + 0.12)
		ink = { ar, ag, ab }
	end
	local linesBefore = goalRuntime.lines
	Kickoff.draw(goalRuntime.drawLine, { eye = camera.position, style = config.kickoffGraphicStyle,
		scale = goalNumber(config.kickoffGraphicScale, 1, 0.4, 2.5), numbers = config.kickoffShowNumbers ~= false,
		home = { hr, hg, hb }, away = { ar, ag, ab }, ink = ink, dim = dim })
	-- how many lines the kickoff graphic drew (read by the tests)
	goalRuntime.kickLines = goalRuntime.lines - linesBefore
	goalRuntime.kickDrawn = (goalRuntime.kickDrawn or 0) + goalRuntime.kickLines
end

-- Puts the camera on the kickoff shot if there is one right now. Returns true when it did.
function goalRuntime.kickoffShot(dt)
	local okPose, position, look, up, fov = pcall(Kickoff.pose, config.kickoffCamStyle, {
		distance = goalNumber(config.kickoffCamDistance, 1900, 400, 4000),
		height = goalNumber(config.kickoffCamHeight, 450, 0, 1500),
		fov = goalNumber(config.kickoffCamFov, 100, 50, 125),
		orbitSpeed = goalNumber(config.kickoffCamOrbitSpeed, 22, -90, 90) }, camera.position, ArenaMap)
	if not okPose or position == nil or look == nil then return false end
	stopVlogBridge()
	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	camera.fieldOfView = fov
	camera.position = position
	camera:lookAt(look, up)
	-- keep this arena's ball known: the graphic sits on it, and the shot ends early once it has
	-- been knocked well away from the spot
	local ball = goalRuntime.ballNear(look, 3500)
	if ball ~= nil then goalRuntime.ball, goalRuntime.ballKnown = ball, true end
	return true
end

-- Goal Explosion Test Cam: parks the camera at the goal cam spot of the arena it is in (or the
-- nearest one), looking at the goal the test will play on, and keeps that arena's ball known so
-- the ball-spot effects have a ball to use. Driven from the goal explosion menu. Returns true when it ran.
function goalRuntime.testCam(dt)
	stopVlogBridge()
	-- a kickoff test (kickoff menu) is watched from the kickoff cam
	if Kickoff.source == "test" and Kickoff.camActive and goalRuntime.kickoffShot(dt) then
		statusText = "Explosion preview | kickoff test: " .. Kickoff.styleFor(config.kickoffGraphicStyle) .. " | " .. tostring(config.kickoffCamStyle) .. " cam"
		return true
	end
	local side = if config.goalTestSide == 1 then 1 else 0
	if not config.customGoalExplosionsEnabled then
		runFreeCam(dt)
		statusText = "Explosion preview: goal explosions are off (a Test button in section 7 turns them on) | Free Cam"
		return true
	end
	local entry = GoalContext.current
	if entry == nil and type(GoalContext.entries) == "table" then
		local nearest = math.huge
		for _, candidate in pairs(GoalContext.entries) do
			local gap = safeDistance(camera.position, candidate.position)
			if gap < nearest then entry, nearest = candidate, gap end
		end
	end
	local frame = nil
	if entry ~= nil then frame = GoalContext:frame(entry, side, goalRuntime.settings()) end
	if frame == nil then
		runFreeCam(dt)
		statusText = "Explosion preview: no arena with goals found yet | Free Cam (fly into an arena)"
		return true
	end
	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	camera.fieldOfView = config.goalCamFov or 90
	camera.position = frame.position + (frame.forward * (config.goalCamDistance or 1300)) + (frame.up * (config.goalCamHeight or 420))
	camera:lookAt(frame.position + (frame.up * 170), frame.up)
	-- this arena's ball (nearest one to the goal), for effects that play where the ball is
	local ball, nearestBall = nil, 9000
	for _, candidate in ipairs(getBalls()) do
		if candidate ~= nil and candidate.transform ~= nil and candidate.transform.position ~= nil then
			local gap = safeDistance(candidate.transform.position, frame.position)
			if gap < nearestBall then ball, nearestBall = candidate, gap end
		end
	end
	goalRuntime.ball, goalRuntime.ballKnown = ball, ball ~= nil
	-- optional loop: play the chosen explosion again each time the last one has finished
	if config.goalTestLoop == true and #goalExplosionParticles == 0 and #ParticleSystem.particles == 0 and goalRuntime.pendingTest == nil then
		goalRuntime.testIdle = (goalRuntime.testIdle or 0) + dt
		if goalRuntime.testIdle >= 0.7 then
			goalRuntime.testIdle = 0
			goalRuntime.pendingTest = { teamIndex = side, effectType = config.goalExplosionType, colorMode = if side == 0 then "Blue" else "Orange" }
		end
	else
		goalRuntime.testIdle = 0
	end
	statusText = "Explosion preview | " .. tostring(entry.slot) .. " | " .. (if side == 0 then "Blue" else "Orange") .. " scores | " .. tostring(config.goalExplosionType)
	return true
end

function goalRuntime.spawn(frame, teamIndex, scorer, effectType, colorMode, manual)
	local resolvedType = effectType or getAssignedGoalExplosionType(scorer)
	local position = frame.position
	local okSpot, spot = pcall(goalRuntime.ballSpot, frame.position, manual == true)
	if not okSpot then spot = nil end
	if goalRuntime.ballCentered[resolvedType] and spot ~= nil then position = spot end
	-- Goal-face effects (Net Ripple, Glass Shatter) stay on the goal but start from the ball's entry point.
	-- (Ball-position profiles have no goal: there the frame is the ball itself.)
	local ballBased = GoalContext.current ~= nil and GoalContext.current.profile ~= nil and GoalContext.current.profile.ballBased == true
	spawnGoalExplosion(position, teamIndex, scorer, frame.forward, frame.right, frame.up,
		{ rotation = frame.rotation, teamColor = frame.color, effectType = resolvedType, colorMode = colorMode, impact = spot,
			goalOrigin = if ballBased then nil else frame.position })
	local duration = 2.2
	for _, effect in ipairs(goalExplosionParticles) do
		if type(effect.maxLife) == "number" then duration = math.max(duration, effect.maxLife) end
	end
	-- While this explosion plays, a ball cam does not chase a target who gets thrown out of the
	-- arena (zero-second and overtime goals). See tickCamera.
	goalRuntime.holdLeft = math.min(math.clamp(duration + 0.4, 1.5, 6), goalNumber(config.goalExplosionHoldMaxSeconds, 6, 1, 6))
	-- Goal cam shot: out on the field in front of this goal, raised, looking at the goal mouth.
	if not ballBased then
		goalRuntime.goalCam = {
			position = frame.position + (frame.forward * (config.goalCamDistance or 1300)) + (frame.up * (config.goalCamHeight or 420)),
			look = frame.position + (frame.up * 170), -- aim at the crossbar so effects above the goal stay in shot
			up = frame.up,
			untilClock = goalRuntime.clock + math.clamp(duration + 0.4, 1.5, 6),
		}
	end
end

function goalRuntime.update(dt)
	goalRuntime.lines, goalRuntime.attempts, goalRuntime.dropped = 0, 0, 0
	goalRuntime.limit = math.floor(goalNumber(config.goalExplosionMaxLinesPerTick, 256, 16, 2048))
	goalRuntime.drawLifetime = goalNumber(config.goalExplosionDrawLifetime, 0.08, 0.05, 0.12)
	ParticleSystem.maxParticles = math.floor(goalNumber(config.goalExplosionMaxActiveParticles, 120, 1, 420))
	ParticleSystem.ringSegments = math.floor(goalNumber(config.goalExplosionRingSegments, 32, 8, 90))
	ParticleSystem.collisionEnabled = config.goalExplosionEmberCollisionEnabled == true
	ParticleSystem.drawLifetime = goalRuntime.drawLifetime
	ParticleSystem.drawLine = goalRuntime.drawLine
	if not config.customGoalExplosionsEnabled then
		goalRuntime.clear(goalRuntime.enabled)
		goalRuntime.enabled = false
		goalRuntime.status = "Goal explosions disabled"
		return
	end
	goalRuntime.enabled = true
	-- Short history of the camera ball, for placing ball-centred goal effects.
	goalRuntime.clock += dt
	local trackedBall = goalRuntime.ball
	if trackedBall ~= nil and trackedBall.transform ~= nil and trackedBall.transform.position ~= nil then
		table.insert(goalRuntime.trail, { p = trackedBall.transform.position, t = goalRuntime.clock })
	end
	while #goalRuntime.trail > 0 and (goalRuntime.clock - goalRuntime.trail[1].t > 1.5 or #goalRuntime.trail > 240) do
		table.remove(goalRuntime.trail, 1)
	end
	local settings = goalRuntime.settings()
	local events = GoalContext:update(dt, goalRuntime.ball, camera.position, getPlayers(), settings)
	for _, event in ipairs(events) do
		goalRuntime.spawn(event.frame, event.teamIndex, event.scorer)
		goalRuntime.status = "Goal accepted: " .. GoalContext.lastGoal
	end
	local test = goalRuntime.pendingTest
	goalRuntime.pendingTest = nil
	if test then
		local frame, reason = GoalContext:frame(GoalContext.current, test.teamIndex, settings)
		if test.effectType == "Caster Burst" and not config.goalExplosionUseCasterParticles then
			goalRuntime.status = "Test not spawned: enable Use Caster particle system for Caster Burst"
		elseif frame then
			-- With a paint colour selected, the test shows that paint (what a real goal will look
			-- like). The Blue / Orange team palettes are only used for Default / Team Color.
			local paint = config.goalExplosionColorMode
			local testColor = if paint ~= nil and paint ~= "Default" and paint ~= "Team Color" then paint else test.colorMode
			goalRuntime.spawn(frame, test.teamIndex, "Unknown", test.effectType, testColor, true)
			goalRuntime.status = "Manual " .. testColor .. " test: " .. test.effectType
		else goalRuntime.status = "Test not spawned: " .. reason end
	end
	trimGoalExplosionParticles()
	-- Separate guards: one broken renderer cannot interrupt the camera or the other pool.
	local ok, err = pcall(updateGoalExplosionParticles, math.min(dt, 0.1))
	if not ok then goalExplosionParticles = {}; goalRuntime.status = "Custom effect error: " .. tostring(err) end
	ParticleSystem.speed = 1
	ok, err = pcall(function() ParticleSystem:particleAffect(dt) end)
	if not ok then ParticleSystem.particles = {}; goalRuntime.status = "Caster effect error: " .. tostring(err) end
end

local function renderStreamerGraphics(player, ball, dt)
	-- Graphics watchdog: keep the overlay system alive even if one component errors.
	if config.graphicsEnabled == nil then
		config.graphicsEnabled = true
	end
	if not config.graphicsEnabled then
		graphicsTrail = {}
		return
	end
	-- Do not clear the entire WorldDraw surface every frame by default; if a later draw fails,
	-- clearing first makes it look like all graphics turned off.
	if config.graphicsClearBeforeDraw then
		local clearOk = drawSafe(function()
			WorldDraw.clear()
		end)
		if not clearOk then
			config.graphicsClearBeforeDraw = false
		end
	end

	local okTrail = pcall(function()
		updateGraphicsTrail(ball, dt)
		drawBallTrail()
	end)
	local okOutline = pcall(function() drawBallOutline(ball) end)
	local okTeam = pcall(function() drawTeamMarkers(player) end)
	local okTarget = pcall(function() drawTargetMarker(player) end)
	local okLine = pcall(function() drawLineToBall(player, ball) end)
	if okTrail or okOutline or okTeam or okTarget or okLine then
		lastGraphicsDrawOkTime = os.clock()
		graphicsFailureCount = 0
	else
		graphicsFailureCount = (graphicsFailureCount or 0) + 1
	end
	-- Recovery: if everything has failed repeatedly, reset volatile draw state but keep toggles on.
	if (graphicsFailureCount or 0) > 45 then
		graphicsFailureCount = 0
		graphicsTrail = {}
		graphicsTrailTimer = 0
		lastGraphicsTrailBallPosition = nil
		config.graphicsEnabled = true
		config.graphicsBallTrailEnabled = true
		config.graphicsBallOutlineEnabled = true
		config.graphicsClearBeforeDraw = false
		statusText = "Graphics watchdog reset overlay state."
	end
end

local function resetPerTargetStateIfNeeded(player)
	local id = getPlayerId(player)
	if id ~= lastTargetId then
		duckState.lastTargetPosition = nil
		duckState.leashActive = false
		duckState.ruffleTimer = 0
		duckState.happyEmoteTimer = 0
		duckState.headpatCooldown = 0
		duckState.headpatTouching = false
		duckState.headpatReleaseTimer = 0
		duckState.faceHoldTimer = 0
		duckState.treatCooldown = 0
		duckState.feedTimer = 0
		duckState.feedCooldown = 0
		simpleBallSmoothFocus = nil
		simpleBallSmoothBackDir = nil
		simpleBallCamCurrentBall = nil
		freeCamInitialized = false
		freeCamRotEuler = nil
		vlogNativeGrabActive = false
		lastTargetId = id
	end
end

local function updateArenaLock(selectedTarget, arenaTarget)
	if not config.autoCastLockToSelectedArena then
		arenaLockCenter = nil
		return
	end

	local lockPlayer = if arenaTarget ~= nil then arenaTarget else selectedTarget
	if lockPlayer ~= nil and lockPlayer.root ~= nil and lockPlayer.root.position ~= nil then
		arenaLockCenter = lockPlayer.root.position
		arenaLockLastSeen = os.clock()
		return
	end

	if arenaLockCenter ~= nil and (os.clock() - (arenaLockLastSeen or 0)) > (config.autoCastArenaLockGraceSeconds or 8) then
		arenaLockCenter = nil
	end
end

local function runOutsideMode(player, dt)
	resetPerTargetStateIfNeeded(player)

	local ok = false

	if config.outsideArenaMode == "First Person POV" then
		stopVlogBridge()
		ok = followFirstPersonPOV(player, dt)
	elseif config.outsideArenaMode == "Vlog Camera (Follow+)" then
		ok = followVlogCamera(player, dt)
	elseif config.outsideArenaMode == "Free Cam" then
		ok = runFreeCam(dt)
	elseif config.outsideArenaMode == "SpecPet" then
		stopVlogBridge()
		ok = followSpecPet(player, dt)
	else
		stopVlogBridge()
		ok = followThirdPersonHeadMovement(player, dt)
	end

	if ok then
		statusText = "Outside: " .. config.outsideArenaMode .. " | " .. getPlayerName(player)
	end
end

local function runInsideMode(player, dt)
	resetPerTargetStateIfNeeded(player)

	local ok = false

	if config.insideArenaMode == "First Person POV" then
		stopVlogBridge()
		ok = followFirstPersonPOV(player, dt)
	elseif config.insideArenaMode == "Vlog Camera (Follow+)" then
		ok = followVlogCamera(player, dt)
	elseif config.insideArenaMode == "Free Cam" then
		ok = runFreeCam(dt)
	elseif config.insideArenaMode == "SpecPet" then
		stopVlogBridge()
		ok = followSpecPet(player, dt)
	elseif config.insideArenaMode == "Third Person - Ball Look" then
		stopVlogBridge()
		ok = followThirdPersonBallLook(player, dt)
	elseif config.insideArenaMode == "Autocast - Simple Ball Cam" or config.insideArenaMode == "Autocast - Simple Ball Cam + Goal Cam" then
		stopVlogBridge()
		ok = followSimpleBallCam(dt)
	elseif config.insideArenaMode == "Autocast - Ball Carrier" then
		stopVlogBridge()
		ok = followBallCarrierCam(dt)
	elseif config.insideArenaMode == "Fixed Camera" then
		stopVlogBridge()
		ok = runFixedCamera(player)
	else
		stopVlogBridge()
		ok = followThirdPersonHeadMovement(player, dt)
	end

	if ok then
		local graphicsBall = nil
		if goalRuntime.ballCamModes[config.insideArenaMode] then
			graphicsBall = simpleBallCamCurrentBall or getSimpleBallCamBall()
		else
			graphicsBall = getBestAutoCastBall(getHeadPosition(player))
		end
		if goalRuntime.ballKnown then
			graphicsBall = goalRuntime.ball
		else
			goalRuntime.ball = graphicsBall
		end
		renderStreamerGraphics(player, graphicsBall, dt)
		statusText = "Inside arena: " .. config.insideArenaMode .. " | " .. getPlayerName(player)
	end
end

-- Puts the camera next to the selected target (their arena, or their spot outside).
local function snapCameraToTarget(player)
	local headPos = getHeadPosition(player)
	if headPos == nil then return false end
	local upDir, _, dirForward = getPlayerDirs(player)
	camera.position = headPos + (dirForward * -(config.thirdPersonDistance or 120)) + (upDir * (config.thirdPersonHeight or 35))
	pcall(function() camera:lookAt(headPos, upDir) end)
	return true
end

-- Is `point` inside the box of arena `key` (or within `margin` of it)? False when that is not known.
local function pointInArena(key, point, margin)
	local entry = if key ~= nil and type(ArenaMap.entries) == "table" then ArenaMap.entries[key] else nil
	if entry == nil or point == nil then return false end
	local ok, result = pcall(function()
		local p = entry.inverse:rotateVector(point - entry.position)
		return math.abs(p.x) <= entry.hx + margin and math.abs(p.y) <= entry.hy + margin and math.abs(p.z - entry.lift) <= entry.hz + margin
	end)
	return ok and result == true
end

-- Is the arena the ball cam is locked on still in use? Yes while the game says a round is running
-- there, or while anybody on a team is in it (or nearer to it than to any other arena).
local function castArenaInUse(key)
	if key == nil then return false end
	local okData, running = pcall(function() return SpectatorGamemodes.getGamemodeData(key).isGameRunning == true end)
	if okData and running then return true end
	local players = getArenaPlayers()
	for i = 1, #players do
		local root = players[i].root
		if root ~= nil and root.position ~= nil then
			local okSlot, slot = pcall(ArenaMap.locate, root.position)
			if okSlot and slot == key then return true end
		end
	end
	return false
end

-- The arena lock when there is no target to go by: none selected, or the selected one is not on
-- this server right now, or (zero-second goals) they have just been thrown out of the arena.
-- The first time it takes the arena ball nearest the camera and remembers which arena that is.
-- From then on only balls of THAT arena are followed. While the arena has no ball (a goal, a break
-- between rounds) the answer is "wait": the camera holds its shot. The arena is only let go once
-- it has been out of use (see castArenaInUse) for config.ballCamArenaReleaseSeconds.
-- Returns "ball" (arenaPin.ball is set), "wait", or nil (there is no arena ball anywhere).
local function resolveLockedArenaBall(dt)
	arenaPin.time += dt
	arenaPin.id = nil -- a target who turns up later starts from their own arena straight away
	local balls = getBalls()
	for _ = 1, 2 do
		if not arenaPin.started then
			local nearest, nearestDistance = nil, math.huge
			for i = 1, #balls do
				local ball = balls[i]
				if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil and isLikelyArenaBall(ball) then
					local distance = safeDistance(camera.position, ball.transform.position)
					if distance < nearestDistance then nearest, nearestDistance = ball, distance end
				end
			end
			arenaPin.ball = nearest
			if nearest == nil then return nil end
			local okKey, key = pcall(ArenaMap.locate, nearest.transform.position)
			arenaPin.started, arenaPin.key = true, if okKey then key else nil
			arenaPin.ballPos, arenaPin.ballTime, arenaPin.emptyTime, arenaPin.challenger = nearest.transform.position, arenaPin.time, 0, 0
			arenaPin.goneTime = 0
			return "ball"
		end
		local key = arenaPin.key
		-- The lock has no arena name (there was no arena list when it was taken), or its arena is
		-- not on the list any more: go by where the ball that was being followed is now.
		local listed = key ~= nil and type(ArenaMap.entries) == "table" and ArenaMap.entries[key] ~= nil
		if not listed and ArenaMap.available then
			local same, sameDistance = nil, 1500
			if arenaPin.ballPos ~= nil then
				for i = 1, #balls do
					local ball = balls[i]
					if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil and isLikelyArenaBall(ball) then
						local drift = safeDistance(ball.transform.position, arenaPin.ballPos)
						if drift < sameDistance then same, sameDistance = ball, drift end
					end
				end
			end
			if same ~= nil then
				local okKey, found = pcall(ArenaMap.locate, same.transform.position)
				if okKey and found ~= nil then key = found; arenaPin.key = found end
				arenaPin.goneTime = 0
			elseif key ~= nil then
				-- that arena has gone from the list and its ball with it: let go after a moment
				-- (one failed read of the list looks the same, so not at once)
				arenaPin.goneTime = (arenaPin.goneTime or 0) + dt
				if arenaPin.goneTime >= 3 then arenaPin.emptyTime = math.huge end
			end
		else
			arenaPin.goneTime = 0
		end
		local best, bestDistance = nil, math.huge
		for i = 1, #balls do
			local ball = balls[i]
			if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil and isLikelyArenaBall(ball) then
				local ballPos = ball.transform.position
				local qualifies = false
				if key ~= nil then
					local okBall, ballKey = pcall(ArenaMap.locate, ballPos)
					qualifies = okBall and ballKey == key
				elseif arenaPin.ballPos ~= nil then
					-- no arena list to go by: only the ball that was already being followed
					qualifies = safeDistance(ballPos, arenaPin.ballPos) < 1500
				end
				if qualifies then
					local distance = safeDistance(ballPos, arenaPin.ballPos or camera.position)
					if distance < bestDistance then best, bestDistance = ball, distance end
				end
			end
		end
		if best ~= nil then
			arenaPin.ball, arenaPin.ballPos, arenaPin.ballTime, arenaPin.emptyTime = best, best.transform.position, arenaPin.time, 0
			return "ball"
		end
		arenaPin.ball = nil
		if arenaPin.emptyTime ~= math.huge then
			if castArenaInUse(key) then arenaPin.emptyTime = 0 else arenaPin.emptyTime = (arenaPin.emptyTime or 0) + dt end
		end
		local limit = if key ~= nil then goalNumber(config.ballCamArenaReleaseSeconds, 60, 5, 600) else 8
		if arenaPin.emptyTime < limit then return "wait" end
		-- out of use for long enough (or gone from the arena list): let go and look for the nearest ball again
		arenaPin.started, arenaPin.key, arenaPin.ballPos, arenaPin.emptyTime, arenaPin.goneTime = false, nil, nil, 0, 0
	end
	return "wait"
end

-- Keeps Simple Ball Cam in the SAME arena as the selected target, every tick (not just once on
-- arrival). Sets arenaPin.ball and returns a mode:
--   "ball"   -> arenaPin.ball is the arena ball of the target's arena: follow it.
--   "wait"   -> that arena had a ball a moment ago (goal / reset): hold the shot, do not wander off.
--   "target" -> no ball in the target's arena (pre-kickoff, just arrived): stay with the person.
-- The arena comes from the game's own arena list (ArenaMap). If that list is unavailable, the
-- arena ball nearest the TARGET is used instead. Either way the ball being followed is only
-- swapped for a different one after the new answer has held for a moment, so one odd frame of
-- data can never throw the camera into another arena.
local function resolveTargetArenaBall(target, dt)
	local targetPos = if target.root ~= nil then target.root.position else nil
	if targetPos == nil then
		arenaPin.ball = nil
		return nil
	end
	local id = getPlayerId(target)
	if id ~= arenaPin.id then
		arenaPin.id, arenaPin.started = id, false
	end
	local firstLock = not arenaPin.started
	if firstLock then
		arenaPin.started, arenaPin.ballPos, arenaPin.ballTime, arenaPin.challenger = true, nil, -math.huge, 0
	end
	arenaPin.time += dt
	local okKey, key = pcall(ArenaMap.locate, targetPos)
	if not okKey then key = nil end
	-- Once locked on an arena, a different answer is only believed while the target is really inside
	-- that other arena. A target standing just outside their own arena (a launch tube, a goal pocket)
	-- can be nearer to the arena next door, and that must not move the camera there.
	if not firstLock and arenaPin.key ~= nil and key ~= nil and key ~= arenaPin.key
		and (not pointInArena(key, targetPos, 0) or pointInArena(arenaPin.key, targetPos, 600)) then
		key = arenaPin.key
	end
	arenaPin.key = key

	-- resolved: the ball that belongs with the target right now.
	-- current:  the ball we were already following (matched by where it was last tick).
	local balls = getBalls()
	local anchor = arenaPin.ballPos or targetPos
	local resolved, resolvedDistance = nil, math.huge
	local current, currentDistance = nil, 1500
	for i = 1, #balls do
		local ball = balls[i]
		if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil and isLikelyArenaBall(ball) then
			local ballPos = ball.transform.position
			local qualifies = true
			if key ~= nil then
				-- Arena list available: only balls located in the target's arena qualify.
				local okBall, ballKey = pcall(ArenaMap.locate, ballPos)
				qualifies = okBall and ballKey == key
			end
			if qualifies then
				-- With an arena list any ball of that arena will do (prefer the one we follow);
				-- without one, "belongs with the target" means nearest to the target.
				local distance = safeDistance(ballPos, if key ~= nil then anchor else targetPos)
				if distance < resolvedDistance then resolved, resolvedDistance = ball, distance end
			end
			if arenaPin.ballPos ~= nil then
				local drift = safeDistance(ballPos, arenaPin.ballPos)
				if drift < currentDistance then current, currentDistance = ball, drift end
			end
		end
	end

	-- No arena list, and the ball that was being followed is gone: a ball somewhere else is not the
	-- next ball of this arena. Hold the shot first ("wait" below).
	if key == nil and current == nil and arenaPin.ballPos ~= nil and resolved ~= nil
		and safeDistance(resolved.transform.position, arenaPin.ballPos) > 1500 then
		resolved = nil
	end
	local best, switched = resolved, firstLock
	if current ~= nil then
		local same = resolved ~= nil and safeDistance(current.transform.position, resolved.transform.position) <= 1
		if same then
			arenaPin.challenger = 0
			best = current
		else
			-- The ball we follow is no longer the target's arena ball. Believe it only once it has
			-- stayed that way (1s with an arena list, 2s on distance alone).
			arenaPin.challenger += dt
			if arenaPin.challenger >= (if key ~= nil then 1 else 2) then
				arenaPin.challenger, switched = 0, true
				arenaPin.ballPos, arenaPin.ballTime = nil, -math.huge -- left that arena: no "wait" hold
				best = resolved
			else
				best = current
			end
		end
	else
		arenaPin.challenger = 0
	end

	-- First lock, or the target is now in another arena: if the camera is somewhere else, start
	-- from the target instead of flying across the map.
	if switched and safeDistance(camera.position, targetPos) > 3000 then
		local cameraElsewhere = true
		if key ~= nil then
			local okCamera, cameraKey = pcall(ArenaMap.locate, camera.position)
			cameraElsewhere = not (okCamera and cameraKey == key)
		end
		if cameraElsewhere and snapCameraToTarget(target) then
			simpleBallSmoothFocus, simpleBallSmoothBackDir, simpleBallCamCurrentBall = nil, nil, nil
		end
	end

	arenaPin.ball = best
	if best ~= nil then
		arenaPin.ballPos, arenaPin.ballTime = best.transform.position, arenaPin.time
		return "ball"
	end
	if arenaPin.ballPos ~= nil and arenaPin.time - arenaPin.ballTime <= (config.simpleBallCamArenaHoldSeconds or 8) then
		return "wait"
	end
	arenaPin.ballPos = nil
	return "target"
end

local function tickCamera(dt)
	local selectedTarget = findTargetPlayer()
	-- The server search just landed on the target's server: start from where they are.
	if TargetFinder.arrived and selectedTarget ~= nil and snapCameraToTarget(selectedTarget) then
		TargetFinder.arrived = false
		lastTargetId = nil -- full per-target smoothing reset on the next mode tick
		wasInsideArena = false
		goalRuntime.simpleActive = nil
		simpleBallSmoothFocus, simpleBallSmoothBackDir, simpleBallCamCurrentBall = nil, nil, nil
		arenaPin.started, arenaPin.ball = false, nil
	end
	-- Goal Explosion Test Cam is a test tool and takes the camera whatever the target is doing.
	if config.insideArenaMode == "Goal Explosion Test Cam" then
		if goalRuntime.simpleActive ~= nil then
			goalRuntime.simpleActive = nil -- the ball cams start fresh when the test cam is switched off
			simpleBallSmoothFocus, simpleBallSmoothBackDir, simpleBallCamCurrentBall = nil, nil, nil
			arenaPin.started, arenaPin.ball = false, nil
		end
		if goalRuntime.testCam(dt) then return end
	end
	-- Simple Ball Cam stays ball-only (no target, missing target, or target in an arena all run it).
	-- The one exception: a selected target who is present and OUTSIDE every arena gets the
	-- configured outside mode (SpecPet etc.) instead of having the ball cam steal the camera.
	local carrierMode = config.insideArenaMode == "Autocast - Ball Carrier"
	local goalCamMode = config.insideArenaMode == "Autocast - Simple Ball Cam + Goal Cam"
	local ballCamName = if carrierMode then "Ball Carrier" elseif goalCamMode then "Simple Ball Cam + Goal Cam" else "Simple Ball Cam"
	-- Zero-second / overtime goals: the game ends on the goal and the players are thrown out of
	-- the arena straight away. A ball cam that was already running stays on the goal until that
	-- goal's explosion has played out, and only then follows the target outside.
	-- (The hold has its own countdown, run in tick() every frame, so it always ends on time.)
	local holdLeft = goalRuntime.holdLeft or 0
	local explosionPlaying = holdLeft > 0 and config.customGoalExplosionsEnabled == true and config.goalExplosionHoldCamera ~= false
	goalRuntime.holdLeft = if explosionPlaying then holdLeft else 0
	local holdingForGoal = explosionPlaying and goalRuntime.simpleActive == true
		and selectedTarget ~= nil and not isArenaPlayer(selectedTarget)
	-- A note for the menu, so it is visible afterwards how a hold ended.
	if holdingForGoal then
		goalRuntime.wasHolding = true
		goalRuntime.holdNote = string.format("holding on the goal for the explosion, %.1fs left, then following %s", holdLeft, getPlayerName(selectedTarget))
	elseif goalRuntime.wasHolding then
		goalRuntime.wasHolding = false
		goalRuntime.holdNote = if selectedTarget == nil then "ended, but the target was no longer on this server by then, so there was nobody to follow (the camera stays on the ball cam; auto-follow will search for them)"
			elseif isArenaPlayer(selectedTarget) then "ended: the target is in an arena again"
			else "ended: now following " .. getPlayerName(selectedTarget) .. " outside the arena"
	end
	local simple = config.autoCasterEnabled and goalRuntime.ballCamModes[config.insideArenaMode] == true
		and (selectedTarget == nil or isArenaPlayer(selectedTarget) or holdingForGoal)
	if carrierMode ~= goalRuntime.carrierMode then
		goalRuntime.carrierMode = carrierMode
		goalRuntime.simpleActive = nil -- switching between the two ball cams resets their state too
	end
	if simple ~= goalRuntime.simpleActive then
		resetCarrierCam()
		simpleBallSmoothFocus, simpleBallSmoothBackDir, simpleBallCamCurrentBall = nil, nil, nil
		-- Entering/leaving the ball cam is an arena/mode change: drop stale follow state too.
		duckState.lastTargetPosition = nil
		duckState.leashActive = false
		freeCamInitialized = false
		graphicsTrail = {}
		goalRuntime.simpleActive = simple
		arenaPin.started, arenaPin.ball = false, nil
	end
	if not simple then
		arenaPin.started, arenaPin.ball = false, nil -- no ball cam running: the next one locks afresh
	end
	if simple then
		stopVlogBridge()
		wasInsideArena = false
		pcall(ArenaMap.refresh, dt)
		-- Goal cam: for the length of the goal explosion, sit out on the field in front of the
		-- scored-on goal so the whole goal (and the effect) is in shot.
		local goalCam = goalRuntime.goalCam
		if goalCam ~= nil then
			-- Plain Simple Ball Cam never cuts away; the "+ Goal Cam" mode always does.
			local wanted = goalCamMode or (carrierMode and config.goalCamEnabled ~= false)
			if wanted and goalRuntime.clock < goalCam.untilClock then
				camera.positionSmoothing = 0.02
				camera.rotationSmoothing = 0.02
				camera.fieldOfView = config.goalCamFov or 90
				camera.position = goalCam.position
				camera:lookAt(goalCam.look, goalCam.up)
				simpleBallSmoothFocus, simpleBallSmoothBackDir = nil, nil
				resetCarrierCam()
				statusText = ballCamName .. " | Goal cam, watching the goal"
				return
			end
			goalRuntime.goalCam = nil
		end
		-- Kickoff cam: from the moment the kickoff countdown shows until a little after GO, watch the
		-- kickoff spot (from the side, circling it, or from above). Same modes as the goal cam; plain
		-- Simple Ball Cam never cuts away. A goal cam that is still playing goes first.
		if (goalCamMode or (carrierMode and config.goalCamEnabled ~= false)) and config.kickoffCamEnabled ~= false
			and goalRuntime.kickoffShot(dt) then
			simpleBallSmoothFocus, simpleBallSmoothBackDir = nil, nil
			resetCarrierCam()
			if goalRuntime.ball ~= nil then renderStreamerGraphics(nil, goalRuntime.ball, dt) end -- ball trail / outline as usual
			statusText = ballCamName .. " | Kickoff cam (" .. tostring(config.kickoffCamStyle) .. ") | " .. Kickoff.status
			return
		end
		if holdingForGoal then
			-- No goal cam in this mode (plain Simple Ball Cam): keep the shot we have. Stay with the
			-- ball if it is still there, otherwise leave the camera exactly where it is.
			resetCarrierCam()
			if arenaPin.started and resolveLockedArenaBall(dt) == "ball" and followSimpleBallCam(dt) then
				goalRuntime.ball, goalRuntime.ballKnown = simpleBallCamCurrentBall, true
				renderStreamerGraphics(nil, simpleBallCamCurrentBall, dt)
			end
			statusText = ballCamName .. " | holding on the goal until the explosion finishes"
			return
		end
		-- A selected target who is in an arena pins the ball cam to THAT arena's ball. With no target
		-- to go by, it stays with the arena it is already casting.
		local targetHere = selectedTarget ~= nil and selectedTarget.root ~= nil and selectedTarget.root.position ~= nil
		local pinMode = nil
		if targetHere then pinMode = resolveTargetArenaBall(selectedTarget, dt) else pinMode = resolveLockedArenaBall(dt) end
		if pinMode == "target" then
			-- Their arena has no ball right now (pre-kickoff, or we just arrived): stay with the
			-- person so the camera is already in the right arena when the ball appears.
			simpleBallSmoothFocus, simpleBallSmoothBackDir, simpleBallCamCurrentBall = nil, nil, nil
			resetCarrierCam()
			if followThirdPersonHeadMovement(selectedTarget, dt) then
				statusText = ballCamName .. " | no ball in " .. getPlayerName(selectedTarget) .. "'s arena yet, staying with them"
			end
			return
		elseif pinMode == "wait" then
			-- The ball of the arena vanished (goal / reset / break): hold this shot.
			resetCarrierCam()
			statusText = ballCamName .. " | waiting for the ball in " .. (if targetHere then getPlayerName(selectedTarget) .. "'s arena"
				elseif arenaPin.key ~= nil then "arena " .. tostring(arenaPin.key) else "this arena")
			return
		end
		local followed = false
		if carrierMode then followed = followBallCarrierCam(dt) else followed = followSimpleBallCam(dt) end
		if followed then
			goalRuntime.ball, goalRuntime.ballKnown = simpleBallCamCurrentBall, true
			renderStreamerGraphics(nil, simpleBallCamCurrentBall, dt)
			local arenaNote = if pinMode ~= "ball" then "" elseif targetHere then " | " .. getPlayerName(selectedTarget) .. "'s arena"
				elseif arenaPin.key ~= nil then " | arena " .. tostring(arenaPin.key) else ""
			if carrierMode then
				statusText = "Ball Carrier | " .. carrierCam.label .. arenaNote
			else
				statusText = ballCamName .. " | Ball-only follow" .. arenaNote
			end
		else
			simpleBallSmoothFocus, simpleBallSmoothBackDir, simpleBallCamCurrentBall = nil, nil, nil
			runFreeCam(dt)
			statusText = ballCamName .. ": no ball | Free Cam"
		end
		return
	end
	local arenaTarget = findAutoCasterPlayer(selectedTarget)
	updateArenaLock(selectedTarget, arenaTarget)
	local insideArena = arenaTarget ~= nil
	local wasInside = wasInsideArena

	-- Edge trigger for the “someone entered arena” moment.
	if insideArena and not wasInside then
		duckState.lastTargetPosition = nil
		duckState.leashActive = false
		freeCamInitialized = false
		if config.insideArenaMode == "Fixed Camera" and config.fixedCamPosition ~= nil then
			local fixedPosition = configTableToVec3(config.fixedCamPosition)
			if fixedPosition ~= nil then
				camera.position = fixedPosition
			end
		end
	elseif wasInside and not insideArena then
		-- Cleanly release inside/autocast state so outside modes like SpecPet take over immediately.
		stopVlogBridge()
		vlogNativeGrabActive = false
		simpleBallSmoothFocus = nil
		simpleBallSmoothBackDir = nil
		simpleBallCamCurrentBall = nil
		graphicsTrail = {}
		duckState.lastTargetPosition = nil
		duckState.leashActive = false
		freeCamInitialized = false
		duckState.headpatCooldown = 0
		duckState.treatCooldown = 0
		duckState.feedTimer = 0
		duckState.feedCooldown = 0
	end
	wasInsideArena = insideArena

	if config.autoCasterEnabled and insideArena then
		runInsideMode(arenaTarget, dt)
		return
	end

	if selectedTarget == nil then
		duckState.lastTargetPosition = nil
		duckState.treatCooldown = 0
		duckState.feedTimer = 0
		duckState.feedCooldown = 0
		lastTargetId = nil
		simpleBallSmoothFocus = nil
		simpleBallSmoothBackDir = nil
		simpleBallCamCurrentBall = nil
		if runFreeCam(dt) then
			if hasSavedTargetSelection() then
				statusText = "Waiting for saved target to reappear: " .. (config.selectedTargetName or "selected player") .. " | Free Cam"
			else
				statusText = "No target: Free Cam"
			end
		end
		return
	end

	runOutsideMode(selectedTarget, dt)
end

function tick(dt)
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt == math.huge then return end
	-- A server change can leave this camera unselected. alwaysTick (same flag Caster/Follow+/august
	-- use) keeps tick running so the search can finish; camera work is skipped while inactive.
	local cameraActive = not (camera.isActive == false and camera.isFollowed ~= true)
	if cameraActive then
		goalRuntime.ball, goalRuntime.ballKnown = nil, false
		duckState.ranThisTick = false
		-- countdown for the zero-second / overtime goal hold (see tickCamera)
		goalRuntime.holdLeft = math.max((goalRuntime.holdLeft or 0) - math.min(dt, 0.25), 0)
		local cameraOK, cameraError = pcall(tickCamera, dt)
		-- A Kitty / Pidgeon that did not run this tick wakes up and drops its state.
		pcall(SpecPets.afterTick)
		-- Duckling face timer: runs every tick so the happy face always ends on time, and the
		-- standard face is restored if the Duckling stops while it is showing.
		if duckState.ranThisTick or duckState.faceHappy or (duckState.happyEmoteTimer or 0) > 0 then
			pcall(setDucklingNeutralFaceIfReady, dt)
		end
		local effectOK, effectError = pcall(goalRuntime.update, dt)
		if not effectOK then
			goalRuntime.clear(false)
			goalRuntime.status = "Goal system error: " .. tostring(effectError)
		end
		-- Kickoff countdown graphic (own guard: it can never interrupt the camera or the goal effects).
		local kickOK, kickError = pcall(goalRuntime.kickoff, dt)
		if not kickOK then
			pcall(Kickoff.stop)
			Kickoff.status = "Kickoff error: " .. tostring(kickError)
		end
		-- Send Overlay Info (optional, off by default). Own guard: a fault in it is logged once and
		-- can never interrupt the camera.
		if config.sendOverlayInfo == true then
			local overlayOK, overlayError = pcall(goalRuntime.overlay, dt)
			if not overlayOK then
				Overlay.status = "Error: " .. tostring(overlayError)
				if not goalRuntime.overlayLogged then
					goalRuntime.overlayLogged = true
					print("[Streamer Cam] Send Overlay Info error (logged once): " .. tostring(overlayError))
				end
			end
		end
		if not cameraOK then statusText = "Camera error: " .. tostring(cameraError) end
	end
	-- Experimental matchmaking-server search for the selected target. Own guard; no camera writes.
	local finderOK, finderError = pcall(TargetFinder.update, dt)
	if not finderOK then TargetFinder.fail(finderError) end
	if TargetFinder.state == "searching" then
		alwaysTick = true
	elseif not cameraActive then
		alwaysTick = nil
	end
end

local function combo(label, current, values)
	local changed = false

	if Gui.beginCombo(label, current) then
		for i = 1, #values do
			local value = values[i]

			if Gui.selectable(value, current == value) then
				current = value
				changed = true
			end
		end

		Gui.endCombo()
	end

	return current, changed
end

local function playerNameCombo(label, current)
	local changed = false
	local preview = current
	if preview == nil or preview == "" then
		preview = "Any / unassigned"
	end
	if Gui.beginCombo(label, preview) then
		if Gui.selectable("Any / unassigned", current == nil or current == "") then
			current = ""
			changed = true
		end
		local players = getPlayers()
		for i = 1, #players do
			local player = players[i]
			local name = getPlayerName(player)
			if name ~= nil and name ~= "" and Gui.selectable(name, current == name) then
				current = name
				changed = true
			end
		end
		Gui.endCombo()
	end
	return current, changed
end

local function snapToPlayerThirdPerson(player)
	local headPos = getHeadPosition(player)
	local headRot = getHeadRotation(player)

	if headPos == nil or headRot == nil then
		return
	end

	local upDir = getUpDir(player)
	local forward = safeNormalize(headRot:getForwardVector(), Vec3.forwardVector)
	camera.position = headPos + (forward * -config.thirdPersonDistance) + (upDir * config.thirdPersonHeight)
	camera:lookAt(headPos, upDir)
end

-- Saved choices from a list (an explosion, a colour, a trail style...) that are not on that list
-- go back to the default, so the menu never shows a name that does not exist.
do
	local function keep(key, list)
		for _, name in ipairs(list) do
			if name == config[key] then return end
		end
		config[key] = DEFAULTS[key]
	end
	keep("graphicsTargetMarkerShape", TARGET_MARKER_SHAPES)
	keep("graphicsBallTrailStyle", BALL_TRAIL_STYLES)
	keep("goalExplosionType", GOAL_EXPLOSION_TYPES)
	keep("goalExplosionFallbackType", GOAL_EXPLOSION_TYPES)
	for slot = 1, 5 do keep("goalExplosionAssignment" .. slot .. "Type", GOAL_EXPLOSION_TYPES) end
	keep("goalExplosionColorMode", GOAL_EXPLOSION_COLORS)
	keep("kickoffColorMode", GOAL_EXPLOSION_COLORS)
	keep("kickoffGraphicStyle", Kickoff.styleChoices)
	keep("visualFilterPreset", VISUAL_FILTER_PRESET_NAMES)
end

-- =========================
-- Menu
-- =========================
-- Sections are numbered so they are easy to point at. The everyday settings are at the top of
-- each section; anything called "fine tuning" can be left alone.
-- Every label in the menu is different on purpose: the menu tells its controls apart by label.

local Menu = {}

local function slider(label, key, low, high)
	config[key] = Gui.sliderFloat(label, config[key], low, high)
end

local function check(label, key)
	config[key] = Gui.checkbox(label, config[key])
end

local function choice(label, key, values)
	local value, changed = combo(label, config[key], values)
	if changed then config[key] = value end
	return changed
end

-- One line under each mode picker saying what the chosen mode does.
local MODE_NOTES = {
	["Third Person - Head Movement"] = "Behind the player, turning with their head.",
	["First Person POV"] = "Through the player's eyes.",
	["Vlog Camera (Follow+)"] = "Handheld camera from Follow+. The player can also grab the camera with a hand. Without Follow+ it is third person.",
	["Free Cam"] = "You fly the camera yourself (keyboard and mouse, or a controller).",
	["SpecPet"] = "The camera is a pet that follows the player around. Pick the pet in section 5.",
	["Third Person - Ball Look"] = "Behind the player, but looking toward the ball.",
	["Autocast - Simple Ball Cam"] = "Wide shot that follows the ball. No goal cam or kickoff cam cuts, so it is the safe one for clips.",
	["Autocast - Simple Ball Cam + Goal Cam"] = "Simple Ball Cam, plus a cut to the goal for each goal explosion and a kickoff shot.",
	["Autocast - Ball Carrier"] = "Player cam on whoever has the ball, ball cam while the ball is loose.",
	["Fixed Camera"] = "Stays at the spot you saved in section 3.",
	["Goal Explosion Test Cam"] = "Explosion preview is running (section 7). Stop it there to get this mode back.",
}

function Menu.target()
	local target = findTargetPlayer()
	local preview = if target ~= nil then getPlayerName(target) else "No player selected"

	targetSearch = Gui.inputText("Search player", targetSearch)

	if Gui.beginCombo("Target player", preview) then
		local players = getPlayers()

		for i = 1, #players do
			local player = players[i]
			local name = getPlayerName(player)

			local allowed = true
			if targetSearch ~= nil and targetSearch ~= "" then
				allowed = string.find(string.lower(name), string.lower(targetSearch), 1, true) ~= nil
			end

			if allowed and Gui.selectable(name, config.selectedTargetName == name) then
				config.selectedTargetName = name
				config.selectedTargetId = getPlayerId(player)
				duckState.lastTargetPosition = nil
				lastTargetId = config.selectedTargetId

				TargetFinder.rearm() -- picking a target (re)arms auto-follow for them
				if not (config.autoCasterEnabled and goalRuntime.ballCamModes[config.insideArenaMode] and isArenaPlayer(player)) then
					snapToPlayerThirdPerson(player)
				end

				saveSafe()
				statusText = "Target set: " .. name
			end
		end

		Gui.endCombo()
	end

	if Gui.button("Clear target") then
		config.selectedTargetName = ""
		config.selectedTargetId = nil
		duckState.lastTargetPosition = nil
		lastTargetId = nil
		saveSafe()
		statusText = "Target cleared."
	end
	Gui.text("The target is the player the camera follows. With no target the camera is a Free Cam (or the ball cam, if your inside mode is an Autocast one).")

	if Gui.collapsingHeader("Find the target on another server (experimental)") then
		Menu.serverSearch()
	end
end

-- Server search: hops the matchmaking servers until the target shows up in the player list.
function Menu.serverSearch()
	Gui.text("Moves your spectator from server to server until it finds the target. Experimental.")
	local finderName = config.selectedTargetName
	if finderName == nil or finderName == "" then finderName = targetSearch or "" end
	if TargetFinder.state == "searching" then
		Gui.text("Looking for " .. TargetFinder.name .. " | " .. TargetFinder.progressText() .. " | " .. TargetFinder.station .. ": " .. TargetFinder.phaseText())
		if Gui.button("Cancel server search") then TargetFinder.cancel() end
	elseif TargetFinder.state == "confirm" then
		Gui.text("This moves your spectator through " .. TargetFinder.planPreview() .. ", up to " .. tostring(TargetFinder.sweeps) .. " sweeps, looking for: " .. TargetFinder.name)
		if Gui.button("Yes, start searching") then TargetFinder.start(TargetFinder.name) end
		if Gui.button("Never mind") then TargetFinder.cancel() end
	else
		Gui.text("Uses the selected target's name, or the Search player text if none is selected.")
		if Gui.button("Find target's server") then TargetFinder.request(finderName) end
	end
	if TargetFinder.status ~= "" then Gui.text(TargetFinder.status) end
	-- Opt-in: follow the target between servers without clicking (queue into a match / back to the hub).
	local autoFollowServers = Gui.checkbox("Auto-follow target to their next server (experimental)", config.targetFinderAutoFollow)
	if autoFollowServers ~= config.targetFinderAutoFollow then
		config.targetFinderAutoFollow = autoFollowServers
		TargetFinder.rearm()
		saveSafe()
	end
	if config.targetFinderAutoFollow then
		slider("Seconds target must be gone before searching", "targetFinderAutoDelay", 3, 30)
		Gui.text("Armed as soon as a target is selected: if they are not on this server it searches.")
		Gui.text("Keeps going until it finds them, you press Stop, or it has swept every server " .. tostring(TargetFinder.sweeps) .. " times.")
	end
	slider("Highest Matchmaking server number to check", "targetFinderMaxServer", 5, 60)
	Gui.spacing()
	Gui.text("Faster search: only check the servers you actually queue on (for example the NA ones).")
	Gui.text("Type their numbers: 1, 2, 3  or  1-4  (0 = the server just called Matchmaking). Leave empty to check every server.")
	local typedList = Gui.inputText("Only check these Matchmaking numbers", config.targetFinderServerList)
	if type(typedList) == "string" and typedList ~= config.targetFinderServerList then
		config.targetFinderServerList = typedList
		saveConfig()
	end
	Gui.text("A search will check: " .. TargetFinder.planPreview())
	check("Check the servers this player is usually on first", "targetFinderFrequentFirst")
	local usualServers = if finderName ~= "" then TargetFinder.usualText(finderName) else ""
	if usualServers ~= "" then
		Gui.text(finderName .. " has been seen on: " .. usualServers .. ". A search asks for those first, most visits first, then the rest. Every server is still checked twice.")
	elseif finderName ~= "" then
		Gui.text("No servers remembered for " .. finderName .. " yet. Each matchmaking server they are seen on is counted from now on.")
	end
	if TargetFinder.seenPlayers() > 0 and Gui.button("Forget remembered servers") then TargetFinder.forgetSeen() end
	local leftOutServers = TargetFinder.avoidText()
	if leftOutServers ~= "" then
		Gui.text("Left out for 2 hours, because joining them threw the spectator out to the main menu: " .. leftOutServers)
		if Gui.button("Check those servers again") then TargetFinder.clearAvoid() end
	end
	slider("Extra seconds on each server before moving on", "targetFinderHopPause", 0, 20)
	Gui.text("Leave that at 0 unless the game throws you out after a few servers in a row. Then try 5 to 10.")
	if #TargetFinder.parseList(config.targetFinderServerList) > 0 then
		check("If they are not on my list after 2 sweeps, check the other servers once before giving up", "targetFinderListFallback")
		if Gui.button("Clear my list (check every server)") then
			config.targetFinderServerList = ""
			saveConfig()
		end
	end
	local loadedServers = TargetFinder.loadedText()
	if loadedServers ~= "" then
		Gui.text("Servers that actually loaded in recent searches: " .. loadedServers)
		if Gui.button("Use those as my list") then
			config.targetFinderServerList = loadedServers
			saveConfig()
		end
	end
	Gui.spacing()
	Gui.text("Order: every Matchmaking server once (one that will not load is skipped), then the home server, then every one again, then stop.")
	check("Shortcut: when the target leaves a match they were found in, check the home server first", "targetFinderHomeFirst")
	if #TargetFinder.log > 0 and Gui.collapsingHeader("Server search log") then
		Gui.text("Newest last:")
		for i = 1, #TargetFinder.log do Gui.text("  " .. TargetFinder.log[i]) end
	end
end

function Menu.modes()
	Gui.text("The camera can use one mode while the target is outside an arena and another while they are in one.")
	check("Switch to the inside mode when the target goes into an arena", "autoCasterEnabled")

	Gui.spacing()
	if choice("Outside an arena", "outsideArenaMode", OUTSIDE_MODES) then
		duckState.lastTargetPosition = nil
		duckState.leashActive = false
		freeCamInitialized = false
		vlogNativeGrabActive = false
		saveSafe()
		statusText = "Outside mode set: " .. config.outsideArenaMode
	end
	Gui.text("  " .. (MODE_NOTES[config.outsideArenaMode] or ""))

	Gui.spacing()
	if choice("Inside an arena", "insideArenaMode", INSIDE_MODES) then
		duckState.lastTargetPosition = nil
		duckState.leashActive = false
		freeCamInitialized = false
		wasInsideArena = false
		saveSafe()
		statusText = "Inside mode set: " .. config.insideArenaMode
	end
	Gui.text("  " .. (MODE_NOTES[config.insideArenaMode] or ""))
	Gui.text("The three Autocast modes also work with no target: they take the arena whose ball is nearest the camera and stay with it.")
end

function Menu.camera()
	slider("Camera FOV", "cameraFov", 60, 130)
	slider("Snap distance (farther than this, the camera jumps instead of gliding)", "snapDistance", 100, 5000)
	Gui.text("Camera FOV is for the follow modes, Fixed Camera and Free Cam. The ball cams, goal cam and kickoff cam have their own.")

	if Gui.collapsingHeader("Third person") then
		slider("Third person distance", "thirdPersonDistance", 40, 300)
		slider("Third person height", "thirdPersonHeight", -20, 140)
		slider("Third person follow speed", "followSpeed", 1, 40)
	end

	if Gui.collapsingHeader("First person") then
		slider("First person forward offset", "firstPersonForwardOffset", -10, 20)
		slider("First person height offset", "firstPersonHeightOffset", -20, 40)
		slider("First person follow speed", "firstPersonSpeed", 1, 50)
	end

	if Gui.collapsingHeader("Third Person - Ball Look") then
		slider("Ball look distance", "ballLookDistance", 60, 400)
		slider("Ball look height", "ballLookHeight", -20, 180)
		slider("Ball look follow speed", "ballLookSpeed", 1, 50)
	end

	if Gui.collapsingHeader("Fixed Camera") then
		Gui.text("Fly somewhere with Free Cam, then save the view. Fixed Camera mode stays there.")
		if Gui.button("Save current view as fixed camera") then
			storeFixedCameraHere()
		end
		if Gui.button("Jump to saved fixed camera") then
			local fixedPosition = configTableToVec3(config.fixedCamPosition)
			local fixedRotation = configTableToQuat(config.fixedCamRotation)
			if fixedPosition ~= nil then
				camera.position = fixedPosition
				if fixedRotation ~= nil then
					camera.rotation = fixedRotation
				end
				statusText = "Jumped to saved fixed camera."
			else
				statusText = "No fixed camera saved yet."
			end
		end
		check("Fixed camera looks at ball", "fixedCamLookAtBall")
	end

	if Gui.collapsingHeader("Which ball the follow modes use") then
		Gui.text("For Third Person - Ball Look, a Fixed Camera that looks at the ball, and the ball outline and trail in the follow modes.")
		Gui.text("(The ball cams do not use this. They stay with one arena: see section 4.)")
		check("Only use balls near the target (ignores balls in other arenas)", "autoCastLockToSelectedArena")
		slider("How near the target a ball must be", "autoCastArenaLockRadius", 500, 3500)
		slider("Seconds to remember that spot after the target disappears", "autoCastArenaLockGraceSeconds", 0, 20)
	end

	if Gui.collapsingHeader("Free Cam") then
		Gui.text("Keyboard: W A S D move, Space up, Ctrl down, Shift fast, Alt slow, mouse looks around.")
		Gui.text("Controller: left stick moves, right stick looks, right trigger up, left trigger down, RB fast, LB slow.")
		slider("Free cam move speed", "freeCamMoveSpeed", 50, 2500)
		slider("Free cam sprint multiplier", "freeCamSprintMultiplier", 1, 8)
		slider("Free cam slow multiplier", "freeCamSlowMultiplier", 0.05, 1)
		slider("Free cam look sensitivity", "freeCamLookSensitivity", 0.02, 0.5)
		check("Free cam no-clip through barriers", "freeCamNoClip")
		check("Free cam collision safety (only when no-clip is off)", "freeCamCollisionSafety")
		Gui.text("To make Free Cam stop at walls: untick no-clip AND tick collision safety.")
		if Gui.collapsingHeader("Free Cam fine tuning") then
			slider("Free cam controller look speed", "freeCamControllerLookSpeed", 20, 360)
			slider("Free cam controller move multiplier", "freeCamControllerMoveMultiplier", 0.1, 3)
			slider("Free cam controller deadzone", "freeCamControllerDeadzone", 0, 0.5)
			check("Invert controller Y look", "freeCamInvertControllerY")
			check("Invert left-stick forward/back", "freeCamInvertControllerMoveY")
			check("Left stick moves toward camera view", "freeCamControllerForwardUsesCameraFacing")
			check("Keyboard uses arena floor axis", "freeCamGroundPlaneMovement")
			check("Free cam follows gravity areas", "freeCamGravityAlignedLook")
			slider("Free cam gravity reset speed", "freeCamGravityChaseSpeed", 0.5, 20)
		end
	end

	if Gui.collapsingHeader("Vlog Camera (Follow+)") then
		if refreshFollowPlusBridge() ~= nil then
			Gui.text("Follow+ detected" .. (followPlusVersion ~= "" and (" v" .. followPlusVersion) or ""))
		else
			Gui.text("Follow+ is not installed or not found: this mode uses third person instead.")
		end
		check("Use Follow+ for the vlog camera (reload the camera after changing this)", "vlogFollowPlusEnabled")
		check("Let the target grab the camera with a hand", "vlogNativeGrabEnabled")
		check("Held vlog cam looks at target", "vlogGrabLookAtTarget")
		slider("Vlog FOV", "vlogFov", 60, 130)
		if Gui.collapsingHeader("Vlog Camera fine tuning") then
			slider("Vlog grab radius", "vlogGrabRadius", 10, 120)
			slider("Vlog release radius", "vlogGrabReleaseRadius", 20, 200)
			slider("Vlog follow radius", "vlogFollowRadius", 5, 100)
			slider("Vlog smoothing", "vlogFollowSmoothing", 0.01, 0.5)
		end
	end
end

function Menu.ballCams()
	Gui.text("Simple Ball Cam: a wide shot that follows the ball.")
	slider("Simple ball distance", "simpleBallCamDistance", 200, 1400)
	slider("Simple ball height", "simpleBallCamHeight", 50, 700)
	slider("Simple ball FOV", "simpleBallCamFov", 70, 125)
	slider("Simple ball follow speed", "simpleBallCamFollowSpeed", 2, 45)
	check("Keep ball cams inside the arena (never behind a goal)", "ballCamStayInArena")
	if Gui.collapsingHeader("Simple Ball Cam fine tuning") then
		slider("Simple ball lead", "simpleBallCamLead", 0, 0.8)
		slider("Simple ball smoothing", "simpleBallCamFocusSmoothSpeed", 0.5, 20)
		slider("Simple ball direction smoothing", "simpleBallCamDirectionSmoothSpeed", 0.5, 20)
		slider("Simple ball base max speed", "simpleBallCamMaxStepPerSecond", 500, 9000)
		slider("Simple ball catch-up starts", "simpleBallCamCatchupStartDistance", 50, 1200)
		slider("Simple ball catch-up ramp", "simpleBallCamCatchupMultiplier", 0, 30)
		slider("Simple ball catch-up max speed", "simpleBallCamMaxCatchupStepPerSecond", 1000, 18000)
		slider("Simple ball catch-up follow boost", "simpleBallCamCatchupSmoothBoost", 0, 80)
	end

	Gui.spacing()
	Gui.text("Ball Carrier: player cam on whoever has the ball, ball cam when it is loose.")
	slider("Carrier cam distance", "carrierCamDistance", 80, 600)
	slider("Carrier cam height", "carrierCamHeight", 0, 300)
	if Gui.collapsingHeader("Ball Carrier fine tuning") then
		slider("Has-the-ball distance (hand/head to ball)", "carrierContactDistance", 20, 90)
		slider("Hold time before cutting to the carrier", "carrierHoldSeconds", 0.1, 1.5)
		slider("Loose time before cutting back to the ball", "carrierLooseSeconds", 0.1, 1.5)
	end

	Gui.spacing()
	Gui.text("Goal cam: a view of the whole goal while a goal explosion plays (goal explosions must be on).")
	Gui.text("'Simple Ball Cam + Goal Cam' always uses it. Plain 'Simple Ball Cam' never does.")
	check("Goal cam in Ball Carrier", "goalCamEnabled")
	slider("Goal cam distance out from the goal", "goalCamDistance", 300, 2500)
	slider("Goal cam height", "goalCamHeight", 100, 1200)
	slider("Goal cam FOV", "goalCamFov", 60, 120)
	check("0-second / overtime goals: finish the explosion before following the target out of the arena", "goalExplosionHoldCamera")
	slider("...but never hold longer than this many seconds", "goalExplosionHoldMaxSeconds", 1, 6)

	if Gui.collapsingHeader("Staying in one arena") then
		Gui.text("The ball cams stay with ONE arena: the target's arena, or with no target the arena they started in.")
		Gui.text("While that arena has no ball (after a goal, between rounds) the camera waits there. It never goes to another arena's ball.")
		Gui.text("To move a no-target ball cam to another arena: pick a target there, or set the inside mode to Free Cam, fly over and set it back.")
		slider("Seconds an empty arena is kept before the ball cam looks for another one", "ballCamArenaReleaseSeconds", 5, 600)
		Gui.text("Empty = no ball, no round running and nobody on a team left in it.")
	end
end

function Menu.specPet()
	Gui.text("Pick 'SpecPet' as the outside (or inside) mode in section 2, then choose the pet here.")
	local petChoice, petChanged = combo("SpecPet pet", config.specPetType, { "Duckling", SpecPets.kinds[1], SpecPets.kinds[2] })
	if petChanged then
		config.specPetType = petChoice
		saveConfig()
	end
	if config.specPetType == "Duckling" then
		Gui.text("Duckling: Streamer Cam's own pet. Waddles behind you, stays calm when you turn round, likes pats and treats.")
	elseif config.specPetType == "Kitty" then
		Gui.text("Kitty (Layna's Spectator Pet): sits and watches you, pads over when you get more than 200 away.")
	else
		Gui.text("Pidgeon (Layna's Spectator Pet): flies at your right shoulder. Right trigger with your right hand on it picks it up.")
	end
	check("Everyone can pet / feed it (off = only the player it follows)", "ducklingInteractEveryone")

	if config.specPetType ~= "Duckling" then
		if SpecPets.label ~= "" then Gui.text("Now: " .. SpecPets.label) end
		Gui.text("Kitty and Pidgeon are ported from lovelyylayna.specpet 0.0.3 by LovelyyLayna.")
		slider("Pet speed", "specPetSpeed", 0.5, 12)
		check("Walk / flap bob", "specPetWalkCycle")
		slider("Kitty step height", "specPetWalkHeight", 0, 80)
		check("Head pats (happy face for 3 seconds)", "specPetHeadpats")
		check("Falls asleep when you stand still", "specPetRest")
		slider("Seconds standing still before it sleeps", "specPetRestSeconds", 2, 60)
		check("Eats driftballs that are lying nearby", "specPetEatBalls")
		return
	end

	slider("Duckling follow-behind distance", "ducklingDistance", 40, 220)
	slider("Duckling calm range (only moves when you get farther than this)", "ducklingFollowLeashDistance", 80, 600)
	slider("Duckling height", "ducklingHeight", 0, 50)
	slider("Duckling follow speed", "ducklingSpeed", 1, 30)
	check("Duckling headpat face/wiggle", "ducklingHeadpatsEnabled")
	check("Duckling heart-ball treats", "ducklingTreatsEnabled")
	check("Hand feeding (hold the ball up to it)", "ducklingFeedingEnabled")
	if Gui.collapsingHeader("Duckling fine tuning") then
		slider("Duckling personal space", "ducklingPersonalSpace", 30, 160)
		slider("Face-to-face hold after pet/feed", "ducklingFacePetHoldSeconds", 0.2, 4)
		slider("Face hold max player speed", "ducklingFacePlayerSpeed", 0, 250)
		slider("Duckling hand/headpat radius", "ducklingHeadpatRadius", 10, 60)
		slider("Headpat release grace", "ducklingHeadpatReleaseGrace", 0, 1)
		slider("Happy face hold after the last pat", "ducklingHappyEmoteHoldSeconds", 0.5, 8)
		slider("Treat: ball must be this close to the duckling", "ducklingTreatRadius", 10, 45)
		slider("Treat reaction cooldown", "ducklingTreatCooldown", 0.5, 8)
		check("Treat requires hand near heartball", "ducklingTreatRequireHandNear")
		slider("Treat: hand must be this close to the ball", "ducklingFeedingHandRadius", 10, 45)
		slider("Feeding happy duration", "ducklingFeedingDuration", 0.3, 3)
		slider("Duckling wiggle duration", "ducklingRuffleDuration", 0.2, 2)
		slider("Duckling wiggle speed", "ducklingRuffleSpeed", 10, 90)
		slider("Duckling wiggle amount", "ducklingRuffleMaxTilt", 0.05, 0.6)
	end
end

function Menu.graphics()
	check("Enable graphics", "graphicsEnabled")
	Gui.text("Graphics are drawn while the target is in an arena, and in the ball cams. The ball cams only draw the ball outline and trail.")
	Gui.spacing()
	check("Ball outline", "graphicsBallOutlineEnabled")
	slider("Ball outline size", "graphicsBallOutlineSize", 0.5, 3)
	slider("Ball outline thickness", "graphicsBallOutlineThickness", 0.5, 8)
	Gui.spacing()
	check("Ball trail", "graphicsBallTrailEnabled")
	choice("Ball trail style", "graphicsBallTrailStyle", BALL_TRAIL_STYLES)
	slider("Ball trail fade time (seconds; 0.03 = a tiny stub behind the ball)", "graphicsTrailDuration", 0.03, 5)
	slider("Ball trail thickness", "graphicsTrailThickness", 0.5, 18)
	check("Ball trail color by speed", "graphicsBallTrailSpeedColorEnabled")
	Gui.spacing()
	check("Target marker", "graphicsTargetMarkerEnabled")
	choice("Target marker shape", "graphicsTargetMarkerShape", TARGET_MARKER_SHAPES)
	slider("Target marker size", "graphicsTargetMarkerSize", 5, 50)
	check("Line from target to ball", "graphicsLineToBallEnabled")
	Gui.spacing()
	check("Team markers (a marker over each player who is on a team)", "graphicsTeamMarkersEnabled")
	check("Only mark the target's team", "graphicsTeamMarkersSameTeamOnly")
	check("Also mark target player", "graphicsTeamMarkersShowTarget")
	check("Unique teammate colors", "graphicsTeamMarkersUniqueColors")
	slider("Team marker size", "graphicsTeamMarkerSize", 5, 40)
	slider("Team marker height", "graphicsTeamMarkerHeight", 25, 120)
	if Gui.collapsingHeader("Graphics fine tuning") then
		slider("Graphics vibrance", "graphicsVibrance", 0.2, 3)
		slider("Trail core width", "graphicsBallTrailCoreWidth", 0.15, 1.5)
		slider("Trail glow width", "graphicsBallTrailGlowWidth", 1.0, 4.0)
		slider("Trail blue/slow speed", "graphicsBallTrailBlueSpeed", 0, 1500)
		slider("Trail red/fast speed", "graphicsBallTrailRedSpeed", 500, 5000)
		slider("Graphics draw lifetime", "graphicsDrawLifetime", 0.01, 0.5)
		check("Clear old graphics before drawing", "graphicsClearBeforeDraw")
	end
end

-- Plays the chosen explosion as a test goal for one side.
local function testExplosion(teamIndex)
	config.customGoalExplosionsEnabled = true
	goalRuntime.pendingTest = { teamIndex = teamIndex, effectType = config.goalExplosionType, colorMode = if teamIndex == 1 then "Orange" else "Blue" }
end

function Menu.goalExplosions()
	Gui.text("Extra effects drawn by this camera when a goal is scored. Only people watching this camera see them.")
	check("Enable goal explosions", "customGoalExplosionsEnabled")
	if not config.customGoalExplosionsEnabled then goalRuntime.clear(true) end
	Gui.text("Arena: " .. tostring(GoalContext.status))
	Gui.text("Last: " .. tostring(goalRuntime.status))

	local newFallbackType, fallbackTypeChanged = combo("Explosion for every goal", config.goalExplosionFallbackType, GOAL_EXPLOSION_TYPES)
	if fallbackTypeChanged then
		config.goalExplosionFallbackType = newFallbackType
		config.goalExplosionType = newFallbackType
	end
	choice("Goal explosion color", "goalExplosionColorMode", GOAL_EXPLOSION_COLORS)
	if config.goalExplosionColorMode == "Custom RGB" or config.kickoffColorMode == "Custom RGB" then
		slider("Custom explosion red", "goalExplosionCustomR", 0, 1)
		slider("Custom explosion green", "goalExplosionCustomG", 0, 1)
		slider("Custom explosion blue", "goalExplosionCustomB", 0, 1)
	end

	if Gui.collapsingHeader("Preview explosions") then
		local testing = config.insideArenaMode == "Goal Explosion Test Cam"
		Gui.text("Pick an explosion and press a Test button. It plays in the arena the camera is in.")
		choice("Explosion to test", "goalExplosionType", GOAL_EXPLOSION_TYPES)
		if Gui.button("Test Blue Explosion") then testExplosion(0) end
		if Gui.button("Test Orange Explosion") then testExplosion(1) end
		Gui.spacing()
		Gui.text("Preview camera: parks the camera in front of a goal so you can see the whole thing.")
		Gui.text("While it is on it ignores the target. Fly into an arena first if it says it cannot find one.")
		if not testing then
			if Gui.button("Start preview camera") then
				config.goalTestPreviousMode = config.insideArenaMode
				config.insideArenaMode = "Goal Explosion Test Cam"
				config.customGoalExplosionsEnabled = true
				saveConfig()
			end
		else
			local back = if type(config.goalTestPreviousMode) == "string" and config.goalTestPreviousMode ~= "Goal Explosion Test Cam" then config.goalTestPreviousMode else "Autocast - Simple Ball Cam"
			if Gui.button("Stop preview camera (back to " .. back .. ")") then
				config.insideArenaMode = back
				config.goalTestLoop = false
				saveConfig()
			end
		end
		local sideNames = { "Blue scores", "Orange scores" }
		local testSide, testSideChanged = combo("Which goal the preview camera faces", sideNames[(config.goalTestSide or 0) + 1], sideNames)
		if testSideChanged then config.goalTestSide = if testSide == sideNames[2] then 1 else 0 end
		local fire, step = Gui.button("Test on the preview side"), 0
		if Gui.button("Next explosion + test") then step = 1 end
		if Gui.button("Previous explosion + test") then step = -1 end
		if step ~= 0 then
			local index = 1
			for i, name in ipairs(GOAL_EXPLOSION_TYPES) do
				if name == config.goalExplosionType then index = i end
			end
			config.goalExplosionType = GOAL_EXPLOSION_TYPES[((index - 1 + step) % #GOAL_EXPLOSION_TYPES) + 1]
			fire = true
		end
		if fire then testExplosion(config.goalTestSide or 0) end
		check("Keep replaying it (preview camera only)", "goalTestLoop")
		Gui.text("Now: " .. tostring(config.goalExplosionType) .. " | " .. tostring(config.goalExplosionColorMode))
		Gui.text("Explosions that play where the ball is (Implosion, Tornado, Lightning Strike, Airstrike...) use the arena's ball if there is one, else the middle of the goal.")
	end

	if Gui.collapsingHeader("Give a player their own explosion") then
		Gui.text("Up to five players. When one of them scores, their explosion plays instead of the one for every goal.")
		Gui.text("Who scored is worked out from the last touches on the ball, so now and then the wrong explosion plays.")
		for slot = 1, 5 do
			local playerKey = "goalExplosionAssignment" .. slot .. "Player"
			local typeKey = "goalExplosionAssignment" .. slot .. "Type"
			local assignedPlayer, playerChanged = playerNameCombo("Player " .. slot, config[playerKey])
			if playerChanged then config[playerKey] = assignedPlayer end
			choice("Player " .. slot .. " explosion", typeKey, GOAL_EXPLOSION_TYPES)
		end
		Gui.text("Last goal: " .. GoalContext.lastGoal .. " | scored by (best guess): " .. GoalContext.scorer)
		slider("How close a hand or head must get to count as a touch", "goalExplosionTouchRadius", 30, 220)
	end

	if Gui.collapsingHeader("Explosion size and detail") then
		slider("Explosion vibrance", "goalExplosionVibrance", 0.5, 2)
		slider("Explosion lifetime (seconds; the long animated explosions keep their own length)", "goalExplosionLifetime", 0.35, 2.5)
		Gui.text("Basic Burst and Caster Burst:")
		slider("Explosion particle/detail count", "goalExplosionParticleCount", 12, 120)
		check("Use Caster particle system for Caster Burst", "goalExplosionUseCasterParticles")
		Gui.text("Caster Burst needs that ticked. Without it a goal plays Basic Burst instead.")
		Gui.text("Ripple Wave (it always draws at least 3 rings; the ring count is also used by Caster Burst):")
		slider("Explosion ring count", "goalExplosionRingCount", 1, 5)
		slider("Ripple max radius", "goalExplosionRippleMaxRadius", 80, 1200)
		slider("Ripple line thickness", "goalExplosionRippleThickness", 1, 16)
		slider("Ripple vertical spacing", "goalExplosionRippleRise", 0, 40)
		check("Only play explosions in the arena the camera is watching", "goalExplosionOnlyClosestArena")
		if Gui.button("Clear/Reset Effects") then
			goalRuntime.clear(true)
			goalRuntime.status = "Effects reset; next score sample will baseline"
		end
	end
end

function Menu.kickoff()
	Gui.text("A countdown graphic around the ball at kickoff, and a kickoff shot for the goal-cam autocasts.")
	check("Kickoff graphics (every camera mode)", "kickoffGraphicsEnabled")
	choice("Kickoff graphic", "kickoffGraphicStyle", Kickoff.styleChoices)
	check("Show the 3-2-1 numbers and GO!", "kickoffShowNumbers")
	choice("Kickoff colours (Team Color = each team's own colour on its side)", "kickoffColorMode", GOAL_EXPLOSION_COLORS)
	if config.kickoffColorMode == "Custom RGB" then Gui.text("Custom RGB uses the three colour sliders in section 7.") end
	slider("Show the last this-many seconds of the countdown", "kickoffCountdownSeconds", 1, 15)
	slider("Kickoff graphic size", "kickoffGraphicScale", 0.4, 2.5)
	Gui.text("Kickoff = the launch at the start of a round. Timers in the middle of a round are ignored.")
	check("Also treat mid-round timers as kickoffs (after a goal, ball back in the middle)", "kickoffEveryCountdown")
	Gui.spacing()
	Gui.text("Kickoff cam: 'Simple Ball Cam + Goal Cam' uses it, and Ball Carrier while its goal cam is on.")
	Gui.text("Plain 'Simple Ball Cam' never cuts away (it still gets the graphic).")
	check("Kickoff cam", "kickoffCamEnabled")
	choice("Kickoff cam shot", "kickoffCamStyle", Kickoff.camStyles)
	slider("Kickoff cam distance from the spot (orbit radius)", "kickoffCamDistance", 400, 4000)
	slider("Kickoff cam height above the spot", "kickoffCamHeight", 0, 1500)
	slider("Kickoff cam FOV", "kickoffCamFov", 50, 125)
	slider("Orbit speed (degrees per second, negative = other way)", "kickoffCamOrbitSpeed", -90, 90)
	slider("Stay on the kickoff cam this long after GO", "kickoffCamAfterGoSeconds", 0, 6)
	Gui.spacing()
	local kickTest = Gui.button("TEST KICKOFF (3 second countdown)")
	if Gui.button("Next graphic + test") then
		local index = 1
		for i, name in ipairs(Kickoff.styles) do
			if name == config.kickoffGraphicStyle then index = i end
		end
		config.kickoffGraphicStyle = Kickoff.styles[(index % #Kickoff.styles) + 1]
		kickTest = true
	end
	if kickTest then
		config.kickoffGraphicsEnabled = true
		Kickoff.test(3)
	end
	Gui.text("The test plays in the arena the camera is in. To see it from the kickoff cam, be in a goal-cam autocast or the explosion preview camera.")
	Gui.text("Now: " .. tostring(Kickoff.status))
end

local function setPunchyPicture()
	config.visualSettingsEnabled = true
	config.visualFilterPreset = "Punchy Broadcast"
	config.visualShaderStrength = 1
	config.visualUsePresetFov = true
	config.visualUsePresetGraphics = true
	config.visualApplyEnginePostProcessing = true
	config.visualExposure = 1.15
	config.visualGamma = 0.9
	config.visualContrast = 1.35
	config.visualSaturation = 1.45
	config.visualBloom = 1.0
	config.visualVignette = 0.12
	config.visualChromaticAberration = 0
	config.visualMotionBlur = 0
	config.visualFilmGrain = 0
	config.visualSharpness = 0.25
	config.visualTemperature = 0
	config.visualTint = 0
end

local function setNeutralPicture()
	config.visualFilterPreset = "Custom"
	config.visualShaderStrength = 1
	config.visualUsePresetFov = false
	config.visualUsePresetGraphics = false
	config.visualApplyEnginePostProcessing = false
	visualEffectiveFov = nil
	config.visualExposure = 0
	config.visualGamma = 1
	config.visualContrast = 1
	config.visualSaturation = 1
	config.visualBloom = 0
	config.visualVignette = 0
	config.visualChromaticAberration = 0
	config.visualMotionBlur = 0
	config.visualFilmGrain = 0
	config.visualSharpness = 0
	config.visualTemperature = 0
	config.visualTint = 0
end

function Menu.picture()
	Gui.text("Changes the look of the picture: bloom, vignette, exposure and so on. Off until you tick it. Experimental.")
	Gui.text("It is sent to the game in the follow modes, Free Cam and Fixed Camera. The ball cams do not send it.")
	check("Enable picture filter", "visualSettingsEnabled")
	local newFilterPreset, filterPresetChanged = combo("Filter preset", config.visualFilterPreset, VISUAL_FILTER_PRESET_NAMES)
	if filterPresetChanged then
		config.visualFilterPreset = newFilterPreset
		config.visualSettingsEnabled = true
		saveSafe()
		statusText = "Picture filter set: " .. newFilterPreset
	end
	slider("Filter strength", "visualShaderStrength", 0, 1)
	check("Preset also sets the camera FOV (it then overrides Camera FOV in section 3)", "visualUsePresetFov")
	check("Preset also sets graphics vibrance and ball trail thickness (it then overrides those two sliders in section 6)", "visualUsePresetGraphics")
	check("Use the game's post-processing (needed for bloom, vignette and exposure)", "visualApplyEnginePostProcessing")
	Gui.text("Filter: " .. (if not config.visualSettingsEnabled then "off" elseif visualStatus == "applied" then "has been sent to the game" else "not sent to the game yet"))
	if visualEffectiveFov ~= nil then
		Gui.text("FOV from the preset right now: " .. string.format("%.1f", visualEffectiveFov))
	end
	if config.visualFilterPreset ~= "Custom" then
		Gui.text("A preset is picked, so it sets these values. Pick 'Custom' to use the sliders.")
	end
	slider("Exposure", "visualExposure", -10, 10)
	slider("Bloom", "visualBloom", 0, 10)
	slider("Vignette", "visualVignette", 0, 2)
	slider("Chromatic aberration", "visualChromaticAberration", 0, 2)
	slider("Motion blur", "visualMotionBlur", 0, 1)
	if Gui.collapsingHeader("More picture sliders (these may do nothing in the current game build)") then
		Gui.text("The five sliders above use settings the game is known to have. These seven are sent too, but may be ignored.")
		slider("Gamma", "visualGamma", 0.2, 3)
		slider("Contrast", "visualContrast", 0, 5)
		slider("Saturation", "visualSaturation", 0, 5)
		slider("Film grain", "visualFilmGrain", 0, 1)
		slider("Sharpness", "visualSharpness", 0, 2)
		slider("Temperature", "visualTemperature", -1, 1)
		slider("Tint", "visualTint", -1, 1)
	end
	if Gui.button("Punchy broadcast preset") then
		setPunchyPicture()
		saveSafe()
		statusText = "Punchy picture preset saved."
	end
	if Gui.button("Reset the picture sliders") then
		setNeutralPicture()
		saveSafe()
		statusText = "Picture sliders reset."
	end
	Gui.text("Streamer Cam does not put the game's own picture back. If it still looks filtered with the filter off, restart the spectator.")
end

function Menu.overlay()
	Gui.text("Sends match data (arena, rosters, rounds, overtime...) so OD Caster Bridge overlays can run from Streamer Cam.")
	Gui.text("In the bridge, set the Camera API box to: duckyinvr.streamercam.public")
	local sendOverlay = Gui.checkbox("Send Overlay Info", config.sendOverlayInfo == true) == true
	if sendOverlay ~= (config.sendOverlayInfo == true) then
		config.sendOverlayInfo = sendOverlay
		if not sendOverlay then
			config.api, config.apiHeld = nil, nil
			Overlay.reset()
		end
		saveSafe() -- one save on the click, so the choice itself sticks
	end
	check("Stop sending a match once it is over and the arena has emptied (or the camera has left it)", "overlayClearAfterMatch")
	Gui.text("That takes the scoreboard data down about 3 seconds after everybody is out. It comes back when a round runs there again.")
	check("Send 'no arena' while the camera is outside every arena (the hub, a lobby)", "overlayClearOutsideArena")
	slider("Seconds outside every arena before that happens", "overlayOutsideSeconds", 0.5, 10)
	slider("How far outside an arena still counts as inside (100 = 1 metre)", "overlayOutsideMargin", 0, 6000)
	Gui.text("Overlays then go to standby instead of keeping the last arena up. It never happens while a ball cam or a player cam is casting an arena, and the arena's data is back the moment the camera is.")
	if config.sendOverlayInfo then Gui.text("Camera: " .. tostring(Overlay.cameraNote)) end
	Gui.text("While it is on, the settings file is saved about 20 times a second (that is how the bridge reads the data).")
	Gui.text("Overlay: " .. tostring(if config.sendOverlayInfo then Overlay.status else "Off"))
	if config.sendOverlayInfo then Gui.text("Last goal credited to: " .. tostring(Overlay.lastGoal)) end
	Gui.text("Possession, passes, shots, saves, assists, shot speed and boost are estimates worked out from player and ball movement.")
end

function Menu.about()
	Gui.text("Streamer Cam " .. VERSION .. " (public release), by duckyinvr.")
	Gui.text("Uses material from Caster Camera by Dennssen (MIT licence).")
	Gui.text("Vlog Camera runs on Follow+ by Dennssen when it is installed.")
	Gui.text("Kitty and Pidgeon are from Layna's Spectator Pet by LovelyyLayna.")
	Gui.text("Server search uses the approach from august.matchmaker.")
	Gui.text("Most of the code was written with AI assistance. Full credits and how-to: README.md.")
end

function onGui()
	Gui.text("Streamer Cam " .. VERSION)
	Gui.text("Pick a player in section 1 and your camera modes in section 2. Everything else is optional.")
	Gui.spacing()
	Gui.separator()
	Gui.spacing()

	Gui.text("Status: " .. statusText)
	if TargetFinder.state == "searching" then
		Gui.text("Server search: " .. TargetFinder.name .. " | " .. TargetFinder.progressText() .. " | " .. TargetFinder.station .. ": " .. TargetFinder.phaseText())
		if Gui.button("Stop server search") then TargetFinder.cancel() end
	elseif TargetFinder.status ~= "" then
		Gui.text("Server search: " .. TargetFinder.status)
	end
	if config.targetFinderAutoFollow then
		Gui.text("Auto-follow: " .. TargetFinder.autoText())
	end
	if Gui.button("Save settings") then
		saveSafe()
		statusText = "Settings saved."
	end
	Gui.text("Sliders and checkboxes are kept for next time when you press Save settings.")
	Gui.spacing()

	if Gui.collapsingHeader("1. Target player") then Menu.target() end
	if Gui.collapsingHeader("2. Camera modes") then Menu.modes() end
	if Gui.collapsingHeader("3. Camera settings") then Menu.camera() end
	if Gui.collapsingHeader("4. Ball cams and goal cam") then Menu.ballCams() end
	if Gui.collapsingHeader("5. SpecPet (a pet that follows the target)") then Menu.specPet() end
	if Gui.collapsingHeader("6. Graphics (ball outline, ball trail, markers)") then Menu.graphics() end
	if Gui.collapsingHeader("7. Goal explosions") then Menu.goalExplosions() end
	if Gui.collapsingHeader("8. Kickoff graphics and kickoff cam") then Menu.kickoff() end
	if Gui.collapsingHeader("9. Picture filter") then Menu.picture() end
	if Gui.collapsingHeader("10. Overlay data for OD Caster Bridge") then Menu.overlay() end
	if Gui.collapsingHeader("11. About and credits") then Menu.about() end
end
