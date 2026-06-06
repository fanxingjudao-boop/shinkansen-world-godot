# Handoff: Fox Character (キツネキャラクター)

## Overview
This package contains **only the playable fox character** extracted from the "きつねの空の旅 / Fox Adventure" 3D platformer. It is a cute, chibi fox with a vivid-orange coat, big sparkly amber eyes, large pointed ears, a red neckerchief, a huge bushy tail, and a gentle smile. The character ships with a **physics/animation controller** and **two interchangeable visuals**:

- **`model`** — a procedural low-poly 3D fox built entirely from Three.js primitives (no external mesh file).
- **`billboard`** — a flat camera-facing plane textured with the original illustration (`fox-cutout.png`).

This is the result of many design iterations; the current look is the approved one (smooth body — no fur spikes, paws resting down, closed smile).

## About the Design Files
The files here are a **design reference**, not drop-in production code. They are written as a self-contained Three.js class so you can *see and verify* the exact intended look and motion. When integrating into a real codebase:

- If you already use **Three.js / react-three-fiber / Babylon / a game engine**, recreate this character in that environment following its conventions (component structure, asset pipeline, animation system).
- If you are building from scratch, you may reuse `fox.js` directly — it has no dependencies beyond Three.js r0.152.2 and one global (`World.colliders`, see *Integration*).
- Treat the documented geometry, colors and proportions below as the source of truth.

## Fidelity
**High-fidelity.** Final colors, proportions, materials, lighting intent and idle/locomotion animation are all specified. Recreate the silhouette, palette and motion exactly.

## Files
| File | Purpose |
|---|---|
| `fox.js` | The `FoxCharacter` class — physics controller + both visuals + animation. The deliverable. |
| `fox-viewer.html` | A standalone turntable viewer (drag to rotate, wheel to zoom, button to toggle style). Open it to inspect the character in isolation. Good reference for the lighting rig. |
| `fox-cutout.png` | The original illustration, used by the `billboard` style and as the art reference for the model. |
| `uploads/fox-cutout.png` | Same image at the path the un-modified game expects. |

## The Character

### Anatomy (model style)
Built in `_buildModel()` as a tree of primitive meshes under a single group. Local origin is at the **feet on the ground (y = 0)**; the character stands ~3.2 units tall (ears included).

- **Body** — orange sphere (r≈0.78) at y≈0.84, with a darker-orange "saddle" over the back and a large **smooth white chest** (two stacked white spheres) covering the front.
- **Head** — large orange sphere (r≈0.72) at y≈1.82. A lighter-orange forehead blaze + two brow marks. White lower-face mask + two white cheek puffs.
- **Muzzle** — small white sphere; dark nose (with a tiny glossy highlight); a **gentle closed smile** made from a partial `TorusGeometry` arc; thin pale whiskers sweeping back from each side.
- **Eyes** — see *Eyes* below. Soft pink cheek blush discs sit just under each eye.
- **Ears** — very tall, made of stacked cones: rusty-edge → orange → peach → white inner → dark tip. Slight outward tilt. (≈1.75 units tall before scale.)
- **Neckerchief** — red truncated-cone collar at y≈1.4 with a knot and two hanging cone tails at the front.
- **Arms** — two orange capsule arms hanging at the sides, white paw at the end. They swing gently fore/aft while walking.
- **Legs/Feet** — small dark-brown hind feet peeking out at the base.
- **Tail** — an enormous bushy tail: a chain of ~14 spheres swept up-behind and curled over to one side, transitioning orange → cream → white at the tip, with a cream underside lobe per segment. Sways while idle/moving.

### Eyes (the most detailed part)
Each eye is a **gently convex dome** (a `PlaneGeometry` whose vertices are bulged forward) so it nestles into the curved face with no floating gap. It uses an **unlit** (`MeshBasicMaterial`) **canvas-painted texture** generated in `_eyeTexture()`, so it always reads like the illustration regardless of scene lighting. The painted eye contains:
- a soft dark almond outline,
- a vivid amber iris with a vertical gradient (deep top → glowing bottom) and a jewel-like bottom glow ring,
- a large round pupil with a warm reflected-light crescent at its base,
- **catchlights**: one big glossy shine (upper-left), one soft round shine (lower-right), and two small 4-point sparkle stars.
A faint additive warm halo sits behind each eye. Eyes **blink** occasionally (vertical squash of the dome).

