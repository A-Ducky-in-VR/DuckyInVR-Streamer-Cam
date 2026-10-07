# Streamer Cam

A spectator camera for Orion Drift. You pick a player, it follows them, and it changes camera by itself when they go into an arena. It also does ball cams, goal explosions, kickoff graphics, ball trails, and there's a duck.

Package id: `duckyinvr.streamercam.public`. Version 1.0.0. Made by duckyinvr.

This is a fan project. It isn't made or endorsed by Another Axiom.

## What it does

- **Follows one player.** Third person, first person, a "ball look" third person, or a vlog-style handheld camera.
- **Switches by itself.** One camera mode while your player is walking around outside, another one the moment they're in an arena.
- **Ball cams.** Simple Ball Cam (wide shot on the ball), a version with a goal cam and kickoff cam, and Ball Carrier (player cam on whoever has the ball).
- **Free Cam and Fixed Camera.** Fly it yourself with keyboard or controller, or park it somewhere.
- **Goal explosions.** 21 of them, drawn by the camera when a goal goes in. You can give up to five players their own.
- **Kickoff graphics.** A countdown around the ball at the start of a round.
- **Ball trail, ball outline, player markers.**
- **SpecPet.** The camera becomes a pet that follows your player. A duckling, a kitty or a pidgeon. You can pet it.
- **Extras.** Picture filters, a server search that looks for your player on other servers, and match data for OD Caster Bridge overlays.

Goal explosions and the other graphics are drawn by this camera. Only people watching your camera (your stream or recording) see them. Players in the match don't.

## Install

1. Download `duckyinvr.streamercam.public.zip` from the latest release.
2. Put it in `Documents\Another-Axiom\A2\Cameras\Behaviors`.
3. Extract it there with "Extract Here".
4. Check that this file exists: `Behaviors\duckyinvr.streamercam.public\main.luau`.

