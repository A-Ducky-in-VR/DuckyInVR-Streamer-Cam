# Third-party notices

Streamer Cam contains or builds on work by other people. This file says what, where, and under what terms.

## Caster Camera, by Dennssen

Source: https://github.com/dennssen/CasterCamera

These files in this package use material from Caster Camera. Each one has the notice below at the top, followed by a note saying what was taken.

| File | What comes from Caster Camera |
| --- | --- |
| `particlesystem.luau` | An adapted copy of its `particlesystem.luau` (2.6.4). Changed: the update takes the frame time so it runs the same at any frame rate, caps on particle count and lifespan, colours copied instead of modified in place, ray casts and draw calls guarded, lines drawn through a callback. |
| `arenamap.luau` | Arena box sizes for the known layouts, kickoff spot heights and arena name matching. The code is written for Streamer Cam. |
| `goalcontext.luau` | Goal positions, arena sizes and arena name matching. The code is written for Streamer Cam. |
| `overlay.luau` | The overlay data format and the game calls used to fill it, so OD Caster Bridge can read it. The code is written for Streamer Cam. |
| `matchstats.luau` | The approach to possession, boost and match stats, the boost numbers and the 4v4 boost pad positions. The code is written for Streamer Cam. |
| `goaleffects.luau` | The size and shape of the goal mouth, used to place the effects. The effects are written for Streamer Cam. |
| `kickoff.luau` | The rule for when a round starts (which game signals are read, and when). The code is written for Streamer Cam. |
| `main.luau` | The rule for telling a match ball from a toy ball, the rule for who "has the ball", and the names and values of the game's post-processing settings. The code is written for Streamer Cam. |

Caster Camera is under this licence:

```
MIT License

Copyright (c) 2025 dennssen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Layna's Spectator Pet, by LovelyyLayna

`specpets.luau` (the Kitty and Pidgeon pets) is a port of Layna's Spectator Pet 0.0.3 (`lovelyylayna.specpet`): the pet behaviours from its `pettypes.luau` and the follow / eat / rest logic from its `main.luau`, reworked to run on seconds and to use Streamer Cam's target and hand-tracking rules. The Duckling in `main.luau` is Streamer Cam's own pet, but its head pats, happy face and hand feeding follow how hers work. All credit for how those pets behave goes to her.

Included with her permission. `specpets.luau` is not covered by Streamer Cam's own licence, so if you want to reuse it somewhere else, ask LovelyyLayna.

## august.matchmaker, by august

`targetfinder.luau` (the experimental server search) uses the same network calls and server names as august.matchmaker. The code is written for Streamer Cam.

## Follow+ and OD Caster Bridge, by Dennssen

Not included. Streamer Cam can talk to them if you have them installed:

- Follow+: https://github.com/dennssen/Follow-Plus
- OD Caster Bridge: https://github.com/dennssen/OD_Caster_Bridge
