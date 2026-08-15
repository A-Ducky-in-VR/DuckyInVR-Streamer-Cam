# Streamer Cam Public Beta

Streamer Cam Public Beta is a lightweight **Orion Drift spectator camera script** made for streamers, casters, and clip creators.

This first public version focuses on a smaller set of camera tools that are useful for basic spectating, streaming, casting, and recording gameplay.

## Current Version

**v0.1.3**

## What This Script Does

Streamer Cam gives spectators a few camera modes designed to make Orion Drift easier to watch and record.

It includes:

- target player selection
- outside-arena camera modes
- inside-arena camera modes
- a simple ball-follow camera
- configurable ball trail graphics
- custom goal explosion overlays

This is a **public beta**, so feedback and bug reports are welcome.

## Installation

1. Download the latest release zip.
2. Extract the zip file.
3. Move the extracted folder named:

```text
duckyinvr.streamercam.public
```

into your Orion Drift camera behaviors folder.

On Windows, that folder is usually here:

```text
C:\Users\<YourWindowsUsername>\OneDrive\Documents\Another-Axiom\A2\Cameras\Behaviors
```

After installing, the folder should look like this:

```text
C:\Users\<YourWindowsUsername>\OneDrive\Documents\Another-Axiom\A2\Cameras\Behaviors\duckyinvr.streamercam.public
```

The package folder should contain:

```text
duckyinvr.streamercam.public/
  README.md
  main.luau
  package.json
  particlesystem.luau
```

4. Open Orion Drift.
5. Open the spectator script menu.
6. Select **Streamer Cam Public Beta**.

## Included Modes

### Outside Arena Modes

Outside arena modes are used when the selected target is not actively inside an arena.

#### Third Person - Head Movement

This mode follows behind the selected player and uses their head direction to guide the camera.

It is useful for:

- following a selected player before they enter an arena
- getting simple third-person spectator shots
- keeping the camera attached to a target without needing manual control

#### Free Cam

Free Cam gives manual camera control.

It is useful for:

- setting up shots
- moving around freely
- filming intros or transitions
- spectating without being locked to a player

## Inside Arena Modes

Inside arena modes are used when the selected target is inside an arena.

### Basic Ball Follow

Basic Ball Follow is a simple ball-focused camera.

Instead of trying to do complicated automatic casting, this mode keeps the camera focused on the ball so the action is easier to follow.

It is useful for:

- clips
- casting
- general spectator viewing
- following fast plays without manually tracking the ball

### Third Person - Head Movement

This mode follows the selected player from a third-person angle while they are in arena.

It is useful for:

- player-focused clips
- following a specific player
- showing movement and positioning from behind the player

### Third Person - Ball Look

This mode keeps the camera near the selected player but aims the camera toward the ball.

It is useful when you want to:

- keep the selected player in context
- still see where the ball is
- capture player positioning and ball action together

## Graphics

### Ball Trail

Streamer Cam Public Beta includes a configurable ball trail effect.

The ball trail helps make the ball easier to see during fast plays and can make clips look more dynamic.

Ball trail settings include:

- trail style
- trail fade time
- trail thickness
- trail glow width
- trail core width
- trail vibrance
- speed-based trail coloring

## Goal Explosion Overlays

This script includes a small set of custom WorldDraw-style goal explosion overlays.

Included goal explosion types:

- **Basic Burst**
- **Ripple Wave**
- **Claw Strike**
- **Implosion**

These effects are visual overlays drawn by the spectator script. They are not official Orion Drift goal explosions and may not behave exactly like native in-game effects.

Goal explosion settings include:

- enable/disable overlay
- default explosion type
- test explosion type
- explosion color
- particle/detail count
- ring count
- lifetime
- vibrance
- debounce timing
- max active particles
- closest-arena-only behavior

## Public Beta Feedback

This is an early public beta, so testing feedback is helpful.

If you try it, please let me know:

- whether it appears correctly in the spectator script menu
- whether the camera modes feel stable
- whether Basic Ball Follow is useful
- whether ball trails stay visible
- whether goal explosions trigger correctly
- whether the settings UI is clear
- whether anything causes lag, errors, or weird camera behavior

When reporting a bug, please include:

- what mode you were using
- what arena/state you were in
- what you expected to happen
- what actually happened
- whether it happens every time or only sometimes

## Credits and Acknowledgements

Streamer Cam Public Beta was built by **DuckyInVR**.

Parts of the script were inspired by or adapted from Orion Drift spectator scripting examples and community scripts, including:

### Dennssen’s Caster Camera

Used as a reference/inspiration for:

- caster-style camera ideas
- WorldDraw graphics patterns
- goal explosion and particle effect ideas
- spectator script structure

### Follow+ / Follow Pluss

Used as a reference/inspiration for:

- spectator follow camera behavior
- player-follow camera concepts
- camera control ideas

### Orion Drift Community Script Examples

Other community spectator scripts and examples helped with:

- package structure
- camera API usage
- player and ball data access
- GUI patterns
- spectator scripting conventions

If any part of this project needs clearer credit, please reach out and I will update the README, adjust the implementation, or remove the relevant code.

## AI Assistance Disclosure

This project was developed with assistance from AI tools.

AI assistance was used for:

- organizing code
- debugging
- refactoring
- generating implementation ideas
- writing documentation
- packaging release builds
- checking for obvious release issues

All design choices, feature selection, testing decisions, and public release decisions were directed and reviewed by me.

## Disclaimer

This is a community-made spectator script.

It is not affiliated with, endorsed by, or officially supported by Orion Drift.

Use this script at your own risk. Make sure custom spectator scripts are allowed in whatever lobby, event, league, or tournament you are using it in.

## License / Usage

This is an early public beta release.

If you use, modify, or share this script, please keep credits intact and credit the original inspirations where appropriate.

A formal license may be added later.
