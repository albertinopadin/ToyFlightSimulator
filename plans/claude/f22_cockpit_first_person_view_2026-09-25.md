# F-22 cockpit and first-person view — Implementation Plan

**Started:** 2026-09-25 · **Agent:** claude
**Design source:** the codebase (files cited below) and the cockpit asset's own build notes,
`~/Desktop/BlenderProjects/ToyFlightSimulator/F22_Cockpit/README.md` (sources for the cockpit
layout, the frame conventions, the rig, and how to rebuild or re-export the asset). No research
document: this is asset integration through existing engine paths, small enough to plan from the code.
**Status:** in progress (Milestones 1–3 landed in 25f61c9, Milestone 4 in be87bfd, Milestone 5 in 56dbe0d)
**Related plans:** `plans/claude/c_key_camera_toggle.md` (camera registry and slot selection),
`plans/claude/procedural-animation-plan.md` (procedural channels),
`plans/claude/aircraft_center_of_mass_recentering_2026-09-25.md` (the F-22 body frame used for the eye point)

## How this document works

- The owner writes the code from the pseudocode. The agent implements a milestone only when asked.
- Milestones are edited in place to match the code. History goes in the Changelog, newest first,
  one line per entry.
- A milestone header gets `✅ (landed YYYY-MM-DD, <commit>)` when it lands. Checkboxes (`- [ ]`)
  track the items inside it.
- Review findings that change the plan are folded in; the changelog line names the review and
  says which numbers were re-checked with a scratch script.

## Changelog

- **2026-09-30** — Emission added once, outside the sum over lights (owner question: with several lights, wasn't it multiplied by their number?). It was: `ShadeDirectionalBlinnPhong` took `emission` and returned it in every call, and `material_fragment` / `transparent_material_fragment` sum that call over `lightCount`, so N suns gave N × emission (invisible today: every scene has one sun). The per-light function no longer takes emission; the forward loops start from `emission`, and the transparency fragments and both sun passes add it to their one light's term. Source: the OpenGL 2.1 lighting equation (§2.14.1, p. 62, checked in the extracted PDF text: `e_cm` outside `Σ_i`) and the rendering equation (Kajiya 1986). Algorithm, edge cases, design decisions and References updated. One sun gives the same image as before.
- **2026-09-30** — Renamed `parentModelType` to `sourceFileFormat` (owner request): it holds a `ModelExtension` (the file format), and the old name read like the unrelated `ModelType` enum. `Model.GetMeshes`'s `modelType:` label, the same value, is renamed too.
- **2026-09-30** — Review of the owner's Milestone 5 code, with fixes, and the M5 tests. Two defects kept the displays dark. (1) `Material.init` took `parentModelType` but passed nothing to `setProperties`/`populateMaterial`, whose `= nil` defaults let that compile, so `.emission` was never read; the defaults are gone and the USD-only rule is one static `Material.readsEmission(from:)`. (2) The deferred renderers (TiledMSAATessellated is the macOS default) passed emission 0 in the sun pass, because no G-buffer channel carried it; the G-buffer stage now writes emission into the lighting target (`GBufferOut.lighting`, `GBufferData.lighting`) and the sun pass reads it back. Also fixed: `CalculateDirectionalLighting` had the new 0 in the toCamera slot, so the light direction went in as emission (only the reference `og_` fragment calls it); the texture-slot comments in the transparency fragments (shadow array now slot 4). New `ResolveEmission` helper: a `setColor` object gives off no light. Emission texture loading now happens once, in `populateMaterial`. Milestone rewritten to match the code; Pitfalls updated. Numbers (the lens colors; the OBJ `Ka` arriving as the float3 (1, 1, 1) under `.emission`, the same type as a USD `emissiveColor`) reproduced with the scratch probes `probe_emission.swift` and `probe_synthetic.swift`. The 8 new tests pass (the cockpit and synthetic-USD cases fail with defect (1) put back); full suite 495 Swift Testing tests in 68 suites + 20 XCTest pass. Checked in the app in the cockpit view, under Metal API validation, with the TiledMSAATessellated, SinglePassDeferredLighting and OIT renderers.
- **2026-09-28** — Review of the owner's Milestone 4 code, with fixes, and the M4 tests. The owner's `inverted` flags are right and the plan's were wrong: all seven were reversed, because `float4x4(rotateAbout:byAngle:)` is the transpose of the right-handed axis-angle matrix (a positive angle turns clockwise seen from the axis tip) and the plan had derived them with the right-hand rule. Data table, pseudocode and Pitfalls corrected. Fixed in `F22CockpitAnimator`: the five channel properties were implicitly unwrapped (`!`), so a joint missing from the model (the config only warns) would crash the first setter; now optional, and a missing channel's setter does nothing. `gearHandleCommandedDown` became static, for a Metal-free test (the caller passes `.down` when there is no exterior animator). The threshold keeps the owner's name, `F22.milPowerThrottleThreshold`. Tests: `CockpitControlMappingTests` (Metal-free) and `CockpitAnimatorTests` (app-hosted; reads each skinned mesh's palette and checks where the stick, both levers, both pedals and the gear knob move). Expected positions reproduced with the scratch script `cockpit_m4_directions.swift` (inputs: the engine's rotateAbout matrix, the import basis, the joint pivots, the owner's flags). The 13 new tests pass; full suite 487 Swift Testing tests in 67 suites + 20 XCTest pass.
- **2026-09-28** — Milestone 4 revised to match the owner's in-progress `F22CockpitAnimator` and `F22CockpitAnimationConfig`: layer IDs `cockpitStick`/`cockpitThrottle`/`cockpitRudderPedals`/`cockpitGearHandle`, channel IDs `sideStickRoll`/`sideStickPitch`/`cockpitThrottle`/`rudderPedals`/`gearHandle`, joint lookup `findJointPaths`. Placement settled: only the layer IDs go in `AircraftAnimator.swift`; the throttle mapping is static on the config; the setters and the cached channels are on the cockpit animator; `Aircraft` builds the animator in `attachCockpit` and drives it in `doUpdate`; the 0.8 MIL/afterburner threshold is named once (`F22.afterburnerThrottleThreshold`). Found: the Sketchfab `F22` has no exterior animator, so G does nothing there and its gear handle stays DOWN. Added the pure `gearHandleCommandedDown` rule and its test, and the G check now names the CGTrader F-22. Numbers re-checked with the scratch script `cockpit_m4_numbers.swift` (inputs: the owner's rounded constants 5.74°, 17.46°, 33.40°, threshold 0.8, channel speeds 8/3/4/3 per s): lever angles and channel values as listed (the exact asin values differ by < 0.003°), IDLE → AB in 0.44 s, gear knob UP 16.70° above the slot centre, and the rotation directions for the stick, levers, pedals and yaw key.
- **2026-09-27** — Review of the owner's Milestones 1–3 code, with fixes, and the M1–M3 tests. Fixed in `CockpitCamera`: `setRotationX(headYaw)` then `setRotationY(headPitch)` swapped the axes (yaw is about Y), and each call replaces the whole rotation, so only the second survived; both also turned about world-frame axes (`getRightVector`/`getUpVector` read the world matrix), wrong once the jet banks. Now `turnHead` builds one local rotation, Ry(yaw)·Rx(−pitch), through the pure `turnedHead`/`headRotation` helpers. The limits (150°, 70° up, 80° down; the owner's values, the plan had 60/70) were degrees used as radians, so they never clamped; the mouse Y sign was inverted. `attach(to:)` now recentres the head and returns false, leaving the camera unparented, for a jet without a cockpit; `applyAircraftSwap` attaches for every aircraft type, keeps the cockpit view across a swap to a jet that has one, and takes the camera out of the registry otherwise (`CameraManager.UnregisterCamera`, new), so 'C' no longer cycles to a camera left behind in the removed jet. `Aircraft.cockpitNativeToBody` became static and the M3 filter a static `F22.shouldRenderExteriorSubmesh`, both for Metal-free tests. Numbers re-checked with the scratch script `cockpit_test_numbers.swift` (stick pivot (0.3635, 0.5390, 7.2330) and (0.3635, 0.4990, 5.7330), basis det −1, yaw +90° → (1, 0, 0), pitch +30° → (0, 0.5, 0.8660), yaw 90° + pitch 30° keeps the right axis level). 29 tests in 7 suites pass; full suite 474 + 20 XCTest pass.
- **2026-09-27** — Asset fix (owner report: the cockpit view showed only light brown, `debugging/screenshots/F22Cockpit_CantSeeOut.png`): `Canopy_Glass` had exported with `opacity = 1`, so the engine drew the gold-tinted glass opaque. Blender 5.2.2's USD exporter writes opacity 1 for any Principled Alpha that no image texture feeds (reproduced headless with Alpha 0.07 and 0.5, Dithered, and a Value node). `export_usdz.py` now registers a `ScalarAlphaToOpacity` export hook, and `verify_cockpit_usdz.swift` fails when a material other than `Canopy_Glass`/`HUD_Combiner` would be drawn transparent, or either of those opaque (it flags the old file). Re-exported and prim-compared with the old file (only authored change: that opacity, 1 → 0.07; textures byte-identical); verify RESULT: OK, `usdchecker` Success.
- **2026-09-26** — Milestone 1: added the app-hosted test `CockpitModelTests.restPosePaletteIsIdentity`, the regression test for the empty-`currentPose` crash in `Skin.updatePalette` (clip-less rig; fixed in `dd36871`). Identity result reproduced with the scratch script `cockpit_rest_palette.swift` (Model I/O, world rest × inverse bind per joint): max |palette − I| = 0.0 for all 8 joints.
- **2026-09-25** — Asset revision 3 (owner review of r2): HUD anti-glare tabs now jut forward (away from the pilot) instead of aft; ICP brought aft to the HUD glass plane (key faces at y ≈ 0.51–0.52 m, the glass spans 0.509–0.532 m), tucked under the glareshield lip and 9 mm shorter so the whole ICP face and every display stay visible from the DEP (ray-cast check: no display sample hidden by the ICP); stick-head hypotenuse kinked outward 11 mm so the red button sits fully on the thumb face. HUD glass, calibration and joint pivots unchanged. 42,560 triangles, 30 meshes, 77 submeshes. Re-verified with `verify_cockpit_usdz.swift` (RESULT: OK) and `usdchecker` (Success), no vertex outside the Sketchfab skin.
- **2026-09-25** — Asset revision 2 (owner review against photos): squat barrel-shaped HUD combiner (0.180 x 0.165 m, top 3.7° above the DEP line) with a frame thin across and deep fore-aft plus anti-glare tabs; all displays flat and vertical, ICP 3–5 cm proud of them; glareshield hood juts 11 cm aft and side glare shields splay aft to the sills; right-triangle stick head; D-shaped throttle grips. Joint pivots unchanged. HUD calibration re-derived and reproduced with the scratch script `hud_v2_numbers.py` (inputs: half extents 0.090/0.0825 m, bottom centre (0, 0.532, −0.130), 8° tilt, 1024 x 939 px): boresight uv (0.500, 0.7956), 51.01 / 51.41 px/deg. Re-verified with `verify_cockpit_usdz.swift` (RESULT: OK) and `usdchecker` (Success), no vertex outside the Sketchfab skin.
- **2026-09-25** — Plan created. The asset `F22_Cockpit.usdz` is already in
  `ToyFlightSimulator Shared/Core/Resources/Models/F22_Cockpit/` and was checked on the Mac with
  Model I/O (`Tools/verify_cockpit_usdz.swift` in the Blender project: all 30 meshes triangulated,
  UVs present, 6 rigidly skinned meshes on skeleton `CockpitRig`, joint rest rotations identity,
  "RESULT: OK") and `usdchecker` ("Success!"). Every number in this plan was reproduced with the
  scratch script `cockpit_numbers.py` (inputs: the pivot depths, slot offsets, combiner pose and
  eye points listed in "Worked example"), which lives outside the repo.

