# Changelog

## 1.0.0

First full public release (the 0.1 beta had a small part of this).

- Follow modes: third person, first person, third person looking at the ball, vlog camera (with Follow+).
- Automatic switch between an outside mode and an inside mode when the target enters or leaves an arena.
- Ball cams: Simple Ball Cam, Simple Ball Cam + Goal Cam, Ball Carrier. Goal cam and kickoff cam.
- The ball cams stay with one arena on servers that have several matches going. They wait when that arena has no ball instead of going to another arena's.
- Free Cam (keyboard and controller) and Fixed Camera.
- 21 goal explosions, paint colours, per-player explosions, a preview camera.
- Kickoff graphics (4 styles) and kickoff cam (3 shots).
- Ball outline, ball trail (10 styles), target marker, team markers.
- SpecPet: Duckling, Kitty, Pidgeon.
- Picture filter (off by default, experimental).
- Experimental: server search and auto-follow. It remembers which servers a player is usually found on and checks those first. A server that drops you to the main menu when it is joined is remembered and left out for 2 hours.
- Optional: match data for OD Caster Bridge overlays. A finished match stops being sent once its arena has emptied, and "no arena" is sent while the camera is outside every arena.
