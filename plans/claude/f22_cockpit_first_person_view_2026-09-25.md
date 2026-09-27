# F-22 cockpit and first-person view — Implementation Plan

**Started:** 2026-09-25 · **Agent:** claude
**Design source:** the codebase (files cited below) and the cockpit asset's own build notes,
`~/Desktop/BlenderProjects/ToyFlightSimulator/F22_Cockpit/README.md` (sources for the cockpit
layout, the frame conventions, the rig, and how to rebuild or re-export the asset). No research
document: this is asset integration through existing engine paths, small enough to plan from the code.
**Status:** in progress (Milestones 1–3 landed in 25f61c9)
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
| Joint rotation | θ | `angle_rad` | rad | joint-local = native axes | right-hand rule in the native Z-up frame |
| Stick roll | θ_r | `stickRoll_rad` | rad | about native +Y | + = stick right; ±12° |
| Stick pitch | θ_p | `stickPitch_rad` | rad | about native +X | + = stick aft (pull); ±12° |
| Throttle lever | θ_t | `throttleLever_rad` | rad | about native +X | − = forward; IDLE +5.74°, MIL −5.74°, AB −17.46° |
| Gear handle | θ_g | `gearHandle_rad` | rad | about native +X | 0 = DOWN (rest), −33.40° = UP |
| Rudder pedal | θ_y | `pedal_rad` | rad | about native +X | + = pedal pushed forward; ±10° |
| Throttle input | — | `ControlInput.throttle` / `.MoveFwd` | 0…1 | — | as read in `Aircraft.getControlInput()` |

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
  cockpit node is created with the aircraft.
- `GameObjects/F22.swift`, `GameObjects/F22_CGTrader.swift` — override the eye point.
- New `GameObjects/Cameras/CockpitCamera.swift` — a look-only camera at the DEP.
- `Managers/InputManager.swift` — two `DiscreteCommand` cases mapped to `Keycodes.one` / `.two`.
- `Scenes/GameScene.swift` / `Scenes/FlightboxWithPhysics.swift` — register the cockpit camera,
  handle the keys, re-attach on aircraft swaps (`applyAircraftSwap`).
- `Animation/Animators/AircraftAnimator.swift` — new `AnimationLayerID` cases; a new
  `CockpitAnimator` next to `F22Animator`; a new `Animation/Configs/CockpitAnimationConfig.swift`.
- `AssetPipeline/Material.swift` and the lighting shaders — emission (Milestone 5).
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
  to light the afterburners, so the lever crosses the MIL gate when the plumes appear.
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

### Milestone 4 — Animate stick, throttles, pedals and gear handle

- **Learning objective:** turn an input value into a joint rotation with a procedural channel, and
  map a nonlinear lever travel (detents) with a pure, testable function.
- **Prerequisites:** Milestone 1; `procedural-animation-plan.md`; the joint table above.
- **Engine integration points:** `AnimationLayerID` (new cases `cockpitStick`, `cockpitThrottle`,
  `cockpitPedals`, `cockpitGearHandle`), new `CockpitAnimator` (subclass of `AircraftAnimator`),
  new `CockpitAnimationConfig`, new pure `CockpitControlMapping`, the cockpit node's owner
  (`Aircraft.doUpdate` reads input as `F22_CGTrader.doUpdate` does).
- **Algorithm:**

Symbols: θ = joint angle (rad), v = channel value, θ_max = `maxDeflection`; the channel computes
θ = v · θ_max (sign flipped when `inverted`), applied as `restTransform * rotation(axis, θ)`.

```pseudocode
constant stickMax_rad = 12°        // visual only: the real F-22 stick is force-sensing, ~1/4 in throw
constant throttleMax_rad = 17.46°  // AB detent = asin(0.06 m / 0.20 m)
constant idle_rad = +5.74° ; mil_rad = -5.74° ; ab_rad = -17.46°   // forward is negative
constant gearUp_rad = 33.40°       // 2 * atan(0.030 m / 0.10 m)
constant pedalMax_rad = 10°

// CockpitAnimationConfig.createLayers(model)
function findJoint(model, name) -> path            // suffix match, as createAileronLayer does
layer cockpitStick:
    channel "stickRoll":  range (-1, 1), speed 8/s, joint StickRoll,  axis (0, 1, 0), max stickMax_rad
    channel "stickPitch": range (-1, 1), speed 8/s, joint StickPitch, axis (1, 0, 0), max stickMax_rad
layer cockpitThrottle:
    channel "throttle": range (-1, 1), speed 3/s, joints ThrottleLeft and ThrottleRight,
                        axis (1, 0, 0), max throttleMax_rad, inverted false
layer cockpitPedals:
    channel "pedals": range (-1, 1), speed 4/s, axis (1, 0, 0), max pedalMax_rad,
                      joints PedalLeft (inverted false) and PedalRight (inverted true)
layer cockpitGearHandle:
    channel "gearHandle": range (0, 1), speed 3/s, joint GearHandle, axis (1, 0, 0),
                          max gearUp_rad, inverted true            // v = 1 -> -33.40 deg = UP

// CockpitControlMapping (pure, Metal-free)
function throttleLeverAngle(throttle01) -> angle_rad
    t = clamp(throttle01, 0, 1)
    if t <= 0.8
        return idle_rad + (mil_rad - idle_rad) * (t / 0.8)            // IDLE .. MIL
    return mil_rad + (ab_rad - mil_rad) * ((t - 0.8) / 0.2)           // MIL .. AB (afterburner)
function throttleChannelValue(throttle01) -> value
    return throttleLeverAngle(throttle01) / throttleMax_rad           // channel multiplies back

// Every UpdateThread tick, in the aircraft's doUpdate, only with player focus:
function updateCockpitControls(cockpitAnimator, input, gearCommandedDown, deltaTime_s)
    cockpitAnimator.channel("stickRoll").setValue(input.roll)          // + = right
    cockpitAnimator.channel("stickPitch").setValue(input.pitch)        // + = aft; verify sign in-app
    cockpitAnimator.channel("throttle").setValue(throttleChannelValue(input.throttle))
    cockpitAnimator.channel("pedals").setValue(input.yaw)
    cockpitAnimator.channel("gearHandle").setValue(gearCommandedDown ? 0 : 1)
    cockpitAnimator.update(deltaTime_s)                                // writes the skin palettes

// gearCommandedDown: the F-22 animator's gearState is .down or .extending
```