## Goal and what you will learn

When this plan is finished, pressing **1** puts the camera at the pilot's eye inside a detailed
F-22 cockpit: six colour displays, the Integrated Control Panel, the HUD with its combiner glass,
both consoles, the ejection seat, and a side-stick and twin throttles that move with your input.
Pressing **2** returns to the chase view behind the jet. Through the canopy you still see the
exterior model's nose and wings, so the two models have to line up.

Learning objectives:
- How a child model is placed in a parent's body frame when the two files use different axes and
  origins (a basis permutation with a reflection, plus a translation).
- How a skinned USD asset with a skeleton plugs into `UsdModel`, and how a single-axis procedural
  joint turns an input value into a rotation (`restTransform * rotation`).
- Why a first-person camera must sit exactly at the design eye point for a HUD to line up with the
  world, and what "collimated" means for a real HUD.
- Why emissive displays need a lighting term of their own, and how a baked texture can later be
  replaced by a live render target.

Not in scope:
- Drawing live HUD and MFD symbology from telemetry. Milestone 6 only builds the texture-swap hook
  and records the calibration it needs; the symbology renderer deserves its own research + plan.
- Clickable cockpit switches, a pilot body, canopy opening, and cockpits for the other aircraft.

## Terms

- **Design eye point (DEP)** — the point where the aircraft's designers put the pilot's eyes. HUD
  optics, over-the-nose view and display angles are all laid out from it. The cockpit model's
  origin is the DEP.
- **Body frame** — the aircraft node's local frame after import: metres, +X right, +Y up, +Z nose
  (left-handed), origin = the recentered center of mass for the Sketchfab F-22.
- **Native frame** — the coordinates stored in the cockpit file: metres, +X right, +Y forward,
  +Z up (Blender's right-handed, Z-up axes), origin = DEP.
- **Basis transform** — the 4x4 matrix `ModelLibrary` bakes into a model's vertices at import
  (row-vector convention `v_engine = v_native · B`). A determinant below zero means a reflection;
  `Mesh.reverseTriangleWinding()` then keeps faces front-facing.
- **UsdSkel / skeleton / joint** — USD's skinning schema. A skeleton is a list of joints (paths such
  as `CockpitRoot/StickRoll/StickPitch`), each with a rest transform relative to its parent.
- **Rigid skinning** — every vertex of a part is bound to exactly one joint with weight 1, so the
  part moves as a solid piece. All animated cockpit parts use it.
- **PMFD / SMFD / UFD** — primary multifunction display (8 x 8 in, centre), secondary
  multifunction displays (6.25 x 6.25 in, left, right and lower centre), up-front displays (3 x 4 in,
  either side of the ICP).
- **ICP** — Integrated Control Panel, the keypad under the HUD used for radio/navigation/autopilot
  data entry.
- **OSB** — option select button, one of the 20 push buttons around each MFD bezel.
- **HUD combiner** — the tilted glass plate the pilot looks through; the HUD projects symbology
  onto it.
- **Collimated** — focused at infinity. A real HUD's symbols stay fixed against the outside world
  when the pilot's head moves; symbology painted on the glass only lines up from the DEP.
- **Emission** — light a surface gives off by itself, added after lighting, so a display stays
  bright in shadow.
- **IDLE / MIL / AB** — throttle settings. IDLE is the lowest running thrust, MIL ("military power")
  the most thrust without afterburner, AB (afterburner) extra thrust from burning fuel in the exhaust.
- **Detent** — a notch you feel in a lever's travel. The F-22 throttle has detents at OFF, IDLE,
  MIL and AB.

## The idea in plain words

**The problem.** The cockpit is a second model that must sit inside the F-22 at the right place,
move some of its parts every frame, and host a camera that sees the HUD aligned with the world. The
cockpit file uses Blender's axes; the engine uses left-handed +Y-up/+Z-forward axes; and the F-22
body frame has its origin at the center of mass, far from the cockpit.

**The idea.** Author the cockpit in metres with its origin at the DEP. Then one permutation basis
(`Transform.transformXZYToXYZ`, native (x, y, z) → engine (x, z, y), determinant −1) converts the
axes, no meterization is needed, and placing the cockpit node at the aircraft's eye point
`eyePointInBodyFrame` puts every cockpit vertex where it belongs. The camera attaches at the same
point with zero offset. Moving parts are rigid-skinned to single-axis joints whose local axes equal
the native axes, so each joint maps to one `ProceduralJointConfig` — exactly the pattern the CGTrader
F-22's control surfaces already use.

**The steps.**
1. Register the model and add it as a child of the F-22 at the eye point (Milestone 1).
2. Add a cockpit camera and the 1/2 keys (Milestone 2).
3. Stop drawing the exterior's own crude interior and HUD glass so they do not poke through (Milestone 3).
4. Drive stick, throttles, pedals and gear handle from input through a cockpit animator (Milestone 4).
5. Add an emission term so displays glow (Milestone 5).
6. Give the HUD and display materials a replaceable texture for live symbology later (Milestone 6).

## Worked example

Inputs (from the asset build, `bc_controls.py`, `bc_common.py`):
- Stick pivot, native: (0.3635, 0.2330, −0.5810) m.
- Sketchfab F-22 eye point, body frame: (0, 1.12, 7.00) m. CGTrader F-22: (0, 1.08, 5.50) m.
- Throttle pivot 0.20 m below the console top; printed detents 0.06 m and 0.02 m either side of
  the slot centre. Afterburner threshold in `F22.doUpdate`: throttle > 0.8.
- Gear knob 0.030 m below the slot centre, pivot 0.10 m behind the panel face.
- HUD combiner: centre (0, 0.5205, −0.0483) native, tilted 8° with its top toward the pilot,
  barrel outline 0.180 m wide (at mid-height) x 0.165 m tall, texture 1024 x 939 px.