### Billboard style
`_buildBillboard()` makes a 2.7-unit-tall plane (aspect 433×780) with the cutout texture (`alphaTest` cutout, double-sided) plus a soft round contact-shadow blob. The game faces this plane toward the camera each frame; it also squashes/stretches and flips horizontally with movement.

## Design Tokens — Palette (model)
| Token | Hex | Use |
|---|---|---|
| Orange | `#f3762a` | main coat |
| Orange dark | `#dd5e18` | back saddle / shading |
| Orange light | `#fba85a` | forehead blaze, brow marks |
| Ear edge | `#bf4a18` | rusty outer rim of ears |
| Ear tip | `#8a4622` | dark ear tips |
| Cream | `#fce8c8` | tail mid, accents |
| White | `#fff6e9` | chest, cheeks, muzzle, paws, tail tip |
| Peach (inner ear) | `#fcc07e` | inner ear |
| Nose | `#2a1810` | nose |
| Red | `#e83a26` | neckerchief |
| Red dark | `#c62a1f` | neckerchief tail |
| Amber / Amber-hi | `#f6a821` / `#fcd76a` | eye iris (painted in texture) |
| Eye rim | `#281307` | eye outline |
| Paw pad pink | `#f2a0a6` | (pads — currently unused with paws down) |
| Feet | `#6e4a2e` | hind feet |
| Cheek blush | `#ff9a86` @ 0.4 | blush discs |

Materials use **`MeshToonMaterial` with a 4-step gradient map** (`_toonGradient()`) for a soft cel-painted look. Eyes/catchlights/whiskers/blush use unlit `MeshBasicMaterial`.

## Lighting (recommended rig — see `fox-viewer.html`)
The character is tuned for: a warm key `DirectionalLight` (`#fff4e0`, ~1.1, casts shadows), a camera-following white fill (~0.45), a cool **rim/back light** (`#bfe0ff`, ~0.7) for a sculpted silhouette, plus hemisphere + ambient fill. Renderer: `PCFSoftShadowMap`, sRGB output, antialias.

## Public API
```js
const fox = new FoxCharacter(scene);   // adds itself to the scene
fox.setStyle('model');                 // or 'billboard'
fox.pos.set(x, y, z);                  // THREE.Vector3 — world position (origin = feet)
fox.onGround = true;

// per frame:
fox.update(dt, input, camYaw, scene);
//   dt: seconds since last frame (clamp to ~0.04)
//   input: { x, y, jumpPressed }  — x/y in [-1,1] (camera-relative), jumpPressed: bool edge
//   camYaw: the camera's yaw in radians (movement is applied relative to it)
```
Key public properties: `pos`, `vel` (Vector3), `facing` (yaw it turns toward), `onGround`, `jumps`, `speed01` (0–1 used for anim blending), and tunables `gravity, moveSpeed, accel, jumpV, doubleJumpV`.

Override the billboard art path before constructing:
```js
FoxCharacter.BILLBOARD_SRC = 'path/to/fox-cutout.png';
```

## Behavior & Animation
- **Locomotion**: camera-relative acceleration, turns smoothly to face velocity, gravity + double jump. Falls below y=-25 trigger `respawn()` to the last safe spot.
- **Squash & stretch** on jump (stretch up) and land (squash).
- **Idle/locomotion anim** (in `_animate`): body bob/hop, arm fore-aft swing, big tail sway, ear wiggle, head bob, and occasional eye blink. All driven by `speed01` and time — no skeletal rig.

## Integration — the one external dependency
`fox.update()` raycasts straight down against a **global `World.colliders`** array (an array of meshes whose tops the fox can stand on) to handle ground/landing. Provide it before the first update:
```js
window.World = { colliders: [ myGroundMesh /*, platforms... */ ] };
```
If you wire the fox into an engine with its own collision/physics, replace the ground-ray block in `update()` with your engine's grounded test and feed `onGround` / vertical position from there. Everything else (visuals, animation, input handling) is self-contained.

## Dependencies
- **Three.js r0.152.2** (the project loads `https://unpkg.com/three@0.152.2/build/three.min.js`). Any modern Three.js release works; if you use ES modules, import `THREE` and drop the global `<script>`.
- No other libraries. The model needs no external 3D asset; only the `billboard` style needs `fox-cutout.png`.
