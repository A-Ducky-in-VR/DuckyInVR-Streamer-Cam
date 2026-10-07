-- Streamer Cam SpecPet pets: Kitty and Pidgeon.
--
-- These two pets are a port of Layna's Spectator Pet 0.0.3 (lovelyylayna.specpet, by LovelyyLayna):
-- the pet behaviours from its pettypes.luau and the follow / eat / rest state machine from its
-- main.luau. All credit for how these pets behave goes to her. What is NOT ported: bond levels,
-- the match-win celebration, the owner picker (Streamer Cam's selected target is the owner) and
-- custom pet scripting.
--
-- Differences from the original, on purpose:
--   * Timers run on seconds instead of counting ticks, so a pet behaves the same at any frame rate.
--   * A head pat needs a tracked hand (same rule as Streamer Cam's Duckling), and honours the
--     "everyone / only the owner" setting.
--   * Every engine call is guarded. An error in here can only cost the pet one tick.
--
-- Streamer Cam's own Duckling pet is not in this file; it stays in main.luau.
local Pets = { kinds = { "Kitty", "Pidgeon" }, label = "", lastError = nil }

local EMOTE = { Sleepy = 2, Biting = 6, Gleam = 9, Standard = 11 } -- SpecPet's emote numbers

local state = nil

local function fresh(kind, ownerId)
	return {
		kind = kind, owner = ownerId, mode = "follow", -- "follow" | "eat" | "rest"
		walkStep = 0, walkTimer = 0,
		grabbed = false,
		emote = nil, emoting = false, emoteTimer = 0, emoteLength = 0,
		eatTimer = 0, eatCooldown = 0, eatSpot = nil,
		restTimer = 0, restSpot = nil, restCooldown = 0, patted = false,
		ticked = false,
	}
end
state = fresh("", nil)

local function number(value, default, low, high)
	if type(value) ~= "number" or value ~= value then return default end
	return math.clamp(value, low, high)
end

local function setEmote(index)
	pcall(function() camera:setEmote(index) end)
end

-- Show a face for `seconds`. (SpecPet re-sends the emote every tick; here it is only sent when
-- it changes, the timer is simply restarted.)
local function display(index, seconds)
	if not state.emoting or state.emote ~= index then setEmote(index) end
	state.emote, state.emoting, state.emoteTimer, state.emoteLength = index, true, 0, seconds
end

local function emoteTick(dt)
	if not state.emoting then return end
	state.emoteTimer += dt
	if state.emoteTimer >= state.emoteLength then
		setEmote(EMOTE.Standard)
		state.emoting, state.emote = false, nil
	end
end

local function distance(a, b) return (a - b):length() end

local function upFor(player)
	if gravity ~= nil and gravity.upDirection ~= nil and gravity.upDirection:length() > 0.001 then return gravity.upDirection end
	return player.root.rotation:getUpVector()
end

-- The owner's own up / right / forward, as SpecPet works them out.
local function basis(player)
	local up = player.root.rotation:getUpVector()
	local right = up:cross(player.head.rotation:getForwardVector())
	local forward = up:cross(right) * -1
	return up, right, forward
end

local function ray(from, to)
	local ok, hit = pcall(function() return camera:castRay(from, to) end)
	if ok and hit ~= nil and hit.successful and hit.position ~= nil then return hit.position end
	return nil
end

local function glide(target, dt, cfg)
	local speed = number(cfg.specPetSpeed, 3, 0.5, 12) -- SpecPet's petSpeedMultiplier
	camera.position = camera.position + ((target - camera.position) * math.clamp(speed * dt, 0, 1))
end

local function face(direction, up)
	camera:lookAt(camera.position + (direction * 100), up)
end

local function handPosition(player, left)
	local hand = if left then player.leftHand else player.rightHand
	if hand == nil or hand.position == nil then return nil, false end
	local tracked = hand.position:length() > 8 -- an untracked hand sits at the body origin
	return player.root.position + player.root.rotation:rotateVector(hand.position), tracked
end

-- SpecPet reads the trigger from the hand pose bits (bit 1).
local function triggerHeld(player, left)
	local bits = if left then player.leftHandPosebits else player.rightHandPosebits
	return type(bits) == "number" and bit32.band(bits, 2) ~= 0
end

local function players()
	local ok, list = pcall(function() return getGameData().players end)
	return if ok and type(list) == "table" then list else {}
end

local function nearestBall(origin, radius)
	local ok, balls = pcall(function() return getGameData().balls end)
	if not ok or type(balls) ~= "table" then return nil end
	local best, bestDistance = nil, radius or math.huge
	for _, ball in pairs(balls) do
		if ball ~= nil and ball.transform ~= nil and ball.transform.position ~= nil then
			local gap = distance(origin, ball.transform.position)
			if gap == gap and gap <= bestDistance then best, bestDistance = ball, gap end
		end
	end
	return best
end

local function walkCycle(dt, cfg)
	state.walkTimer += dt
	if state.walkTimer > number(cfg.specPetWalkStepSeconds, 0.5, 0.1, 3) then
		state.walkStep = if state.walkStep == 1 then 0 else 1
		state.walkTimer = 0
	end
end

-- KITTY ---------------------------------------------------------------------------------------
-- Stays put and watches the owner until they are more than 200 away, then pads over along the
-- ground (with a little hop in its step) and stops again.
local function kittyFollow(player, dt, cfg)
	local up = upFor(player)
	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	if distance(camera.position, player.root.position) > 200 then
		local target = player.root.position -- owner in the air: head straight for them
		local ground = ray(player.root.position, player.root.position - (up * 500))
		if ground ~= nil then
			target = ground + (up * 15)
			if cfg.specPetWalkCycle ~= false then
				walkCycle(dt, cfg)
				if state.walkStep == 0 then target = target + (up * number(cfg.specPetWalkHeight, 30, 0, 80)) end
			end
		end
		camera:lookAt(player.head.position, up)
		glide(target, dt, cfg)
	else
		camera:lookAt(player.head.position, up)
	end
end

local function kittySleep(player, dt, cfg)
	local up, right, forward = basis(player)
	camera.position = player.root.position + (right * 40) -- curls up right beside the owner
	face(forward, up)
	display(EMOTE.Sleepy, 0.3)
end

local function kittyWantsBall(ball, cfg)
	local spot = ball.transform.position
	if distance(camera.position, spot) > number(cfg.specPetEatRadius, 50, 10, 300) then return false end
	local up = if gravity ~= nil and gravity.upDirection ~= nil then gravity.upDirection else Vec3.new(0, 0, 1)
	return ray(spot, spot - (up * 30)) ~= nil -- only a ball that is on (or nearly on) the ground
end

-- Returns: where to go (or nil), whether the meal is progressing, whether to give up.
local function kittyEat(player, ball, dt, cfg)
	local spot = ball.transform.position
	local up = upFor(player)
	if distance(camera.position, spot) > 400 then return nil, false, true end
	if distance(camera.position, spot) > 10 then
		local ground = ray(spot, spot - (up * 30))
		if ground == nil then return nil, false, true end
		camera:lookAt(spot, up)
		display(EMOTE.Biting, 0.3)
		return ground, true, false
	end
	display(EMOTE.Biting, 0.3)
	return nil, true, false
end

-- PIDGEON -------------------------------------------------------------------------------------
-- Flies along at the owner's right shoulder, bobbing as it flaps. Hold the right trigger with the
-- right hand on it to pick it up; it rides in that hand until the trigger is let go.
local function pidgeonFollow(player, dt, cfg)
	camera.positionSmoothing = 0.01
	camera.rotationSmoothing = 0.01
	local worldUp = upFor(player)
	local hand, tracked = handPosition(player, false)
	if state.grabbed then
		if hand ~= nil then camera.position = hand end
		camera:lookAt(player.head.position, worldUp)
		if not triggerHeld(player, false) then state.grabbed = false end
		return
	end
	local up, right, forward = basis(player)
	local perch = player.root.position + (right * 40)
	if cfg.specPetWalkCycle ~= false then
		walkCycle(dt, cfg)
		if distance(camera.position, perch) >= 80 then
			glide(perch + (Vec3.new(0, 0, 1) * (if state.walkStep == 1 then 15 else -15)), dt, cfg)
			camera:lookAt(player.head.position, worldUp)
		else
			glide(perch, dt, cfg)
			face(forward, up)
		end
	else
		glide(perch, dt, cfg)
		if distance(camera.position, player.head.position) >= 40 then camera:lookAt(player.head.position, worldUp) else face(forward, up) end
	end
	if hand ~= nil and tracked and distance(hand, camera.position) <= 20 and triggerHeld(player, false) then
		state.grabbed = true
	end
end

local function pidgeonSleep(player, dt, cfg)
	local up = upFor(player)
	glide(player.head.position + (up * 30), dt, cfg) -- roosts on the owner's head
	face(player.root.rotation:getForwardVector(), player.root.rotation:getUpVector())
end

local function pidgeonWantsBall(ball, cfg)
	if state.grabbed then return false end
	local up = if gravity ~= nil and gravity.upDirection ~= nil then gravity.upDirection else Vec3.new(0, 0, 1)
	local under = ray(camera.position, camera.position - (up * 500))
	local spot = ball.transform.position
	local ballGround = ray(spot, spot - (up * 500))
	if under == nil or ballGround == nil then return false end
	return distance(under, ballGround) <= number(cfg.specPetEatRadius, 50, 10, 300) * 1.3
end

local function pidgeonEat(player, ball, dt, cfg)
	local spot = ball.transform.position
	if distance(camera.position, spot) > 400 then return nil, false, true end
	if distance(camera.position, spot) > 30 then
		local target = spot + (Vec3.new(0, 0, 1) * 10)
		camera:lookAt(target, upFor(player))
		return target, false, false -- still flying over: the meal has not started
	end
	return nil, true, false
end

-- SHARED STATE MACHINE (SpecPet main.luau) ----------------------------------------------------
local function sensePats(player, cfg)
	state.patted = false
	if cfg.specPetHeadpats == false or state.emoting then return end
	local ownerOnly = cfg.ducklingInteractEveryone == false
	for _, other in pairs(players()) do
		local isOwner = other == player or (other.playerId ~= nil and other.playerId == player.playerId)
		if other ~= nil and other.root ~= nil and other.root.position ~= nil and other.root.rotation ~= nil and (isOwner or not ownerOnly) then
			for side = 1, 2 do
				local left = side == 1
				local hand, tracked = handPosition(other, left)
				-- (the Pidgeon ignores the right hand while it is being held in it)
				local holdingHand = state.kind == "Pidgeon" and state.grabbed and isOwner and not left
				if hand ~= nil and tracked and not holdingHand and distance(camera.position, hand) < 30 then
					display(EMOTE.Gleam, 3)
					state.patted = true -- being petted keeps it awake
					return
				end
			end
		end
	end
end

local function restTimer(player, dt, cfg)
	if cfg.specPetRest == false then return end
	if state.patted then state.restTimer = 0 return end
	if state.restCooldown > 0 then
		state.restCooldown = math.max(state.restCooldown - dt, 0)
		return
	end
	if state.restSpot == nil then state.restSpot = player.root.position end
	if distance(state.restSpot, player.root.position) < 15 then
		state.restTimer += dt
	else
		state.restTimer, state.restSpot, state.restCooldown = 0, nil, 10
	end
	if state.restSpot ~= nil and state.restTimer > number(cfg.specPetRestSeconds, 10, 2, 120) then
		state.mode = "rest"
	end
end

local function lookForBall(player, dt, cfg)
	if cfg.specPetEatBalls == false then return end
	if state.eatCooldown > 0 then
		state.eatCooldown = math.max(state.eatCooldown - dt, 0)
		return
	end
	local ball = nearestBall(camera.position)
	if ball == nil then return end
	local wanted = if state.kind == "Pidgeon" then pidgeonWantsBall(ball, cfg) else kittyWantsBall(ball, cfg)
	if not wanted then return end
	state.mode, state.eatTimer, state.eatSpot, state.restTimer = "eat", 0, ball.transform.position, 0
end

local function followState(player, dt, cfg)
	if state.kind == "Pidgeon" then pidgeonFollow(player, dt, cfg) else kittyFollow(player, dt, cfg) end
	sensePats(player, cfg)
	restTimer(player, dt, cfg)
	lookForBall(player, dt, cfg)
end

local function eatState(player, dt, cfg)
	local function stop()
		state.mode, state.eatCooldown = "follow", number(cfg.specPetEatCooldown, 5, 0, 60)
	end
	local ball = if state.eatSpot ~= nil then nearestBall(state.eatSpot, 500) else nil
	if ball == nil then stop() return end
	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	local target, progressing, giveUp
	if state.kind == "Pidgeon" then target, progressing, giveUp = pidgeonEat(player, ball, dt, cfg) else target, progressing, giveUp = kittyEat(player, ball, dt, cfg) end
	if giveUp then stop() return end
	if progressing then
		state.eatTimer += dt
		if state.eatTimer >= number(cfg.specPetEatSeconds, 3, 0.5, 20) then
			display(EMOTE.Standard, 1)
			stop()
			return
		end
	end
	if target ~= nil then glide(target, dt, cfg) end
end

local function restState(player, dt, cfg)
	if state.restSpot == nil or distance(player.root.position, state.restSpot) > 15 then
		state.restTimer, state.restSpot, state.mode = 0, nil, "follow" -- the owner moved: wake up
		return
	end
	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	if state.kind == "Pidgeon" then pidgeonSleep(player, dt, cfg) else kittySleep(player, dt, cfg) end
end

-- Runs one tick of the named pet ("Kitty" or "Pidgeon") following `player`. Returns true when
-- the pet ran. Pets.label says what it is doing, for the GUI.
function Pets.tick(kind, player, dt, cfg)
	if kind ~= "Kitty" and kind ~= "Pidgeon" then return false end
	if player == nil or player.root == nil or player.root.position == nil or player.root.rotation == nil
		or player.head == nil or player.head.position == nil or player.head.rotation == nil then
		return false
	end
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 then dt = 1 / 60 end
	dt = math.min(dt, 0.1)
	local ownerId = player.playerId or player.id or player.playerName
	if state.kind ~= kind or state.owner ~= ownerId then
		local wasEmoting = state.emoting
		state = fresh(kind, ownerId) -- a different pet or a different owner starts from scratch
		if wasEmoting then setEmote(EMOTE.Standard) end
	end
	state.ticked = true
	local ok, problem = pcall(function()
		emoteTick(dt)
		if state.mode == "eat" then
			eatState(player, dt, cfg)
		elseif state.mode == "rest" then
			restState(player, dt, cfg)
		else
			followState(player, dt, cfg)
		end
	end)
	if not ok then
		Pets.lastError = tostring(problem)
		state.mode = "follow"
		return false
	end
	Pets.label = kind .. ": " .. (if state.mode == "rest" then "sleeping" elseif state.mode == "eat" then "eating a ball"
		elseif state.grabbed then "held in the owner's hand" elseif state.emoting and state.emote == EMOTE.Gleam then "being petted" else "following")
	return true
end

-- Call once per script tick, after the camera has run. When a Kitty / Pidgeon did not run this
-- tick (another mode took over, or the pet type changed), its face goes back to normal and its
-- state is dropped, so it never stays asleep or mid-bite while something else drives the camera.
function Pets.afterTick()
	if state.ticked then
		state.ticked = false
		return
	end
	if state.kind ~= "" then
		if state.emoting then setEmote(EMOTE.Standard) end
		state = fresh("", nil)
		Pets.label = ""
	end
end

-- For tests and the GUI.
function Pets.peek() return state end

return Pets