Step 1 — native → cockpit-local engine axes: (x, y, z) → (x, z, y) = (0.3635, −0.5810, 0.2330).
Step 2 — add the eye point: Sketchfab body frame (0.3635, 0.5390, 7.2330); CGTrader (0.3635, 0.4990, 5.7330).
Step 3 — throttle detent angles about the lever's local X (forward is negative):
AB = −asin(0.06/0.20) = −17.46°, MIL = −asin(0.02/0.20) = −5.74°, IDLE = +5.74°, OFF = +17.46°.
Step 4 — lever angle from throttle (piecewise, MIL at the afterburner threshold 0.8):
throttle 0.0 → +5.74° (IDLE), 0.4 → 0.00°, 0.8 → −5.74° (MIL), 0.9 → −11.60°, 1.0 → −17.46° (AB).
Channel value = angle / 17.46° → +0.329, 0.000, −0.329, −0.664, −1.000.
Step 5 — gear handle: rest (DOWN) sits atan(0.030/0.10) = 16.70° below the slot centre, so UP is a
−33.40° rotation about local X.
Step 6 — HUD calibration: the eye's straight-ahead ray meets the combiner at uv (0.500, 0.7956); one
degree is 51.01 px horizontally and 51.41 px vertically. The glass spans ±10.0° across and from 3.7°
above to 14.5° below the DEP line (the real HUD's field is mostly below the waterline). These values
are in `Textures/hud_geometry.json`.
Result: the stick base lands 0.54 m above and 0.23 m ahead of the Sketchfab jet's eye-level origin
line, on the right console; full throttle shows the lever 17.46° forward.

## Data, units, and conventions

| Quantity | Symbol | Name in pseudocode and code | Unit | Frame | Sign or convention |
|---|---|---|---|---|---|
| Eye point of an aircraft | e | `cockpitEyePointInBodyFrame` | m | aircraft body | Sketchfab (0, 1.12, 7.00); CGTrader (0, 1.08, 5.50) |
| Cockpit basis | B | `Transform.transformXZYToXYZ` | — | native → engine | row-vector, det −1 (winding reindexed) |
| Joint rotation | θ | `angle_rad` | rad | joint-local = native axes | `float4x4(rotateAbout:byAngle:)`: + turns clockwise seen from the axis tip (left-hand rule); about +X, + tips a part's top forward |
| Stick roll | θ_r | `stickRoll_rad` | rad | about native +Y | + = stick right; ±12° |
| Stick pitch | θ_p | `stickPitch_rad` | rad | about native +X | + = stick aft (pull); ±12°; the down arrow gives + (`pitchAxisFlipped` default) |
| Throttle lever | θ_t | `throttleLever_rad` | rad | about native +X | − = forward; IDLE +5.74°, MIL −5.74°, AB −17.46° |
| Gear handle | θ_g | `gearHandle_rad` | rad | about native +X | 0 = DOWN (rest), −33.40° = UP |
| Rudder pedal | θ_y | `pedal_rad` | rad | about native +X | + = pedal pushed forward; ±10°; yaw + (Q, nose left) pushes the left pedal forward |
| Throttle input | t | `ControlInput.throttle` / `.MoveFwd` | 0…1 | — | as read in `Aircraft.getControlInput()`; keyboard W = 1, S = −1 (clamped to IDLE) |
| MIL throttle setting | t_MIL | `F22.milPowerThrottleThreshold` | 0…1 | — | 0.8; the afterburners light above it |
| Emission | e | `MaterialProperties.emissive`, `Material.emissiveTexture` | linear RGB, 0…1 | — | added after lighting, outside the lit fraction; USD files only |

Joint table (from the file; paths as `MDLSkeleton.jointPaths` prints them):

| Joint path | Pivot, native (m) | Axis | Bound mesh |
|---|---|---|---|
| `CockpitRoot` | (0, 0, 0) | — | — |
| `CockpitRoot/StickRoll` | (0.3635, 0.2330, −0.5810) | Y | — |
| `CockpitRoot/StickRoll/StickPitch` | same pivot | X | `Stick` |
| `CockpitRoot/ThrottleLeft` | (−0.3951, 0.1190, −0.7710) | X | `Throttle_Left` |
| `CockpitRoot/ThrottleRight` | (−0.3579, 0.1190, −0.7710) | X | `Throttle_Right` |
| `CockpitRoot/GearHandle` | (−0.3605, 0.4140, −0.5621) | X | `GearHandle` |
| `CockpitRoot/PedalLeft` / `PedalRight` | (∓0.160, 0.960, −0.790) | X | `Pedal_Left` / `Pedal_Right` |

Update order: input is read in the aircraft's `doUpdate` on the UpdateThread; the cockpit animator
sets channel targets and `update(deltaTime:)` writes skin palettes in the same tick, before
`SceneManager.writeFrameSnapshot`. Camera selection happens in `GameScene.doUpdate` on the same
thread, so the frame's cascade fit, view matrix and camera position agree.
Engine conventions that apply: left-handed, +Z forward, reverse-Z main depth, metres, UpdateThread
ownership of the scene graph, lazy `ModelLibrary` factories (first access off the render thread).

## Engine integration points

- `AssetPipeline/Libraries/Models/ModelLibrary.swift` — new `ModelType` case and factory.
- `GameObjects/Aircraft.swift` — optional per-subclass eye point and cockpit model type; the
  cockpit node is created with the aircraft; from Milestone 4 it also owns and drives the cockpit animator.
- `GameObjects/F22.swift`, `GameObjects/F22_CGTrader.swift` — override the eye point; `F22` also
  names the afterburner throttle threshold (Milestone 4).
- New `GameObjects/Cameras/CockpitCamera.swift` — a look-only camera at the DEP.
- `Managers/InputManager.swift` — two `DiscreteCommand` cases mapped to `Keycodes.one` / `.two`.
- `Scenes/GameScene.swift` / `Scenes/FlightboxWithPhysics.swift` — register the cockpit camera,
  handle the keys, re-attach on aircraft swaps (`applyAircraftSwap`).
- `Animation/Animators/AircraftAnimator.swift` — the new `AnimationLayerID` cases only.
- `Animation/Animators/F22CockpitAnimator.swift` (next to `F22Animator`) and
  `Animation/Configs/F22CockpitAnimationConfig.swift` — the cockpit layers, the throttle mapping,
  and the per-layer setters (Milestone 4).
- `AssetPipeline/Material.swift`, the lighting shaders, and the deferred G-buffer and sun passes —
  emission (Milestone 5).
- Thread: all scene-graph, camera, and animator mutation on the UpdateThread.

## Design decisions and where they came from

- [design] Cockpit origin = DEP, metres, native axes; engine registration uses the existing
  `Transform.transformXZYToXYZ`, no `realWorldLength`, no `centerOfMassInImportFrame`. Rejected:
  authoring the cockpit in the F-22 body frame, which would tie the file to one exterior.
- [design] A reflecting basis (det −1) keeps the cockpit's handedness: throttle on the left, stick
  on the right. The CGTrader F-22's basis (det +1) draws that jet mirror-imaged, which is invisible
  on a symmetric airframe but would swap the cockpit's sides. [codebase] `Mesh.reverseTriangleWinding()`
  already handles det < 0 (Sketchfab F-22).
- [source: GlobalSecurity F-22 cockpit page; Wikipedia] Display sizes (8 in PMFD, 6.25 in SMFDs,
  3 x 4 in UFDs), centre ejection handle, 15° over-the-nose view (the glareshield lip sits 16.1° and the HUD base
  14.6° below the DEP), HUD 30° x 25° total FOV, side-stick right / throttles left.
- [design] Eye points measured, not published: the cockpit canopy was fitted to the Sketchfab
  canopy (surface table in `bc_common.CANOPY_PROFILE`); the CGTrader eye point was chosen so its
  canopy crown matches within 1 cm (0.304 vs 0.301 m above the eye at the pilot's station).
- [codebase] One degree of freedom per joint, bones pointing +Y with zero roll, so joint-local axes
  equal native axes and each joint is one `ProceduralJointConfig` (same as
  `F22AnimationConfig.createAileronLayer`). The stick is a two-joint gimbal (roll parent, pitch child).
- [design] The first-person camera is a new look-only camera, not a second `AttachedCamera`:
  `AttachedCamera.doUpdate` translates on the wheel, middle-drag and i/j/k/l, and any translation
  moves the eye off the DEP and misaligns the HUD.
- [design] Keys select camera instances (`CameraManager.SetCamera(_:)`), not slots. The earlier idea
  "number key N = slot N−1" (`c_key_camera_toggle.md`) would put the cockpit at slot 0 and change the
  default and 'C' order; direct instance selection keeps chase as the default view.
- [design] Hide the Sketchfab jet's `f22a_cockpit` and `HudGlass` submeshes permanently (both views),
  because the new cockpit replaces them visibly in both views. Rejected: toggling per view, which
  needs a `SetRenderableHidden` round trip to rebuild the model's draw lists.
- [design] Throttle lever mapping puts MIL at throttle 0.8, the same threshold `F22.doUpdate` uses
  to light the afterburners, so the lever crosses the MIL gate when the plumes appear. The value is
  named once, `F22.milPowerThrottleThreshold`, and both read it.
- [design] The cockpit setters live on `F22CockpitAnimator`, not on the `AircraftAnimator` base. A
  base-class setter would also exist on `F22Animator` and `F35Animator`, where no cockpit layer is
  registered, so it could only print "No … layer registered" there. Rejected: the base class, as
  `deflectHorizontalStabilizers` does (it names `F22AnimationConfig` channel IDs inside the base;
  don't copy that). Only the `AnimationLayerID` cases go in `AircraftAnimator.swift`, because that
  enum is the one list of layer IDs [codebase: `.claude/rules/animation.md`].
- [design] The throttle mapping is static on `F22CockpitAnimationConfig`, next to the detent angles
  and `throttleMaxDeflection`. The mapping divides by that constant and the channel multiplies by
  it, so one definition keeps the two inverse. Static and free of `UsdModel`, so the tests need no
  Metal. Rejected: a separate `CockpitControlMapping` type, which would read every constant from the
  config anyway.
- [codebase] The animator looks up its five channels once at init and keeps the references, as
  `AnimationLayerSystem` resolves joints once at registration (`.claude/rules/animation.md`). The
  channel IDs are static constants read by both the layer builders and the animator, as
  `F22AnimationConfig.horizontalStabLeftChannelID` is.
- [design] `Aircraft` owns the cockpit animator: both F-22s mount the cockpit through
  `attachCockpit`, so one copy in the base class drives both. It is fed the `controlInput` the
  flight model reads, so the stick shows what the jet is commanded. The property's type is the
  concrete `F22CockpitAnimator`, because only one cockpit exists (no abstraction for a
  hypothetical second one).
- [codebase] The gear handle follows the exterior animator's `gearState` (`.down` or `.extending`
  = DN) and stays DN for an aircraft without an exterior animator. The Sketchfab `F22` never calls
  `setupAnimator`, so its `handleGearToggle` does nothing and `isGearDown` is always true: its gear
  is fixed down, and a handle that stays DN tells the truth.
- [source: OpenGL 2.1 specification §2.14.1; Kajiya 1986] Emission is added once per fragment,
  outside the sum over lights: `color = emission + Σ ShadeDirectionalBlinnPhong(light)`, and the
  per-light function takes no emission input. Rejected: an `emission` input on the per-light
  function (the first Milestone 5 version), which the forward loop added once per light, so two
  suns doubled every display.
- [design] Deferred renderers carry emission in the lighting target: the G-buffer stage writes it
  there, the sun pass reads it back. Rejected: a fourth G-buffer target (more tile memory and
  bandwidth for a term most pixels leave at 0).
- [design] HUD symbology is baked for now (pitch 2.5°, heading 119°) and calibrated from the DEP;
  Milestone 6 replaces the texture.
- [source: owner's reference photos] Display faces flat and vertical (no tilt, no cant), ICP proud of
  the display plane out to the HUD glass plane, glareshield hood and side glare shields jutting aft,
  HUD frame thin across and deep fore-aft with forward-pointing anti-glare tabs, right-triangle stick
  head with an outward kink in the hypotenuse, D-shaped throttle grips.

## Verification commands

```bash
# Build the app and the test bundle (the scheme's Build action builds the app only)
xcodebuild build-for-testing -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run one suite, serial per project rule
xcodebuild test-without-building -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  -only-testing:"ToyFlightSimulatorTests/CockpitControlMappingTests" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Re-check the asset itself (Model I/O, no engine code)
swift ~/Desktop/BlenderProjects/ToyFlightSimulator/F22_Cockpit/Tools/verify_cockpit_usdz.swift \
  "ToyFlightSimulator Shared/Core/Resources/Models/F22_Cockpit/F22_Cockpit.usdz"
```

## Milestones

### Milestone 1 — Register the cockpit model and mount it in the F-22 ✅ (landed 2026-09-27, 25f61c9)

- **Learning objective:** place a child model in a parent's body frame through a basis permutation
  plus a translation, and see why the reflection matters for an asymmetric object.
- **Prerequisites:** Terms "native frame", "body frame", "basis transform".
- **Engine integration points:** `ModelLibrary` (`ModelType`, `makeLibrary`), `Aircraft`, `F22`,
  `F22_CGTrader`, `SceneManager.SetScene` warm-up (optional).
- **Algorithm:**

```pseudocode
// ModelLibrary: the cockpit is authored in metres with its origin at the design eye point.
engine: register(.F22_Cockpit) -> UsdModel("F22_Cockpit", fileExtension: USDZ,
                                            basisTransform: Transform.transformXZYToXYZ)
        // no realWorldLength (already metres), no centerOfMassInImportFrame (origin = eye point)

// Aircraft base: optional cockpit, off by default.
property cockpitModelType -> ModelType or none           // override per aircraft
property cockpitEyePointInBodyFrame_m -> vector3          // body frame, metres

// Called once where the aircraft builds its children (after its own model is set up).
function attachCockpit(aircraft)
    if aircraft.cockpitModelType is none
        return
    cockpitNode = new GameObject(name: "F-22 Cockpit", modelType: aircraft.cockpitModelType)
    cockpitNode.position = aircraft.cockpitEyePointInBodyFrame_m   // cockpit origin = eye point
    aircraft.addChild(cockpitNode)                                  // registers with SceneManager
    aircraft.cockpit = cockpitNode

// F22: cockpitModelType = F22_Cockpit, eye point (0, 1.12, 7.00)
// F22_CGTrader: cockpitModelType = F22_Cockpit, eye point (0, 1.08, 5.50)

// Pure static helper (Aircraft.cockpitNativeToBody) for the tests below: where a native
// cockpit point lands in the body frame.
function cockpitNativeToBody(nativePoint_m, eyePointInBodyFrame_m) -> bodyPoint_m
    engineLocal = (nativePoint_m.x, nativePoint_m.z, nativePoint_m.y)   // transformXZYToXYZ, row-vector
    return engineLocal + eyePointInBodyFrame_m
```

- **Tests** (Metal-free where possible):
  - [x] `CockpitGeometryTests.stickPivotLandsOnRightConsole` — native (0.3635, 0.2330, −0.5810)
    with eye (0, 1.12, 7.00) → (0.3635, 0.5390, 7.2330) within 1e-4 m; x > 0 (right side).
  - [x] `CockpitGeometryTests.stickPivotInTheCGTraderF22` — same pivot, eye (0, 1.08, 5.50) →
    (0.3635, 0.4990, 5.7330).
  - [x] `CockpitGeometryTests.helperMatchesTheImportBasis` — for five native points (stick, left
    throttle, gear handle, right pedal pivots and (1, 2, 3)) the helper equals v · `Transform.transformXZYToXYZ`,
    so the hand-written axis swap is the basis the model is actually baked with.
  - [x] `CockpitGeometryTests.basisIsAReflection` — determinant of the 3x3 part of
    `Transform.transformXZYToXYZ` is −1.
  - [x] App-hosted: `CockpitModelTests.skeletonHasTheRigJoints` — `Assets.Models[.F22_Cockpit]` is a
    `UsdModel` with one skeleton whose `jointPaths` contain the eight paths in the joint table, and six
    meshes with a `skin`.
  - [x] App-hosted: `CockpitModelTests.restPosePaletteIsIdentity` — build a fresh
    `UsdModel("F22_Cockpit", fileExtension: USDZ, basisTransform: Transform.transformXZYToXYZ)` in the
    test, not `Assets.Models[.F22_Cockpit]`: the host app's scene shares that instance, and from
    Milestone 4 its animator rewrites the palettes (the IDLE throttle sits at +5.74°, not at rest). Then
    the skeleton's `currentPose.count` is 8, and for each of the six skinned meshes every matrix in
    `skin.jointMatrixPaletteBuffer` (`skin.jointPaths.count` of them) equals the identity within
    `defaultTolerance` (1e-4). Why identity: each joint's composed rest transform equals its bind
    transform, so world rest × inverse bind = I, and conjugating I by the basis leaves I. This is the
    regression test for the empty-`currentPose` crash: the rig ships with no animation clip, so before
    `dd36871` (`Skeleton.init?` evaluates the rest pose) nothing filled the pose before
    `Skin.updatePalette` read it.
- **Observable completion criteria:** in the chase view, the cockpit is visible through the canopy:
  gray consoles, the HUD hoop above the glareshield, the seat headbox under the canopy crown, the
  side-stick on the right. Nothing pokes through the fuselage skin. The log shows
  `[UsdModel init] ... Num skeletons: 1`.
- **Edge cases and expected results:**
  - Aircraft without a cockpit (F-16, F-18, F-35) → no node, no change.
  - Aircraft swap F-22 → F-35 → F-22 → the cockpit node leaves with its aircraft
    (`SceneManager.RemoveObject` unregisters the subtree) and a new one is added; one cockpit at a time.
  - CGTrader F-22 → the canopy glass and aft canopy frame of the cockpit extend a few centimetres
    outside that jet's narrower canopy near the aft end (measured: 401 of 700 glass vertices outside
    the CGTrader skin). Acceptable from inside; hide `Canopy_Glass` for that jet if it shows outside.

### Milestone 2 — Cockpit camera and the 1 / 2 keys ✅ (landed 2026-09-27, 25f61c9)

- **Learning objective:** why the camera must be at the DEP with look-only freedom, and how camera
  selection stays on the UpdateThread.
- **Prerequisites:** Milestone 1; `plans/claude/c_key_camera_toggle.md` (registry, `isActiveCamera`).
- **Engine integration points:** new `CockpitCamera` (subclass of `Camera`, parented like
  `AttachedCamera`), `InputManager` (`DiscreteCommand`, `keyboardMappingsDiscrete`), `GameScene.doUpdate`
  (next to `.CycleCamera`), `FlightboxWithPhysics.applyAircraftSwap` (re-attach), `GameScene.addCamera`.
- **Algorithm:**

```pseudocode
// CockpitCamera: sits at the eye point, rotates only (head look), never translates.
// yaw and pitch are head angles relative to the aircraft's nose; clamps keep the head human.
// headYaw_rad: + looks right. headPitch_rad: + looks up.
constant maxHeadYaw_rad = 150°   ;  maxHeadPitchUp_rad = 70°  ;  maxHeadPitchDown_rad = 80°

// Pure helpers (static on CockpitCamera), so the tests need no camera.
function turnedHead(yaw_rad, pitch_rad, yawDelta_rad, pitchDelta_rad) -> (yaw_rad, pitch_rad)
    return (clamp(yaw_rad + yawDelta_rad, -maxHeadYaw_rad, maxHeadYaw_rad),
            clamp(pitch_rad + pitchDelta_rad, -maxHeadPitchDown_rad, maxHeadPitchUp_rad))
function headRotation(yaw_rad, pitch_rad) -> rotation
    // Yaw about the cockpit's up axis, then pitch about the turned head's right axis:
    // Ry(yaw) · Rx(−pitch) with column vectors. This order never rolls the head. A positive
    // angle about +X tips +Z (forward) down, hence −pitch for "+ looks up".
    return rotationY(yaw_rad) * rotationX(-pitch_rad)

function cockpitCameraDoUpdate(camera, deltaTime_s)
    if not camera.isActiveCamera
        return                                              // parented: runs even when not current
    if right mouse button held
        turnPerPixel = deltaTime_s * turnSpeed              // as AttachedCamera
        // NSEvent's deltaY is + for a downward move, so dragging down looks down.
        (camera.headYaw_rad, camera.headPitch_rad) = turnedHead(camera.headYaw_rad, camera.headPitch_rad,
                                                                mouseDX * turnPerPixel, -mouseDY * turnPerPixel)
        camera.localRotation = headRotation(camera.headYaw_rad, camera.headPitch_rad)
    if middle mouse button or the 0 key held
        recenterHead(camera)                                // yaw = pitch = 0, identity rotation
    // position stays (0, 0, 0) relative to the cockpit node = the eye point

// Attach: parent to the cockpit node at zero offset, so the camera and the cockpit share one origin.
function attachCockpitCamera(camera, aircraft) -> Bool
    camera.detachFromParent()                               // always leave the previous jet
    if aircraft.cockpit is none
        return false                                        // left unparented
    camera.position = (0, 0, 0) ; recenterHead(camera)
    aircraft.cockpit.addChild(camera)
    aircraft.cockpitCamera = camera
    return true

// InputManager: two new discrete commands.
engine: DiscreteCommand.CockpitView -> Keycodes.one
engine: DiscreteCommand.ChaseView   -> Keycodes.two

// GameScene.doUpdate (UpdateThread), next to the existing CycleCamera block:
engine: InputManager.HasDiscreteCommandDebounced(command: CockpitView) ->
            if playerAircraft has a cockpit: CameraManager.SetCamera(cockpitCamera)
engine: InputManager.HasDiscreteCommandDebounced(command: ChaseView) ->
            CameraManager.SetCamera(attachedCamera)

// FlightboxWithPhysics.applyAircraftSwap, for every aircraft type:
wasInCockpitView = cockpitCamera.isActiveCamera     // read before the chase camera is made current
addCamera(attachedCamera) ; re-attach it            // makes the chase camera current
if attachCockpitCamera(cockpitCamera, playerAircraft)
    addCamera(cockpitCamera, isCurrent: wasInCockpitView)   // registration dedupes
else
    engine: CameraManager.UnregisterCamera(cockpitCamera)   // 'C' must not reach a camera left in the old jet
```

- **Tests** (Metal-free where possible):
  - [x] `CockpitCameraHeadLookTests.headAnglesClamp` — 10 s at 60 Hz of a hard drag (0.83 rad per
    tick) leaves yaw at +150° and pitch at +70°; the reverse drag leaves −150° and −80° (pure `turnedHead`).
  - [x] `CockpitCameraHeadLookTests.headRotationDirections` — yaw +90° maps forward (0, 0, 1) to (1, 0, 0);
    pitch +30° maps it to (0, 0.5, 0.8660).
  - [x] `CockpitCameraHeadLookTests.combinedTurnKeepsTheHorizonLevel` — yaw 90° + pitch 30° looks at
    (0.8660, 0.5, 0) with the head's right axis level (y = 0).
  - [x] App-hosted: `CockpitCameraAttachTests.positionNeverMoves` — after 200 head turns and a recentre
    the local position is (0, 0, 0) and the rotation matches `headRotation`.
  - [x] App-hosted: `CockpitCameraAttachTests` attach cases — attach parents the camera to the cockpit
    node at zero offset and recentres the head; re-attaching leaves the old cockpit; a jet without a
    cockpit returns false and leaves the camera unparented.
  - [x] Existing `CameraManagerCycleTests` still pass (they test the pure `nextCameraIndex` rule).
    With the cockpit camera registered inside `applyAircraftSwap`, the 'C' order becomes
    chase → cockpit → debug (registration order).
- **Observable completion criteria:** press 1: the view matches the Blender render
  `Reference/_previews/final_pilot.png` — HUD centred on the hood, ICP below it, PMFD centred,
  SMFDs flat beside it, lower SMFD between the knees. The HUD's waterline "W" is near the top of the
  glass; in level flight at 2.5° nose-up the baked horizon line lies on the real horizon. Press 2: back to the chase view. Right-drag looks
  around; the eye stays put.
- **Edge cases and expected results:**
  - Press 1 in the F-35 → no-op (no cockpit), the view stays on chase.
  - Swap aircraft while in the cockpit view → the view stays in the new jet's cockpit if it has
    one, else falls back to chase.
  - Swap F-22 → F-35 → F-22 → the F-35 takes the cockpit camera out of the registry, and the F-22
    re-registers it at the end: the 'C' order becomes chase → debug → cockpit. The 1 key selects it
    by instance, so only the cycle order changes.
  - Near plane: 0.01 m (as the chase camera) is enough; the closest cockpit geometry in the forward
    view (the combiner's top edge) is about 0.50 m from the eye, the headrest pad about 0.21 m behind it.

### Milestone 3 — Hide the exterior's interior and HUD glass ✅ (landed 2026-09-27, 25f61c9)

- **Learning objective:** how `shouldRenderSubmesh` shapes a model's draw lists at registration.
- **Prerequisites:** Milestone 1.
- **Engine integration points:** `GameObject.shouldRenderSubmesh(_ submesh: Submesh)` override on
  `F22`; `SceneManager.CreateModelData` (where it is evaluated).
- **Algorithm:**

```pseudocode
// Sketchfab F-22 submeshes by material (measured with Model I/O):
//   Object_2 "f22a_cockpit"  (1,468 tris, crude interior)   -> hide: it intersects the new cockpit
//   Object_3 "HudGlass"      (16 tris)                       -> hide: the new HUD has its own combiner
//   Object_1 "Glass"         (canopy, faces outward)         -> keep: culled from inside, seen from outside
// Pure static helper (F22.shouldRenderExteriorSubmesh); the override passes the submesh's
// material name and whether this jet has a cockpit.
function shouldRenderExteriorSubmesh(materialName, hasCockpit) -> Bool
    if not hasCockpit or materialName is none
        return true
    return materialName not in {"f22a_cockpit", "HudGlass"}   // F22.materialsReplacedByCockpit
```

- **Tests** (Metal-free where possible):
  - [x] `F22SubmeshFilterTests.hidesInteriorOnlyWhenCockpitPresent` — pure helper over material names:
    {"f22a_cockpit", "HudGlass"} → false with a cockpit, true without; "f22a_airframe", "Glass",
    "f22a_landingLights" and a missing material → true (`keepsTheExterior`, `keepsASubmeshWithoutAMaterial`).
  - [x] App-hosted: `F22SubmeshFilterTests.sketchfabModelHasTheReplacedMaterials` — the loaded
    Sketchfab model's submesh materials include both hidden names and `Glass`, so a rename cannot
    turn the filter into a silent no-op.
- **Observable completion criteria:** in the cockpit view there is no flickering gray geometry
  through the consoles or a second small HUD glass behind the combiner.
- **Edge cases and expected results:**
  - The filter is evaluated only when the model's draw data is created; the F-22 always has the
    cockpit, so no toggling is needed.
  - Two F-22s in one scene share one `ModelData` → both hide the interior (intended).

### Milestone 4 — Animate stick, throttles, pedals and gear handle ✅ (landed 2026-09-28, be87bfd)

- **Learning objective:** turn an input value into a joint rotation with a procedural channel, and
  map a nonlinear lever travel (detents) with a pure, testable function.
- **Prerequisites:** Milestone 1; `procedural-animation-plan.md`; the joint table above; Terms
  "IDLE / MIL / AB" and "detent".
- **Engine integration points:**
  - `Animation/Animators/AircraftAnimator.swift` — the four `AnimationLayerID` cases only
    (`cockpitStick`, `cockpitThrottle`, `cockpitRudderPedals`, `cockpitGearHandle`). No cockpit
    setters in the base class (see Design decisions).
  - `Animation/Configs/F22CockpitAnimationConfig.swift` — the layers (`createLayers`,
    `findJointPaths`), the detent angles, the five channel IDs as static constants, and the pure
    throttle mapping.
  - `Animation/Animators/F22CockpitAnimator.swift` — keeps the five channels after `setupLayers`,
    has one setter per layer, and the pure gear-handle rule.
  - `GameObjects/Aircraft.swift` — a `cockpitAnimator` property, built in `attachCockpit`, driven
    in `doUpdate`.
  - `GameObjects/F22.swift` — `milPowerThrottleThreshold`, read by `doUpdate` and by the mapping.
  - Thread: UpdateThread (the aircraft's `doUpdate`), as for the exterior animator.
- **Algorithm:**

Symbols: θ = joint angle (rad), v = channel value, θ_max = `maxDeflection`; the channel computes
θ = v · θ_max (sign flipped when `inverted`), applied as `restTransform * rotation(axis, θ)`.
`rotation` is the engine's `float4x4(rotateAbout:byAngle:)`, the transpose of the right-handed
axis-angle matrix: a positive θ turns a part clockwise seen from the tip of its axis (left-hand
rule). About native +X, a positive θ tips a part's top forward.
t = throttle input after clamping to 0…1; t_MIL = `F22.milPowerThrottleThreshold` = 0.8.

```pseudocode
// F22CockpitAnimationConfig — constants, named as in the code
constant sideStickMaxDeflection = 12°       // visual only: the real F-22 stick is force-sensing, ~1/4 in throw
constant throttleMaxDeflection = 17.46°     // AB detent = asin(0.06 m / 0.20 m)
constant idleThrottleSpace = +5.74° ; milThrottleSpace = -5.74° ; afterburnerThrottleSpace = -17.46°   // forward is negative
constant gearLeverDeflection = 33.40°       // 2 * atan(0.030 m / 0.10 m)
constant rudderPedalsMaxDeflection = 10°
// Channel IDs, read by the layer builders below and by F22CockpitAnimator
constant sideStickRollChannelID = "sideStickRoll" ; sideStickPitchChannelID = "sideStickPitch"
constant throttleChannelID = "cockpitThrottle" ; rudderPedalsChannelID = "rudderPedals"
constant gearHandleChannelID = "gearHandle"

// findJointPaths(model, suffixes...) -> one joint path (or none) per suffix, in the same order.
// A parameter pack; its doc comment in the config explains the pack and cites SE-0393.
// Each inverted flag makes a positive input move the part in its positive direction.
layer cockpitStick:
    channel sideStickRollChannelID:  range (-1, 1), speed 8/s, joint StickRoll,  axis (0, 1, 0),
                                     max sideStickMaxDeflection, inverted true      // + = stick right
    channel sideStickPitchChannelID: range (-1, 1), speed 8/s, joint StickPitch, axis (1, 0, 0),
                                     max sideStickMaxDeflection, inverted true      // + = stick aft
layer cockpitThrottle:
    channel throttleChannelID: range (-1, 1), speed 3/s, joints ThrottleLeft and ThrottleRight,
                               axis (1, 0, 0), max throttleMaxDeflection, inverted true   // v = -1 -> lever forward (AB)
layer cockpitRudderPedals:
    channel rudderPedalsChannelID: range (-1, 1), speed 4/s, axis (1, 0, 0), max rudderPedalsMaxDeflection,
                                   joints PedalLeft (inverted true) and PedalRight (inverted false)
                                   // each pedal hangs from its top hinge: + θ swings its foot aft
layer cockpitGearHandle:
    channel gearHandleChannelID: range (0, 1), speed 3/s, joint GearHandle, axis (1, 0, 0),
                                 max gearLeverDeflection, inverted false    // v = 1 -> +33.40 deg = UP

// F22CockpitAnimationConfig — the pure throttle mapping (static, Metal-free)
function throttleLeverAngle(throttleInput) -> leverAngle_rad
    t = clamp(throttleInput, 0, 1)                         // keyboard S gives -1, which clamps to IDLE
    milSetting = F22.milPowerThrottleThreshold             // 0.8
    if t <= milSetting
        return idleThrottleSpace + (milThrottleSpace - idleThrottleSpace) * (t / milSetting)       // IDLE .. MIL
    return milThrottleSpace + (afterburnerThrottleSpace - milThrottleSpace)
                              * ((t - milSetting) / (1 - milSetting))                            // MIL .. AB
function throttleChannelValue(throttleInput) -> channelValue
    return throttleLeverAngle(throttleInput) / throttleMaxDeflection    // the channel multiplies back

// F22CockpitAnimator — in setupLayers, keep each channel as it is registered, matched by its ID.
// Per-tick setters then do no string lookups. A channel that is missing stays none and its setter does nothing.
function setSideStick(pitchInput, rollInput)
    sideStickPitchChannel.setValue(pitchInput)              // + = stick aft (down arrow)
    sideStickRollChannel.setValue(rollInput)                // + = stick right (right arrow)
function setThrottles(throttleInput)
    throttleChannel.setValue(throttleChannelValue(throttleInput))
function setRudderPedals(yawInput)
    rudderPedalsChannel.setValue(yawInput)                  // + (Q, nose left) = left pedal forward, right pedal aft
function setGearHandle(gearDown)
    gearHandleChannel.setValue(gearDown ? 0 : 1)

// F22CockpitAnimator — pure static rule: which way the handle points.
function gearHandleCommandedDown(exteriorGearState) -> Bool
    return exteriorGearState is down or extending           // the handle leads the gear, like the real lever

// Aircraft.attachCockpit (existing) — after the cockpit node is added:
if cockpitNode.model is a UsdModel
    aircraft.cockpitAnimator = new F22CockpitAnimator(that UsdModel)
else
    print a warning, as setupAnimator does; cockpitAnimator stays none

// Aircraft.doUpdate (existing), UpdateThread. New lines are marked.
if shouldUpdateOnPlayerInput and hasFocus
    controlInput = getControlInput()
    ...                                                     // flight input, unchanged
    handleGearToggle()                                      // toggles the exterior gear first ...
    updateCockpitControls(controlInput)                     // NEW: ... so the handle moves in the same tick
else
    ...                                                     // unchanged
animator.update(deltaTime_s)                                // unchanged
cockpitAnimator.update(deltaTime_s)                         // NEW, outside the guard: parts finish their travel
                                                            // when focus drops; writes the skin palettes

function updateCockpitControls(aircraft, controlInput)
    if aircraft.cockpitAnimator is none
        return
    cockpitAnimator.setSideStick(controlInput.pitch, controlInput.roll)
    cockpitAnimator.setThrottles(controlInput.throttle)
    cockpitAnimator.setRudderPedals(controlInput.yaw)
    // No exterior animator (the Sketchfab F22) means the gear is fixed down: pass down.
    exteriorGearState = aircraft.animator's gearState, or down when it has no animator
    cockpitAnimator.setGearHandle(gearHandleCommandedDown(exteriorGearState))

// F22.doUpdate: lights the afterburners above F22.milPowerThrottleThreshold (was the literal 0.8).
```

- **Tests** (Metal-free where possible), in `ToyFlightSimulatorTests/Animation/`:
  - [x] `CockpitControlMappingTests.throttleWorkedExample` — throttle 0.0, 0.4, 0.8, 0.9, 1.0 →
    +5.74°, 0.00°, −5.74°, −11.60°, −17.46° (±0.01°); `throttleChannelValue` +0.329, 0.000,
    −0.329, −0.664, −1.000 (±0.001).
  - [x] `CockpitControlMappingTests.throttleBelowZeroIsIdle` — −0.5 and −1.0 (keyboard S) → exactly
    `idleThrottleSpace`; `throttleAboveOneIsAfterburner` — 1.7 → `afterburnerThrottleSpace` (1e-6 rad).
  - [x] `CockpitControlMappingTests.milDetentSitsAtTheAfterburnerThreshold` —
    `throttleLeverAngle(F22.milPowerThrottleThreshold)` equals `milThrottleSpace` within 1e-6 rad,
    so the lever reaches the MIL gate exactly when the plumes light.
  - [x] `CockpitControlMappingTests.gearHandleDownWhileGearCommandedDown` (`.down`, `.extending` →
    true) and `gearHandleUpWhileGearCommandedUp` (`.up`, `.retracting` → false).
  - [x] App-hosted: `CockpitAnimatorTests.registersSevenJointConfigs` — build a fresh
    `UsdModel("F22_Cockpit", fileExtension: USDZ, basisTransform: Transform.transformXZYToXYZ)` (as
    `restPosePaletteIsIdentity` does, so the host app's shared model is untouched), then an
    `F22CockpitAnimator` on it: `channelCount` is 5, the four cockpit layers are registered, all five
    channel properties are set, and their `jointConfigs` hold the seven rig joints below the root,
    each one in the skeleton's `jointPaths`.
  - [x] App-hosted direction tests, `CockpitAnimatorTests`. Each sets one input through the
    animator's setter, updates for 1 s (longer than any channel's travel), reads the joint's matrix
    from the skinned mesh's palette buffer (what the GPU skins with), and checks where it moves a
    probe point, as a displacement from the joint's pivot in the cockpit's engine frame (+X right,
    +Y up, +Z forward), within 1e-4 m:
    - `stickPitchPullsAft` — pitch +1, a point 0.15 m up the stick → (0, 0.14672, −0.03119).
    - `stickRollGoesRight` — roll +1 → (0.03119, 0.14672, 0) (the `Stick` mesh is bound to
      `StickPitch`, the child of `StickRoll`).
    - `fullThrottleReachesAfterburnerDetent` — throttle 1, 0.20 m up each lever → (0, 0.19079,
      0.06000): 0.06 m forward, on the printed AB detent.
    - `zeroThrottleSitsAtIdleDetent` — throttle 0 → (0, 0.19900, −0.02000), on the IDLE detent.
    - `leftYawPushesLeftPedal` — yaw +1, 0.15 m below each hinge → left (0, −0.14772, +0.02605),
      right (0, −0.14772, −0.02605).
    - `gearHandleUpRaisesTheKnob` — the knob (0.10 m aft of the pivot, 0.030 m below the slot
      centre) at rest (0, −0.030, −0.10), after gear UP (0, 0.030, −0.10).
- **Observable completion criteria:** the log shows `[F22CockpitAnimator] Initialized with 5
  channels` and no `joint not found` warning. In the cockpit view (1): the right arrow tilts the
  stick right; the down arrow pulls it aft; holding W runs both throttle grips forward past the MIL
  gate to AB in about 0.44 s as the afterburner plumes light, and releasing W brings them back to
  IDLE; Q pushes the left pedal forward and the right pedal aft, E the reverse. In the CGTrader F-22,
  G swings the gear handle UP (knob 16.7° above the slot centre) ahead of the gear animation, and G
  again brings it DN. In the Sketchfab F-22, G does nothing and the handle stays DN.
- **Edge cases and expected results:**
  - A part moves the wrong way → a direction test in `CockpitAnimatorTests` fails first; flip that
    joint's `inverted`. Derive flags from the engine's rotation sign (Symbols above), not from the
    right-hand rule: the first version of this plan did that and had all seven backwards.
  - Sketchfab F-22 → no exterior animator, so `updateCockpitControls` passes `.down` and the handle
    stays DN, matching that jet's fixed-down gear. Check G in the CGTrader F-22.
  - Before the first player tick the throttle channel sits at its initial value 0: levers vertical,
    between IDLE and MIL (the rest pose). The first tick moves them to IDLE in about 0.11 s.
  - Keyboard throttle: `.MoveFwd` is −1 with S; the mapping clamps it to IDLE. The keyboard gives
    only 0 or 1, so the lever travels IDLE ↔ AB; a HOTAS throttle stops at every point between.
  - The model is shared by every F-22 instance (one `Model` per `ModelType`), so the pose is shared.
    Each F-22 builds its own cockpit animator, and only the player's sets values. No scene has two
    F-22s today. If one ever does, the second animator writes the rest pose once (at init) over the
    player's, and it stays until the player's input changes. Fix it then by building the cockpit
    animator only when `shouldUpdateOnPlayerInput` is true.
  - Aircraft swap → the old jet's animator leaves with the old aircraft; the new jet builds its own
    in `attachCockpit` on the UpdateThread (`applyAircraftSwap` constructs the aircraft there).

### Milestone 5 — Emission term for displays, HUD and indicator lenses ✅ (landed 2026-09-30, 56dbe0d)

- **Learning objective:** why emissive surfaces bypass lighting, why only the USD dialect may
  read `.emission` (Model I/O stores an OBJ's `Ka` there), and how a deferred renderer carries a
  per-pixel term that has no G-buffer channel.
- **Prerequisites:** `research/claude/modelio_material_semantics_blinn_phong_2026-09-21.md` §1.2;
  Term "Emission".
- **Engine integration points:**
  - `AssetPipeline/Material.swift` — `readsEmission(from:)` (USD only), `properties.emissive` (a
    constant `emissiveColor`, read in `setProperties`) and `emissiveTexture` (a texture-typed
    `emissiveColor`, loaded sRGB by `populateMaterial` with the other maps). The file format
    reaches `Material` as `sourceFileFormat`: `Model.GetMeshes` → `Mesh` → `Submesh` → `Material`;
    `SingleSubmeshMesh.createSingleSMMeshFromModel` maps its extension string.
  - `TFSCommon.h` — `MaterialProperties.emissive`; `TFSTextureIndexEmissive = 3` (the shadow array and
    every later index move up by one). `DrawManager.applyMaterialTextures` binds the map per submesh.
  - `ShaderHelpers.h` — `ResolveEmission`, the cascade every fragment uses.
  - `Lighting::ShadeDirectionalBlinnPhong` — one light's `ambient + litFraction · (diffuse + specular)`,
    with no emission input; every caller adds the emission once, outside its sum over lights.
  - Forward and transparent fragments (`material_fragment`, `transparent_material_fragment`,
    `single_pass_deferred_transparency_fragment`, `tiled_deferred_transparency_fragment`) add
    `ResolveEmission` to the lit color.
  - Deferred renderers: the G-buffer fragments (`gbuffer_fragment_material`,
    `tiled_deferred_gbuffer_fragment`; the terrain writes 0) write emission into the lighting
    target (`GBufferData.lighting`, `GBufferOut.lighting`), and the sun passes
    (`deferred_directional_lighting_fragment`, `tiled_deferred_directional_light_fragment`) read it back.
- **Algorithm:**

Symbols: e = emission (linear RGB, 0…1 from the file) = `emission`; L_i = light i's term from
`Lighting::ShadeDirectionalBlinnPhong`, ambient_i + litFraction · (diffuse_i + specular_i).
color = e + Σ_i L_i: e is added once, outside the sum over lights and outside the lit fraction, so
it stays bright in shadow and at night and does not grow with the number of lights. This is the
structure of the OpenGL lighting equation (material emission `e_cm` outside the sum over lights,
each light's ambient inside it) and the single emitted term of the rendering equation; see
References. No emission strength: UsdPreviewSurface has none, the exporter bakes it into
`emissiveColor`.

```pseudocode
// Import (Material). sourceFileFormat is the format of the file the material came from.
function readsEmission(sourceFileFormat) -> Bool
    return sourceFileFormat is USDC or USDZ      // OBJ: .emission holds the MTL Ka line (Blender writes 1 1 1)
if readsEmission(sourceFileFormat)
    if .emission is a texture: material.emissiveTexture = load(texture, srgb: true)
    else if .emission is a float3: material.emissive = that value   // Model I/O's default when none is authored: 0 0 0

// Shaders: the emission of one fragment.
function resolveEmission(useObjectColor, materialEmission, emissionMap, baseColorUV) -> linearRGB
    if useObjectColor: return 0                 // a setColor object shows a flat color, like its normal map
    if emissionMap is bound: return sample(emissionMap, baseColorUV)   // no emission UV-transform slot
    return materialEmission

// The shared per-light function (no emission input, so a loop cannot count emission twice):
function shadeDirectional(albedo, normal, light, ...) -> linearRGB
    return ambient + litFraction * (diffuse + specular)

// Forward pass, several lights:
color = resolveEmission(...)                    // once, before the sum
for each light: color += shadeDirectional(albedo, normal, light, ...)

// Transparent passes (one sun): color = resolveEmission(...) + shadeDirectional(...)

// Deferred renderers. The G-buffer targets have no free channel, so the lighting target carries it.
G-buffer stage, each opaque fragment (depth-tested, not blended):
    lightingTarget = (resolveEmission(...), 1)  // replaces the clear color; 0 where nothing glows
Sun pass, each covered pixel (reads the tile's attachments):
    emission = lightingTarget.rgb
    lightingTarget = emission + shadeDirectional(albedo, normal, sun, ...)   // overwrites it
Point lights then add to it; transparent surfaces add their own emission in their forward pass.
```

- **Tests** (Metal-free where possible), `ToyFlightSimulatorTests/AssetPipeline/MaterialEmissionTests.swift`:
  - [x] `readsEmissionOnlyForUSD` — USDZ, USDC → true; OBJ, none → false.
  - [x] `objKaIsNotEmission` — an OBJ + MTL written by the test with `Ka 1 1 1`: Model I/O's
    `.emission` is the float3 (1, 1, 1), and the `Material` keeps emission 0 and no map.
  - [x] `usdEmissiveColorIsRead` — a USDA written by the test with `emissiveColor` (0.8, 0.02, 0.01)
    → `properties.emissive` the same within 1e-4; `usdWithoutEmissiveColorKeepsZero` — none authored → 0.
  - [x] App-hosted: `cockpitDisplaysHaveEmissionMaps` — the six displays, the ICP and `HUD_Combiner`
    have an emission map.
  - [x] App-hosted: `cockpitLensesHaveEmissionColors` — `Lens_Red` (0.8, 0.02, 0.01), `Lens_Amber`
    (0.9, 0.35, 0.02), `Lens_Green` (0.05, 0.6, 0.1); `cockpitStructureGivesOffNoLight` — every other
    cockpit material 0 and no map.
  - [x] App-hosted: `f16ObjReadsNoEmission` — the F-16's source materials carry (1, 1, 1) under
    `.emission` (its `Ka`), and its `Material`s all keep 0.
- **Observable completion criteria:** with the jet in shadow or at night, the six displays, the HUD
  symbology, the ICP text and the red/amber/green lenses stay bright; the rest of the cockpit is dark.
  The same in every renderer (the deferred ones through the lighting target).
- **Edge cases and expected results:**
  - The F-16/F-18 OBJs look unchanged (their `Ka` is ignored; the F-16 authors `Ka 1 1 1`).
  - The Sketchfab F-22's `f22a_landingLights` author `emissiveColor` (1, 1, 1), so they now glow
    white. The other USD aircraft author 0 (the unregistered CGTrader F-35 has real emission maps).
  - A `setColor` object gives off no light, even on a model with emissive materials.
  - Forward path with two directional lights: emission is still added once (e, not 2e); each
    light's ambient is added, as in the OpenGL equation. An unlit material or a sunless scene shows
    the base color without emission.
  - Every G-buffer fragment must write the lighting target (0 when it does not glow); a fragment that
    left it alone would pass the clear color to the sun pass as emission. The unused
    `SinglePassDeferredGBufferBase` pipeline blends that target additively, so it would.

### Milestone 6 — Replaceable HUD / display textures (hook for live symbology)

- **Learning objective:** render to a texture and bind it to a material, and use a calibration
  (boresight uv, px/deg) to place a world direction on the combiner.
- **Prerequisites:** Milestones 2 and 5.
- **Engine integration points:** the cockpit's materials `HUD_Combiner`, `Display_PMFD`,
  `Display_SMFD_Left/Right/Lower`, `Display_UFD_Left/Right`, `Display_ICP` (each screen is its own
  mesh with UVs 0..1); `Material.baseColorTexture`; `TextureLoader` / `LazyLibrary.setResolved` for
  runtime textures.
- **Algorithm:**

```pseudocode
// Calibration from Textures/hud_geometry.json (1024 x 939 px texture over the 0.180 x 0.165 m combiner's bounding box)
constant boresightUV = (0.500, 0.7956) ; pxPerDeg_h = 51.01 ; pxPerDeg_v = 51.41 ; textureSize_px = (1024, 939)

// Where a direction, given as angles from the aircraft's nose, lands on the HUD texture.
// azimuth_deg: + right ; elevation_deg: + up (body frame). Valid within +/-10 deg across, +3.7 .. -14.5 deg vertically.
function hudPixelFor(azimuth_deg, elevation_deg) -> pixel
    u = boresightUV.u + azimuth_deg * pxPerDeg_h / textureSize_px.width
    v = boresightUV.v + elevation_deg * pxPerDeg_v / textureSize_px.height
    return (u * textureSize_px.width, (1 - v) * textureSize_px.height)    // origin top-left

// Once per frame (or 30 Hz), on the render thread, before the lighting pass:
draw symbology into hudTarget (RGBA, alpha = coverage) using hudPixelFor
    horizon line at hudPixelFor(0, -pitch_deg) rotated by -roll about the boresight
    flight path marker at hudPixelFor(beta_deg, pitch_deg - alpha_deg) ...   // from AircraftTelemetry
cockpit HUD_Combiner material: baseColorTexture = hudTarget ; emissionTexture = hudTarget
```

- **Tests** (Metal-free where possible):
  - [ ] `HudCalibrationTests.boresightMaps` — (0°, 0°) → pixel (512.0, 191.9).
  - [ ] `HudCalibrationTests.tenDegreesDown` — (0°, −10°) → pixel (512.0, 706.0).
- **Observable completion criteria:** the swapped texture shows a test pattern (a cross at the
  boresight) that sits on the horizon ahead when flying level at zero pitch.
- **Edge cases and expected results:** painted symbology is exact only from the DEP; head look
  (Milestone 2) shifts it against the world, which a real collimated HUD would not do. A true
  collimated HUD draws symbols in view space instead, clipped to the combiner outline.

## Simple version, then optimized version

- **Simple version:** Milestones 1–4 with one static model, rigid skins and baked textures. It stays
  as the reference.
- **Optimized version:** none needed for frame time: the cockpit is 42,560 triangles in 30 meshes
  (77 submeshes, one draw call each). If the Metal HUD shows the cockpit costing more than
  ~0.3 ms, merge the static meshes per material in Blender (`build_cockpit.py` builds them
  separately for clarity) — same pixels, fewer draw calls.
- **Runtime switch:** a `Preferences` flag to leave the cockpit out of the chase view (hide the
  node with `SceneManager.SetRenderableHidden` while the chase camera is current).
- **Comparison:** same scene, camera 1 vs camera 2, stats overlay FPS and the Metal HUD's GPU time.
- **Fidelity note:** merging meshes changes nothing visible; hiding in chase view removes the
  interior seen through the canopy.

## Pitfalls and how to detect them

| Symptom | Likely cause | How to check |
|---|---|---|
| Cockpit view is a flat light brown above the glareshield | `Canopy_Glass` exported with opacity 1 (Blender drops a scalar Alpha) | `verify_cockpit_usdz.swift` flags it; re-export with `export_usdz.py` (its hook writes the 0.07) |
| Cockpit invisible or only its back faces show | basis without the reflection, or winding not reversed | log the basis determinant (must be −1); `Mesh.reverseTriangleWinding` must run |
| Throttle on the right, stick on the left | a det +1 basis mirrored the cockpit | use `transformXZYToXYZ`, not the CGTrader basis |
| Cockpit 7 m ahead or below the jet | eye point in the wrong frame (import vs body) | the Sketchfab eye point is in the recentered body frame |
| A part rotates the wrong way | `inverted` derived with the right-hand rule; `float4x4(rotateAbout:byAngle:)` turns the other way (the basis reflection does not flip it: conjugation keeps the motion) | the direction tests in `CockpitAnimatorTests`; flip `inverted` for that joint config |
| No cockpit control moves | `cockpitAnimator` is none (the cockpit model is not a `UsdModel`), or `update` is not called | `[F22CockpitAnimator] Initialized with 5 channels` in the log; a `joint not found` warning means a suffix no longer matches |
| One control dead, the others move | its channel ID in the animator differs from the one the layer was built with | use the config's channel-ID constants on both sides; `CockpitAnimatorTests` |
| Gear handle never moves | Sketchfab F-22: no exterior animator, gear fixed down (expected) | try G in the CGTrader F-22 |
| Levers reach AB before or after the plumes light | the mapping and `F22.doUpdate` use different thresholds | `milDetentSitsAtTheAfterburnerThreshold`; both must read `F22.milPowerThrottleThreshold` |
| Stick parts explode or collapse to the origin | skeleton not found / palette not updated | `[UsdModel loadSkins] ... Created skin with skeleton` for all six meshes |
| Gray shapes flicker through the consoles | Sketchfab `f22a_cockpit` still drawn | Milestone 3 filter |
| Displays and lenses dark in every renderer | `Material` got no file format (`sourceFileFormat` nil), so `readsEmission` is false | `MaterialEmissionTests` cockpit cases |
| Displays glow in the OIT renderer but not in a deferred one | the G-buffer stage does not write the lighting target, or the sun pass does not add it back | `GBufferOut.lighting` / `GBufferData.lighting`; the sun pass's `emission + ShadeDirectionalBlinnPhong(...)` |
| The F-16 turns white | an OBJ's `Ka` read as emission | `objKaIsNotEmission`, `f16ObjReadsNoEmission` |
| HUD symbology off the horizon | camera not at the DEP (offset, zoom) or head look | camera local position must be (0,0,0); recentre with middle click |
| tvOS bundle grows 3 MB | new file joins every target | add the usdz to the tvOS membership exceptions like `F-22_Raptor.usdz` |

## References

1. **Origin:**
   - GlobalSecurity, "F-22 Raptor Cockpit" (https://www.globalsecurity.org/military/systems/aircraft/f-22-cockpit.htm) —
     the most detailed public text: display sizes, ICP, HUD FOV (30° x 25°), side-stick, canopy,
     15° over-the-nose. Read it for every layout number used in the asset.
   - Pixar, OpenUSD "UsdSkel" schema (https://openusd.org/release/api/usd_skel_page_front.html) —
     skeleton, joint paths, rest/bind transforms, skinning primvars; read "UsdSkel Introduction" and
     "Schemas In-Depth".
   - J. T. Kajiya, "The Rendering Equation", SIGGRAPH 1986 (Computer Graphics 20(4), 143–150) — the
     outgoing light is the surface's own emitted light plus the reflected incoming light, and the
     emitted term appears once. The physical reason Milestone 5 adds emission outside the sum over lights.
2. **Detailed explanation:**
   - M. Segal and K. Akeley, *The OpenGL Graphics System: A Specification*, version 2.1 (2006),
     section 2.14.1 "Lighting", equation on p. 62 (https://registry.khronos.org/OpenGL/specs/gl/glspec21.pdf).
     The fixed-function lighting equation, `c_pri = e_cm + a_cm·a_cs + Σ_i att_i·spot_i·[a_cm·a_cli
     + diffuse_i + specular_i]`: the material emission `e_cm` and the scene ambient sit outside the
     sum over lights, each light's own ambient inside it. Table 2.10 lists the terms. Checked by
     extracting the PDF text. The engine's forward loop has the same shape.
   - Kodeco, *Metal by Tutorials* v5, character animation chapters
     (https://www.kodeco.com/books/metal-by-tutorials/v5.0) — the engine's `Skeleton` is based on it;
     read the skinning and joint-palette sections.
   - Apple, `MDLSkeleton` and `MDLAnimationBindComponent` documentation
     (https://developer.apple.com/documentation/modelio/mdlskeleton) — what Model I/O exposes.
   - Blender Manual, USD export (https://docs.blender.org/manual/en/latest/files/import_export/usd.html) —
     the export options used by `Tools/export_usdz.py` (no axis conversion, triangulate, armatures).
3. **Reference implementation:**
   - This repo: `F22AnimationConfig.createAileronLayer` and `F22_CGTrader.doUpdate` — the procedural
     channel pattern Milestone 4 copies; `AircraftAnimator.rollAilerons` for a setter that loops over
     a layer's channels; `ColliderDebugOverlay` for `SetRenderableHidden` use.
   - `F22CockpitAnimationConfig.findJointPaths` — its doc comment explains Swift parameter packs and
     cites SE-0393 and WWDC23 session 10168.
   - The asset build: `F22_Cockpit/Tools/bc_controls.py` (rig and pivots), `bc_displays.py`
     (HUD calibration), `verify_cockpit_usdz.swift` (import check).

Adaptations made for this engine: joints are single-axis to fit `ProceduralJointConfig`; the stick
travel is a visual convention (the real stick barely moves); display and HUD content is
representative, not the real (unpublished) formats; the canopy was fitted to the Sketchfab model,
not to real drawings.

## Pseudocode style

- Structure with `function name(inputs) -> output`, `for each`, `while`, `if / else`, and
  `return`. No language-specific syntax and no real API calls. An engine touchpoint is written
  as `engine: SceneManager.RemoveObject(object)`.
- Names are descriptive. A quantity name carries its unit as a suffix: `_m`, `_s`, `_mps`, `_N`,
  `_rad`. Frames are named where they matter: `worldVelocity_mps`, `bodyLocalAttachPoint_m`.
- One idea per line. A comment says what a step does, not what the syntax is.
- When the math uses symbols, define each symbol once, above the block, and map it to the
  name used in the pseudocode.