- **Tests** (Metal-free where possible):
  - [ ] `CockpitControlMappingTests.throttleWorkedExample` — throttle 0.0, 0.4, 0.8, 0.9, 1.0 →
    +5.74°, 0.00°, −5.74°, −11.60°, −17.46° (±0.01°); values +0.329, 0.000, −0.329, −0.664, −1.000.
  - [ ] `CockpitControlMappingTests.throttleClamps` — −0.5 → IDLE, 1.7 → AB.
  - [ ] App-hosted: `CockpitAnimatorTests.registersSevenJointConfigs` — the four layers resolve all
    seven joint paths (none reported missing).
- **Observable completion criteria:** in the cockpit view, the right arrow tilts the stick right,
  the down arrow pulls it aft, W moves both throttle grips forward past the MIL gate as the
  afterburner plumes light, Q/E push the pedals, G swings the gear handle UP/DN.
- **Edge cases and expected results:**
  - A part moves the wrong way → flip that joint's `inverted` (the reflection in the basis makes
    signs easy to get wrong; see Pitfalls).
  - The model is shared by every F-22 instance (one `Model` per `ModelType`), so the pose is shared;
    only the player jet should drive it.
  - Keyboard throttle: `.MoveFwd` is −1 with S; the mapping clamps it to IDLE.

### Milestone 5 — Emission term for displays, HUD and indicator lenses

- **Learning objective:** why emissive surfaces bypass lighting, and why only the USD dialect may
  read `.emission` (Model I/O stores an OBJ's `Ka` there).
- **Prerequisites:** `research/claude/modelio_material_semantics_blinn_phong_2026-09-21.md` §1.2; the
  TODO in `Material.setProperties`.
- **Engine integration points:** `Material` (`populateTexture` `.emission` case, a new
  `emissionTexture` and `emissionColor`), `MaterialProperties` in `TFSCommon.h`, and the lighting
  function every renderer shares (`Lighting::ShadeDirectionalBlinnPhong`), plus the G-buffer paths.
- **Algorithm:**

```pseudocode
// Import: USD models only (UsdModel), never ObjModel.
if model is USD and material has .emission
    if texture: material.emissionTexture = load(texture, srgb: true)
    else:       material.emissionColor = float3 value
// Shading, after lighting:
finalColor = emission + ambient + litFraction * (diffuse + specular)
emission   = emissionTexture sample (or emissionColor) * emissionStrength   // 1.0 from the file
```

- **Tests** (Metal-free where possible):
  - [ ] `MaterialEmissionTests.objKaIsNotEmission` — an OBJ material with `Ka 1 1 1` keeps emission 0.
  - [ ] App-hosted: the cockpit's `Display_PMFD` material has an emission texture after import.
- **Observable completion criteria:** with the jet in shadow or at night, the six displays, the HUD
  symbology, the ICP text and the red/amber/green lenses stay bright; the rest of the cockpit is dark.
- **Edge cases and expected results:** the F-16/F-18 OBJs look unchanged (their `Ka` is ignored).

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
| A part rotates the wrong way | sign convention across the reflection | flip `inverted` for that joint config |
| Stick parts explode or collapse to the origin | skeleton not found / palette not updated | `[UsdModel loadSkins] ... Created skin with skeleton` for all six meshes |
| Gray shapes flicker through the consoles | Sketchfab `f22a_cockpit` still drawn | Milestone 3 filter |
| Displays black in shadow | no emission term yet | Milestone 5 |
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
2. **Detailed explanation:**
   - Kodeco, *Metal by Tutorials* v5, character animation chapters
     (https://www.kodeco.com/books/metal-by-tutorials/v5.0) — the engine's `Skeleton` is based on it;
     read the skinning and joint-palette sections.
   - Apple, `MDLSkeleton` and `MDLAnimationBindComponent` documentation
     (https://developer.apple.com/documentation/modelio/mdlskeleton) — what Model I/O exposes.
   - Blender Manual, USD export (https://docs.blender.org/manual/en/latest/files/import_export/usd.html) —
     the export options used by `Tools/export_usdz.py` (no axis conversion, triangulate, armatures).
3. **Reference implementation:**
   - This repo: `F22AnimationConfig.createAileronLayer` and `F22_CGTrader.doUpdate` — the procedural
     channel pattern Milestone 4 copies; `ColliderDebugOverlay` for `SetRenderableHidden` use.
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