If you use Windows "Extract All", it wants to add a second folder with the same name. Delete that extra name from the path before you extract, so the path ends at `Behaviors\`. If you end up with `duckyinvr.streamercam.public\duckyinvr.streamercam.public\main.luau`, the camera won't show up. Move the inner folder up one level.

To update, extract the new zip over the old folder and let it replace the files.

## Quick start

1. Open the spectator client, pick **Streamer Cam** as your camera and open its menu (F3).
2. Open **1. Target player** and pick a player.
3. Open **2. Camera modes** and pick what you want outside an arena and inside one. If you don't know yet, try `Third Person - Head Movement` outside and `Autocast - Simple Ball Cam` inside.
4. Press **Save settings** at the top.

That's all you need. Everything below is optional.

Sliders and checkboxes are only remembered for next time when you press **Save settings**.

## Camera modes

Outside an arena you can use the first five. Inside an arena you can use all ten.

| Mode | What it does |
| --- | --- |
| Third Person - Head Movement | Behind the player, turning with their head. |
| First Person POV | Through the player's eyes. |
| Vlog Camera (Follow+) | Handheld camera from Follow+. The player can also grab the camera with a hand. Without Follow+ installed it's just third person. |
| Free Cam | You fly it. |
| SpecPet | The camera is a pet that follows the player. |
| Third Person - Ball Look | Behind the player, but looking toward the ball. |
| Autocast - Simple Ball Cam | Wide shot that follows the ball. No goal cam or kickoff cam cuts. This is the one I use for clips. |
| Autocast - Simple Ball Cam + Goal Cam | Same, plus a cut to the goal for each goal explosion and a kickoff shot. |
| Autocast - Ball Carrier | Player cam on whoever has the ball, ball cam while it's loose. |
| Fixed Camera | Stays at a spot you saved. |

With no player picked the camera is a Free Cam. The exception is the three Autocast modes: they run with no player too.

### The ball cams stay in one arena

On a server with several matches going (ranked), the three Autocast modes stick to one arena:

- With a player picked, it's that player's arena.
- With no player picked, it's the arena whose ball was nearest the camera when the ball cam started.

When that arena has no ball for a bit (after a goal, between rounds), the camera waits there. It doesn't go off to another arena's ball. To move a no-player ball cam to a different arena, pick a player there, or set the inside mode to Free Cam, fly over and set it back.

If the target's arena has no ball for more than about 8 seconds, the camera goes to the player in third person until the ball is back.

### Free Cam controls

| | Keyboard and mouse | Controller |
| --- | --- | --- |
| Move | W A S D | Left stick |
| Look | Mouse | Right stick |
| Up / down | Space / Ctrl | Right trigger / left trigger |
| Fast | Shift | RB |
| Slow | Alt | LB |

## The menu, section by section

The sections are numbered. In each one the everyday settings are at the top, and anything called "fine tuning" can be left alone.

**1. Target player.** Pick who the camera follows. There's a search box if the server is full. "Find the target on another server" is the experimental server search (see below).

**2. Camera modes.** The outside mode, the inside mode, and the switch that turns automatic switching on or off. A line under each one says what the mode does.

**3. Camera settings.** FOV, and distance / height / speed for each follow mode. Free Cam speed and controller options are here. So is Fixed Camera: fly somewhere, press "Save current view as fixed camera", then pick Fixed Camera as your inside mode.

**4. Ball cams and goal cam.** Distance, height and FOV for Simple Ball Cam, the Ball Carrier settings, the goal cam, and how long an empty arena is kept.

**5. SpecPet.** Pick the pet and how it behaves. Set a mode to `SpecPet` in section 2 first.

**6. Graphics.** Ball outline, ball trail (10 styles), a marker over your player, markers over the other players. These are drawn while your player is in an arena. The ball cams only draw the ball outline and trail.

**7. Goal explosions.** See the next part.

**8. Kickoff graphics and kickoff cam.** The countdown graphic (4 styles), and the kickoff shot for the ball cams that have a goal cam (side on, orbiting, or top down). There's a test button.

**9. Picture filter.** Bloom, vignette, exposure and a few presets. Off until you tick it. Experimental.

**10. Overlay data for OD Caster Bridge.** Only for people running Caster Bridge overlays.

**11. About and credits.**

## Goal explosions

Open **7. Goal explosions**.

- **Explosion for every goal** is the one that plays when anybody scores.
- **Goal explosion color** is Default (team colours), one of the paint colours, or Custom RGB.
- **Preview explosions** lets you try them. Pick one and press "Test Blue Explosion" or "Test Orange Explosion". "Start preview camera" parks the camera in front of a goal so you see the whole thing, and "Next explosion + test" steps through all of them. You need to be in or near an arena.
- **Give a player their own explosion** has five slots. Pick a player and an explosion. When they score, theirs plays.

The list: Basic Burst, Ripple Wave, Caster Burst, Crumble, Claw Strike, Implosion, Fireworks, Lightning Strike, Net Ripple, Glass Shatter, Tornado, Ducky Spirit, Dueling Dragons, Juice Box, Lucky Cat, UFO, Gunslinger, Airstrike, Zero-G Battle, Slushie, Trash Panda.

Things to know:

- Who scored is worked out from the last touches on the ball. Most of the time it's right. When it's wrong you get the explosion for every goal, or now and then another player's.
- Caster Burst needs "Use Caster particle system for Caster Burst" ticked (under "Explosion size and detail"). Without it you get Basic Burst.
- Goals are detected in Driftball 3v3, Driftball 4v4, Driftblitz and Z-Drift arenas. In other arenas nothing plays. The goal cam is for 3v3 and 4v4.
- In the ball cams, a goal on zero seconds or in overtime keeps the camera in the arena until the explosion is done. Then it follows your player out.

## Works with

You don't need any of these. The camera runs fine without them.

- **[Follow+](https://github.com/dennssen/Follow-Plus)** by Dennssen. The Vlog Camera mode uses it when it's installed.
- **[OD Caster Bridge](https://github.com/dennssen/OD_Caster_Bridge)** by Dennssen. Tick "Send Overlay Info" in section 10 and set the bridge's Camera API box to `duckyinvr.streamercam.public`.

About the overlay data:

- Possession, passes, shots, saves, assists, shot speed and boost are estimates worked out from how the players and ball move. Don't treat them as official stats.
- When a match is over and everybody has left the arena (or the camera has followed your player out), the camera stops sending that match about 3 seconds later, so a scoreboard doesn't sit there showing an old game. It starts again when a round runs in that arena. There's a checkbox to turn this off.
- When the camera itself is outside every arena (in the hub, for example) for 2 seconds, it sends "no arena" instead of the last arena, match running or not. Fly back in and that arena's data is back straight away, finished rounds included. It never does this while a ball cam or a player cam is casting an arena, wherever the camera sits. Section 10 has a checkbox for it, a slider for the 2 seconds, and a slider for how far outside an arena still counts as inside (2,500 = 25 metres by default, so an overview from above or a sideline spot doesn't clear anything). The "Camera:" line there shows how far outside the nearest arena you are, which is what you need to set that slider.
- "No arena" / "no match" is the same table with an empty `gamemodeId` and every other field empty or zero. Your overlay has to hide itself (or show standby) when it sees that.

## Experimental stuff

These are less finished than the rest.

- **Server search** (section 1). It moves your spectator through the matchmaking servers one at a time looking for your player, and gives up after two passes. "Auto-follow" does that by itself whenever your player leaves. It can take a while, and it will pull you off the server you're on, so don't leave it on by accident.
  - It learns where your player usually is. Every time they're found on a matchmaking server (by a search, or just there when you arrive), that server's count for that player goes up. The next search asks for their most-visited servers first, then servers other players you followed were on, then the rest. Every server still gets checked twice; only the order changes. The menu shows the counts, and there's a checkbox to turn it off and a "Forget remembered servers" button. It remembers the last 8 players.
  - Some servers don't load when you join them: the game drops you back to its main menu instead. When that happens, come back into spectator and the camera will have worked out which server did it. That server is left out of searches for 2 hours (the menu names it and has a "Check those servers again" button), and a search that was running carries on with the next one.
  - If the game throws you out after a few servers in a row, whichever servers they are, try the "Extra seconds on each server before moving on" slider at 5 to 10.
- **Picture filter** (section 9). A few things to know before you rely on it:
  - It's sent to the game in the follow modes, Free Cam and Fixed Camera. The ball cams don't send it.
  - Exposure, bloom, vignette, chromatic aberration and motion blur use settings the game is known to have. The other seven sliders are sent too, but the game may ignore them.
  - A preset can take over the camera FOV and two of the graphics sliders. There are two checkboxes for that.
  - Turning it off stops the camera changing the picture. It doesn't put the game's own picture back. If it still looks filtered, restart the spectator.

## If something's wrong

- **The camera isn't in the list.** Almost always the folder is nested twice. See Install.
- **My settings reset.** Press Save settings after you change things.
- **No goal explosions.** Check they're enabled in section 7 and look at the "Arena" line there. It says which arena it's watching, or why it isn't watching one.
- **The ball cam is sitting in an empty arena.** It's waiting for that arena's ball. Pick a player, or switch the inside mode to Free Cam and back.
- **The Camera FOV slider does nothing.** A picture filter preset is setting the FOV. Untick "Preset also sets the camera FOV" in section 9. The ball cams, goal cam and kickoff cam also have their own FOV sliders.
- **The trail thickness or vibrance slider snaps back.** Same thing: untick "Preset also sets graphics vibrance and ball trail thickness" in section 9.
- **Free Cam flies through walls.** That's the default. To stop at walls, untick no-clip and tick collision safety (section 3, Free Cam).
- **Vlog Camera looks like normal third person.** Follow+ isn't installed or wasn't found.

If it's none of those, open an issue and tell me the Status line from the top of the menu, the mode you were in and what you expected.

## Credits

Streamer Cam is made by duckyinvr.

It uses or builds on other people's work:

- **Dennssen** - [Caster Camera](https://github.com/dennssen/CasterCamera) (MIT licence). The particle system is adapted from it. The arena sizes, goal positions and goal shape, arena name matching, the overlay data format, and the rules for match stats, round starts and which ball is the match ball come from it too. Every file that uses his material has his copyright and licence notice at the top. He also made Follow+ and OD Caster Bridge, which this camera can talk to.
- **LovelyyLayna** - Layna's Spectator Pet. Kitty and Pidgeon are ports of her pets, and the Duckling's head pats, happy face and hand feeding follow how hers work. All credit for how those pets behave goes to her.
- **august** - august.matchmaker. The server search uses the same network calls and server names.

Inspiration:

- **Plutus** (Plutus Autocaster) and **Yuki and Mozzy** (od-sideline-cam). Their cameras inspired autocast modes I'm still working on. Those aren't in this release.
- **Rocket League**, for the whole idea of goal explosions and painted colours.

## AI disclosure

Most of the code in this project was written with AI (mainly Claude). I came up with the features, decided how they should work, and tested them in game, but I didn't hand-write most of the Luau.

The code is tested against a mock of the game's spectator API before each release. That catches a lot, but it isn't the real game. If you find a bug, please open an issue.

## Licence

My own code in this project is under the MIT licence. See `LICENSE`.

Not everything here is mine. See `THIRD-PARTY-NOTICES.md`:

- The files with Dennssen's notice at the top contain material from Caster Camera and are under his MIT licence.
- `specpets.luau` is a port of LovelyyLayna's Spectator Pet, included with her permission. Ask her before you reuse it somewhere else.
