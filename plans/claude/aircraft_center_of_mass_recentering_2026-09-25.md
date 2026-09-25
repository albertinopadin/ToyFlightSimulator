# Aircraft Center-of-Mass Recentering: Implementation Plan

**Started:** 2026-09-25 · **Agent:** claude
**Design source:** none. This is a small asset-pipeline change, planned from the codebase and from a
measurement of the five aircraft models with `scripts/measure_center_of_mass.swift`. The matrix math and
every derived number are checked by `scripts/verify_center_of_mass_math.swift`. The references at the
end cover the rigid-body and matrix-convention background.
**Status:** draft
**Related plans:** `plans/claude/meter_scale_implementation_plan_2026-07-23.md` (the meterization scale
this plan composes with), `plans/claude/reindex_on_import_winding_fix.md` (the basis bake and the winding
flip), `plans/claude/compound_rigid_bodies_implementation_plan_simplified.md` (the "body origin is the
center of mass" contract used by colliders and landing gear)

## How this document works

- The owner writes the code from the pseudocode. The agent implements a milestone only when asked.
- Milestones are edited in place to match the code. History goes in the Changelog, newest first,
  one line per entry.
- A milestone header gets `✅ (landed YYYY-MM-DD, <commit>)` when it lands. Checkboxes (`- [ ]`)
  track the items inside it.
- Review findings that change the plan are folded in; the changelog line names the review and
  says which numbers were re-checked with a scratch script.

## Changelog

- **2026-09-25**: Milestone 6 made required for the F-18 and the Sketchfab F-22 (owner request). The
  scratch probes became two commented scripts, `scripts/measure_center_of_mass.swift` and
  `scripts/verify_center_of_mass_math.swift` (all checks pass), and every number in the plan was
  re-checked with them. Changes that came out of the re-measurement:
  - Wheels are now detected per gear leg. That found the Sketchfab F-22's nose wheel (z = 7.849, 7 cm
    higher than its mains), so its station now comes from its own wheels by the F-18's 12 % rule:
    z = 2.512. The earlier 3.365 was borrowed from the CGTrader F-22's origin. Its current origin
    turned out to be 1.785 m behind its main wheels.
  - The F-18 nose-wheel reading moved from 3.580 to 3.585, so its final value is
    `c = (0, 1.928, −1.761)`.
  - The F-16's nozzle is now measured with a region box. Its line sits 0.14 m below the origin; the
    earlier rough slab said ≈ 0.0.
- **2026-09-25**: Plan created from the codebase. Every number in the findings table, the worked
  example, the tests and Milestone 6 was reproduced by scratch Swift scripts kept outside the repo:
  `measure_origin.swift` and `measure_contacts.swift` (ModelIO loads of the five aircraft files with
  the registered bases and meterization factors: vertex bounds, nose tip, named nozzle parts, wheel
  contact clusters), `verify_math.swift` and `order_check.swift` (the bake, composition order,
  conjugation error over 2,000 random joint deltas per basis, the determinant and the extent),
  `node_times.swift` (node transforms at the start and end of the animation), and `f35_example.swift`
  (the F-35 and Milestone 6 numbers).

## Findings (the short answer)

**Yes, the basis transform can move the roll axis to the center of mass.** It is the right place to
do it, with four conditions:

1. **The translation must be in row-vector form.** `Mesh.transformMeshBasis` bakes each vertex as a
   row vector, `p_body = p_native · B`. In that convention a translation lives in the **bottom row**
   of the matrix, which in simd's column storage is the `w` component of columns 0, 1 and 2.
   `Transform.translationMatrix` builds the column-vector form (translation in column 3). If you put
   that matrix inside the basis, the bake drops it without an error: the offset ends up in the
   output's `w`, which `.xyz` discards. `scripts/verify_center_of_mass_math.swift` confirms that both
   `T·B₀` and `B₀·T` leave every vertex where it was.
2. **The translation must be composed last**, after the meterization scale:
   `B = S · B₀ · T_row(−c)`. Then `c` is in engine meters and engine axes (+Y up, +Z nose). This is the
   frame every number you have authored so far is in. If the translation is composed first, `c` is
   read in native file units and native axes instead.
3. **Everything that reads the basis must get the whole matrix, including the translation.** In
   `Model.init` that happens by itself: the same `meterizedBasisTransform` feeds the vertex bake, the
   winding check, `Skeleton` and `TransformComponent`. The conjugation `Bᵀ·J·(Bᵀ)⁻¹` stays exact for
   an affine `B` (worst error over 2,000 random joint deltas per transform: 4×10⁻⁶ m). The F-18's
   control surfaces and stores are the exception. They come through `SingleSubmeshMeshLibrary`, which bypasses
   `Model.init`, so that library must be given the same matrix.
4. **Offsets you authored against the old origin must be re-expressed.** The rule is
   `new = old − c`. It applies to camera offsets, collider and gear specs, and child positions such
   as the Sketchfab F-22's afterburners.

**Two aircraft need the roll-axis fix, and two need their pitch and yaw pivot moved.** The F-18 and
F-35 need the fix (Milestones 4–5). The F-18 and the Sketchfab F-22 also get a new longitudinal
station, the pivot position along the fuselage (Milestone 6). Measured in the import frame (defined
under Terms) by `scripts/measure_center_of_mass.swift`, in meters:

| Aircraft (model file) | Origin above lowest vertex | Nose tip y | Nozzle center y | Nose→nozzle line at z = 0 | Verdict |
|---|---|---|---|---|---|
| F/A-18 (`FA-18F.obj`) | 0.011 (wheel bottoms) | 1.418 | 2.205 (`EngineNozzles_Paint`) | **1.845** | origin 1.85 m low: **fix** |
| F-35 (`F-35A_Lightning_II.usdz`) | 0.000 | 0.918 | 1.063 (`Object_3`) | **1.003** | origin 1.0 m low: **fix** |
| F-16 (`f16r.obj`) | 1.380 | −0.264 | −0.047 (region box) | −0.142 | origin 0.14 m high; a 90° roll swings the line 0.20 m: left as is |
| F-22 CGTrader (default) | 2.164 | −0.039 | 0.022 (region box) | −0.001 | already on the line |
| F-22 Sketchfab | 2.043 | −0.052 | 0.000 (region box, nozzle pair) | −0.010 | on the line vertically, but the origin is 1.785 m **behind** the main wheels: Milestone 6 |

The final values of `c`, the offset each model's vertices are shifted by:

| Aircraft | `c` (import frame, m) | Milestone |
|---|---|---|
| F-35 | (0, 1.003, 0) | 4 |
| F-18 | (0, 1.845, 0), then (0, 1.928, −1.761) | 5, then 6 |
| Sketchfab F-22 | (0, −0.018, 2.512) | 6 |
| F-16, CGTrader F-22 | none | none |

If you saw the problem on the default CGTrader F-22, check it with Milestone 1 before changing
anything. Its origin is already on the nose→nozzle line. On the runway, though, any roll looks like a
pivot about the wheels, because the gear struts push back on the lowered side. That is the ground's
reaction force and is correct, not a misplaced pivot. In the air it rolls about the fuselage line.

## Goal and what you will learn

When this is finished, the F-18 and the F-35 roll, pitch and yaw about a point on their fuselage
centerline, the nose→nozzle line the owner described, instead of a point at wheel level. The F-18 and
the Sketchfab F-22 also pitch and yaw about a physically plausible station, where the nose wheel
would carry 12 % of the weight. Today the F-18's nose wheel would carry 41 %, and the Sketchfab F-22
pivots about a point behind its main wheels. The X-key
collider overlay draws the body axes, so you can see the roll axis pass through the nose tip and out
through the nozzles. Nothing changes per frame: the correction is baked into the vertex data once, at
import.

Learning objectives:
- Why a node rotates about its local origin (`modelMatrix = T·R·S`), and why the physics body's
  origin must also be its center of mass.
- Affine transforms in homogeneous coordinates: where a translation lives in the row-vector and
  column-vector conventions, and why the wrong one is silently ignored.
- Change of frame by conjugation (`Bᵀ·J·(Bᵀ)⁻¹`): why skinning and node animation stay correct when
  the basis carries a translation, and what breaks when it does not.
- Working in named frames (native, import, body) and re-expressing authored offsets between them.
- Estimating a center of mass from rendered geometry: the height from the nose→nozzle line, and the
  station from the static balance of a tricycle landing gear.

Not in scope:
- A true mass-weighted center of mass. It needs component masses, which these assets do not carry.
- Center-of-mass shift as fuel burns or stores are released (F-18 weapons). That would be a change to
  the flight model.
- A separate center-of-mass offset field on `RigidBody` (the Unity and Jolt approach). It was rejected
  under Design decisions.
- The F-16 (0.14 m above its line) and the CGTrader F-22 (on its line). The CGTrader F-22 would also
  move 0.7 m aft by the 12 % rule, but its collider and gear specs, and the tests that pin them, are
  authored against its current origin. Recentering it is a follow-up; see the last design decision.
- The F-35's station. Its gear is skinned and measured in its bind pose, which is not a gear-down
  tricycle, so the 12 % rule cannot be applied without the animated pose.

## Terms

- **Node origin / pivot.** The point `(0, 0, 0)` of a node's local space. `Node` builds
  `modelMatrix = translationMatrix(position) · rotationMatrix · scaleMatrix(scale)`, so every rotation
  turns the geometry about this point.
- **Center of mass (CoM).** The mass-weighted average position of a body. A free body rotates about
  it, and forces through it produce no torque. `RigidBody` documents the contract that "the body
  origin is the center of mass": every lever arm (gear struts, tires, contacts) is measured from the
  node origin.
- **Roll axis.** The line through the pivot along body +Z (forward). Only the x and y of the pivot
  move this line. Moving the pivot along z slides the pivot along the same line.
- **Nose→nozzle line.** The straight line from the nose tip (the most forward vertex) to the center of
  the engine nozzle. It is the owner's proxy for the fuselage centerline, used here to choose the CoM
  height.
- **Station.** A position along the fuselage, given as a body z coordinate in meters.
- **Homogeneous coordinates.** Writing a point as `(x, y, z, 1)` and a direction as `(x, y, z, 0)`, so
  one 4×4 matrix can rotate, scale and translate. The `w = 0` of a direction makes it ignore
  translation, which is why normals and extents are unaffected by what this plan adds.
- **Row-vector / column-vector convention.** With column vectors the product is `p' = M · p` and the
  translation sits in the last column. With row vectors it is `p' = p · M` and the translation sits in
  the last row. The two matrices are transposes of each other. ModelIO, the shaders and `Node` use
  column vectors. Only the import bake (`Mesh.transformMeshBasis`,
  `SingleMeshVertexMetadata.transformingCentroid`) uses row vectors.
- **Basis transform `B₀`.** The axis permutation each aircraft registers in `ModelLibrary`, for
  example `Transform.transformXMinusZYToXYZ`. It maps a file's axes onto the engine's (+X right,
  +Y up, +Z forward).
- **Meterization scale `s`.** The uniform scale `Model.init` folds in so that 1 unit = 1 m
  (`realWorldLength / GetLengthAxisExtent(...)`).
- **Native frame.** Vertex coordinates as authored in the file.
- **Import frame.** The native frame after `S·B₀`: engine axes and meters, origin wherever the artist
  put it. It is the frame the engine uses today, and every authored number (collider specs, gear
  struts, camera offsets, afterburner positions) is in it.
- **Body frame.** The import frame shifted so that its origin is the CoM: `p_body = p_import − c`.
  After this plan, the node's local space is the body frame.
- **Import transform `B`.** The one matrix the bake uses: `B = S · B₀ · T_row(−c)`. `Model` stores it
  as `basisTransform`.
- **Conjugation.** Re-expressing a transform in another frame. A joint delta `J` that moves native
  vertices becomes `Bᵀ·J·(Bᵀ)⁻¹` in the body frame (`Transform.basisConjugationMatrices`).

## The idea in plain words

**The problem.** The engine rotates every aircraft about its node origin, both on the kinematic path
(`Node.rotateX/Y/Z`) and on the physics path (`AngularIntegration` rotates the node, and torques are
taken about the origin). The origin is wherever the 3D artist placed it. For the F-18 and the F-35 the
artist placed it on the ground between the wheels, the usual choice for a model meant to sit on a
floor. So the roll axis runs along the runway surface under the jet, and a roll swings the whole
fuselage around it like a door on a hinge.

**The idea.** Keep the engine's contract ("the body origin is the center of mass") and move the
geometry instead: subtract the CoM position `c` from every vertex once, at import. After that the CoM
is at the local origin, so every existing rotation already turns about it. The bake already multiplies
each vertex by a 4×4 matrix, and a 4×4 matrix can translate as well as rotate and scale, so the shift
is one more factor in that matrix. Bullet uses the same approach: a rigid body's frame is always its
center of mass, and a model whose origin is elsewhere gets its shape shifted to match (see
References).

**The steps.**
1. Draw the body axes in the X overlay, so you can see where the pivot is before and after.
2. Add a translation helper in the bake's row-vector form, and a pure function that composes
   `S·B₀·T_row(−c)`.
3. Give `Model.init` an optional `c` and let it compose the full import transform. The existing code
   passes that one matrix on to the bake, the skeleton and the node-animation conjugation.
4. Measure `c` for each aircraft (the nose→nozzle line at the current station) and register it on the
   F-35.
5. Register the F-18's `c` through both of its import paths.
6. Move the F-18's and the Sketchfab F-22's station, the pitch and yaw pivot, to where the nose wheel
   would carry 12 % of the weight, and take the line height at that station.

## Worked example

The F-18 at its current station, which is Milestone 5. Milestone 6 then moves the station and repeats
Step 1 there (its own worked numbers are in that milestone). The F-18 is not meterized (`s = 1`), and
its basis is `rotate180AroundY`, which maps native `(x, y, z)` to import `(−x, y, −z)`.

Inputs (import frame, meters, from `scripts/measure_center_of_mass.swift`):
- Nose tip `N = (0, 1.418, 9.085)`, the vertex with the largest z.
- Nozzle center `Z = (0, 2.205, −7.648)`, the bounding-box center of submesh `EngineNozzles_Paint`.
- Station where the CoM stays: z = 0, the current origin station.

Step 1. Height of the nose→nozzle line at z = 0, by linear interpolation along z:
`fraction = (9.085 − 0) / (9.085 − (−7.648)) = 9.085 / 16.733 = 0.54294`, and
`y = 1.418 + 0.54294 · (2.205 − 1.418) = 1.418 + 0.42729 = 1.845`.
So `c = (0, 1.845, 0)`. The line tilts 2.69° nose-down relative to body +Z. That is fine: the roll
axis stays body +Z and passes 0.43 m above the nose tip and 0.36 m below the nozzle center.

Step 2. Import transform `B = rotate180AroundY · T_row(−c)`. In simd's column storage:
`column0 = (−1, 0, 0, 0)`, `column1 = (0, 1, 0, −1.845)`, `column2 = (0, 0, −1, 0)`,
`column3 = (0, 0, 0, 1)`. The −1.845 sits in `column1.w`, not in `column3.y`.

Step 3. Bake some native points with `p · B`:

| Point | Native | Import (today) | Body (after) |
|---|---|---|---|
| Nose tip | (0, 1.418, −9.085) | (0, 1.418, 9.085) | (0, −0.427, 9.085) |
| Nozzle center | (0, 2.205, 7.648) | (0, 2.205, −7.648) | (0, 0.360, −7.648) |
| Lowest vertex (wheel bottom), y only | y = −0.011 | y = −0.011 | y = −1.856 |
| Left main wheel contact | (1.517, 0.018, 2.490) | (−1.517, 0.018, −2.490) | (−1.517, −1.827, −2.490) |

Step 4. What a 90° roll does. A point at distance `r` from the roll axis moves along a chord of
length `2r·sin(45°) = r·√2`.
- The fuselage centerline at z = 0: before, `r = 1.845`, so it moves **2.609 m**. After, `r = 0`, so it
  does not move.
- The nozzle center: before it moves 3.118 m; after, 0.509 m.

Step 5. Re-expressed offsets (`new = old − c`):
- `F18.cameraOffset`: `[0, 9, −20]` → `[0, 7.155, −20]`. The chase-camera framing stays identical.
- The legacy 2 m `SphereRigidBody` holds the origin about 2 m above the runway. Before, the wheels
  rest 1.989 m in the air. After, they rest 0.144 m in the air.

## Data, units, and conventions

| Quantity | Symbol | Name in pseudocode and code | Unit | Frame | Sign or convention |
|---|---|---|---|---|---|
| Native vertex position | `p_native` | `vertexPositionNative` | file units | native | row vector `(x, y, z, 1)` in the bake |
| Axis permutation | `B₀` | `basisTransform` | none | native → import axes | row-vector: `p · B₀` |
| Meterization scale | `s`, `S = diag(s, s, s, 1)` | `meterizationScale` | m per file unit | none | uniform, applied first |
| Center of mass | `c` | `centerOfMassInImportFrame` | m | import | +X right, +Y up, +Z nose; x = 0 for symmetric jets |
| Row-vector translation | `T_row(t)` | `rowVectorTranslationMatrix(t)` | m | none | `t` in the `w` of columns 0–2; equals `transpose(translationMatrix(t))` |
| Import transform | `B = S·B₀·T_row(−c)` | `importTransform` (stored as `Model.basisTransform`) | none | native → body | row-vector |
| Body-frame vertex | `p_body` | none | m | body | `p_body = s·(p_native·B₀) − c` |
| Joint or node delta | `J` | clip or node matrices | none | native | column-vector `J · p` |
| Conjugated delta | `J_body` | `Skeleton.currentPose`, `TransformComponent.keyTransforms` | none | body | `Bᵀ · J · (Bᵀ)⁻¹` |
| Authored offsets | none | `cameraOffset`, `LocalCollider.localPosition`, `SuspensionStrut.attachLocal`, child `setPosition` | m | import today, body after | `new = old − c` |

Update order: all of this happens once per process, when the lazy `ModelLibrary` factory first builds
the model. That happens under the library lock, on whichever thread first asks for the model, which
is scene construction. The bake runs before the `Model` is shared, so there is no threading concern.
The F-18 submesh extraction is also lazy and runs once per cached submesh. Nothing changes per frame.

Engine conventions that apply: left-handed, +Y up, +Z forward, meters, the row-vector bake against
column-vector everything else, and the "body origin is the center of mass" contract in `RigidBody`.

## Engine integration points

- `ToyFlightSimulator Shared/Math/Transform.swift`: new `rowVectorTranslationMatrix(_:)` next to
  `translationMatrix`, with a comment naming the convention.
- `ToyFlightSimulator Shared/AssetPipeline/Model.swift`: new pure static `ComposeImportTransform(...)`,
  in the style of `GetLengthAxisExtent`, and a new optional `centerOfMassInImportFrame` parameter on
  `init(_:fileExtension:basisTransform:realWorldLength:)`. Compose before `GetMeshes` and before
  `self.basisTransform` is assigned. Update the `basisTransform` doc comment: it now holds the full
  import transform.
- `ToyFlightSimulator Shared/AssetPipeline/ObjModel.swift`, `UsdModel.swift`: forward the new
  parameter.
- `ToyFlightSimulator Shared/AssetPipeline/Mesh.swift`, `Animation/Skeleton.swift`,
  `Animation/TransformComponent.swift`, `SingleSubmeshMesh.swift`: **no change**. They already
  consume whatever matrix they are given, and the translation is exact through all of them
  (Milestone 2's tests pin that).
- `ToyFlightSimulator Shared/AssetPipeline/Libraries/Models/ModelLibrary.swift`: the `.Sketchfab_F35`,
  `.F18` and `.Sketchfab_F22` registrations pass their `c`.
- `ToyFlightSimulator Shared/AssetPipeline/Libraries/SingleSubmeshMeshLibrary.swift`: the F-18
  factory passes the composed F-18 import transform instead of the bare `rotate180AroundY`.
- One shared home for the F-18 constant, because two libraries need it (a small enum next to
  `ModelLibrary`, or a static on it; the owner decides).
- `ToyFlightSimulator Shared/GameObjects/F18.swift`, `F35.swift`, `F22.swift`: `cameraOffset`
  re-expressed, and in `F22.init` the two afterburner `setPosition` calls. `F18.setupControlSurfaces`
  needs **no** change (Milestone 5 explains why). The Sketchfab F-22 is also used by
  `FlightboxScene`, `FlightboxWithTerrain` and `FreeCamFlightboxScene`. They place the node at fixed
  positions, so after Milestone 6 the airframe draws 2.5 m further aft of those positions, which is
  harmless. `FreeCamFlightboxScene`'s 2.5 m sphere is then centered on the CoM.
- `scripts/measure_center_of_mass.swift` and `scripts/verify_center_of_mass_math.swift`: the
  measurement and the math checks behind every number here. Keep their mirrored tables (bases, scales,
  offsets, planned `c`) in step with the registrations as you land each milestone.
- `ToyFlightSimulator Shared/Physics/Debug/ColliderDebugOverlay.swift`: the body-axis lines
  (Milestone 1).
- Unaffected, and checked: `AircraftColliderSpec` and `AircraftLandingGearSpec` (both empty for the
  F-18, F-35 and Sketchfab F-22), `Model.GetLengthAxisExtent` (it uses `w = 0`), the winding determinant (3×3 block
  only), the thumbnails (SceneKit loads the file itself and recenters on its bounding sphere in
  `AircraftThumbnailGenerator`), and `FlightboxWithPhysics.applyAircraftSwap` (spawn position is
  unchanged).
- Telemetry: `AircraftTelemetry` reads the node's world position, so after the fix "altitude" is the
  CoM's height. That is already true for both F-22s.
- Thread: import happens inside the lazy library factory. The overlay lines are built on the
  UpdateThread in `ColliderDebugOverlay.apply`, like the strut lines.

## Design decisions and where they came from

- [codebase] **Keep "body origin = center of mass" and move the geometry.** `RigidBody` states the
  contract. `addForce(_:atWorldPoint:)`, `velocity(atWorldPoint:)`, the suspension, the tire model
  and `HeckerCollisionResponse` all measure lever arms from the origin, so moving the origin fixes
  physics and rendering with no physics code change.
- [source: Bullet manual; Baraff 1997] **Rejected: a separate CoM offset stored on the body** (Unity's
  `Rigidbody.centerOfMass`, Jolt's `GetCenterOfMassPosition` against `GetPosition`). Every lever-arm
  site listed above would need the offset. Bullet's own convention, "the rigid body's world transform
  is its center of mass; shift the shape to match", is the one this engine already follows.
- [source: btDefaultMotionState] **Rejected: a per-draw render offset** (`graphics = com · offset`).
  The offset is constant, so a bake costs nothing per frame. It also keeps a single local frame for the
  aircraft's children: the camera, the afterburners and the overlay.
- [source: Giesen 2012] **Row-vector translation, composed last:** `B = S·B₀·T_row(−c)`. Row-vector
  translations live in the bottom row and compose left to right, so the rightmost factor applies last,
  in engine meters and engine axes.
- [codebase] **`c` is authored in the import frame**, the frame of every existing authored number.
  Re-expressing offsets is then a single rule, `new = old − c`.
- [design] **`c` is a measured constant per model, not computed at load.** This follows the
  `realWorldLength` pattern. A loader cannot find "the nozzle" generically (OBJ group names against
  USD `Object_N`), and a mass-weighted CoM needs data the assets do not have.
- [design] **Height first, station second.** The roll axis is a line parallel to +Z, so `c.z` cannot
  change it. Milestones 4–5 therefore fix the height alone (`c = (0, y, 0)`), which can be checked on
  its own. Milestone 6 then moves the station, which changes only pitch and yaw.
- [source: Raymer; design] **The station comes from the nose-wheel share, at 12 %.** Raymer gives
  8–15 % of the weight on the nose wheel; 12 % is the middle of that range and is this plan's own
  choice. The same rule on both F-22 models agrees within 0.15 m (10.976 m and 10.831 m behind the
  nose tip). That was the reason to use it for the Sketchfab F-22 instead of copying the CGTrader
  F-22's authored origin (10.124 m behind the nose). The F-35 keeps its station, because its gear
  geometry is only available in the bind pose.
- [design] **At the new station the height is re-evaluated** on the nose→nozzle line. For the F-18
  that is 1.928 instead of 1.845, because the line tilts 2.69°.
- [design] **Re-express offsets by hand** (`new = old − c`) rather than store `c` on `Model` and
  subtract it where each offset is used. Only two camera offsets change today. If the CGTrader F-22
  ever gets a non-zero `c`, switch to subtract-where-used, so that its collider and gear specs (and
  the tests that pin them) keep their current values.
- [design] **Leave the F-16 and the CGTrader F-22 as they are.** The CGTrader F-22 is on its line.
  The F-16 is 0.14 m above its line: a 90° roll swings its centerline 0.20 m, which is barely visible.
  It is a one-line change later if wanted (`scripts/measure_center_of_mass.swift` already prints its
  estimate and its re-expressed camera offset). The Sketchfab F-22's vertical offset (−0.018) is
  included only because its `c` changes anyway in Milestone 6.

## Verification commands

```bash
# Build the app and the test bundle (the scheme's Build action builds the app only)
xcodebuild build-for-testing -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run the suites this plan touches, serial per project rule
xcodebuild test-without-building -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  -only-testing:"ToyFlightSimulatorTests/CenterOfMassImportTests" \
  -only-testing:"ToyFlightSimulatorTests/BasisConjugationTests" \
  -only-testing:"ToyFlightSimulatorTests/SingleMeshVertexMetadataTests" \
  -only-testing:"ToyFlightSimulatorTests/ModelMeterizationTests" \
  -only-testing:"ToyFlightSimulatorTests/ColliderOverlayMappingTests" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Full suite before calling a milestone done (same flags, no -only-testing)

# Re-measure the models and re-check every number in this plan (no Xcode needed)
swift scripts/measure_center_of_mass.swift                 # add --model f18, --parts, --aft-profile, --slices as needed
swift scripts/verify_center_of_mass_math.swift             # exits 1 if any check fails

# iOS build: the shared files compile into every target
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" \
  -sdk iphonesimulator -configuration Debug
```

## Milestones

### Milestone 1: Make the pivot visible

- **Learning objective:** see that the node origin is the rotation pivot, and where it sits in each
  model, before changing anything.
- **Prerequisites:** none.
- **Engine integration points:** `ColliderOverlayMapping` (new pure `bodyAxisLineEndpoints()`, next
  to `strutLineEndpoints(for:)`); `ColliderDebugOverlay.buildVolumes(on:spec:gearSpec:)` attaches
  three `Line`s with the same `attach(_:to:)` path the strut lines use; colors from `Colors.swift`
  (`RED_COLOR`, `GREEN_COLOR`, `BLUE_COLOR`).
- **Algorithm:**

```pseudocode
// Body axes for the X overlay, in the aircraft's local space (meters). The lines are children of
// the aircraft, so they rotate with it, and their crossing point IS the rotation pivot.
constant rollAxisHalfLength_m = 15      // longer than every nose (max 13.49 m on the Sketchfab F-22), so both ends stick out
constant crossAxisHalfLength_m = 3      // short arms, so the pitch and yaw axes do not hide the wings

function bodyAxisLineEndpoints() -> list of (start_m, end_m, color)
    rollAxis  = ((0, 0, -rollAxisHalfLength_m), (0, 0, +rollAxisHalfLength_m), blue)   // body +Z
    pitchAxis = ((-crossAxisHalfLength_m, 0, 0), (+crossAxisHalfLength_m, 0, 0), red)  // body +X
    yawAxis   = ((0, -crossAxisHalfLength_m, 0), (0, +crossAxisHalfLength_m, 0), green) // body +Y
    return [rollAxis, pitchAxis, yawAxis]

// in buildVolumes, after the strut lines:
for each (start_m, end_m, color) in bodyAxisLineEndpoints()
    engine: attach(Line(startPoint: start_m, endPoint: end_m, color: color), to: target)
```

- **Tests** (Metal-free):
  - [ ] `ColliderOverlayMappingTests.bodyAxisLinesCrossAtTheOrigin`: every line's midpoint is
    `(0, 0, 0)`; the roll line runs from `(0, 0, −15)` to `(0, 0, 15)`, pitch ±3 on x, yaw ±3 on y.
- **Observable completion criteria:** press X with each aircraft.
  - F-18: the blue roll line runs along the runway under the jet, level with the wheel bottoms, about
    1.85 m below the fuselage centerline.
  - F-35: the same, about 1.0 m below.
  - CGTrader F-22: the line enters at the nose tip and leaves through the nozzles.
  - With the free camera ('C'), roll the F-18: the fuselage swings around the blue line.
- **Edge cases and expected results:**
  - Aircraft swap while the overlay is on → `hostWasReplaced` rebuilds the lines on the new aircraft.
  - Overlay off → the lines are removed with the volumes (`removeFromScene`), with no frozen ghosts.

### Milestone 2: Row-vector translation and the composed import transform (pure math)

- **Learning objective:** homogeneous coordinates, the row-vector against the column-vector
  convention, composition order, and why conjugation survives a translation.
- **Prerequisites:** the Terms above.
- **Engine integration points:** `Transform.swift` (new helper); `Model.swift` (new static function);
  a new Swift Testing suite, `CenterOfMassImportTests` (tag `.assetPipeline`); additions to
  `BasisConjugationTests` and `SingleMeshVertexMetadataTests`.
- **Algorithm:**

Why the existing `translationMatrix` does nothing in the bake. The row-vector product computes output
component `j` as `dot(p, column j)`. For the column-form matrix, columns 0–2 are the unit axes with
`w = 0`, so `x' = x`, `y' = y` and `z' = z`. The translation sits in column 3 and lands in `w' = t·p + 1`,
which `.xyz` throws away. To add `t` to `x`, the `t.x` must sit where `p.w = 1` multiplies it into
column 0, which is `column0.w`.

```pseudocode
// Translation in the bake's row-vector form (p_row · M). Equals transpose(Transform.translationMatrix(offset_m)).
function rowVectorTranslationMatrix(offset_m) -> matrix4x4
    matrix = identity
    matrix.column0.w = offset_m.x      // x' = x·1 + w·offset.x, and w = 1 for points
    matrix.column1.w = offset_m.y
    matrix.column2.w = offset_m.z
    return matrix                       // directions (w = 0) pass through unchanged

// The single matrix the importer bakes. Row-vector: the LEFTMOST factor applies first.
//   1. meterization scale   (native units → meters, native axes)
//   2. basis permutation    (native axes → engine axes)   : result is the import frame
//   3. recentering          (subtract c, engine meters)   : result is the body frame
function composeImportTransform(basisTransform or none, meterizationScale or none,
                                centerOfMassInImportFrame_m or none) -> importTransform or none
    if basisTransform, meterizationScale and centerOfMassInImportFrame_m are all none
        return none                     // Mesh.init then skips the per-vertex pass, as today
    importTransform = basisTransform or identity
    if meterizationScale is present
        importTransform = uniformScaleMatrix(meterizationScale) * importTransform   // same as Model.init today
    if centerOfMassInImportFrame_m is present
        importTransform = importTransform * rowVectorTranslationMatrix(-centerOfMassInImportFrame_m)
    return importTransform
```

Why conjugation stays exact. With row-vector baking, `p_body = p_native · B`. Written as column
vectors that is `p_body = Bᵀ · p_native`. A joint moves native vertices: `p_native' = J · p_native`.
The same motion in the body frame is
`p_body' = Bᵀ · J · p_native = (Bᵀ · J · (Bᵀ)⁻¹) · p_body`. Nothing in this derivation assumes `B` has
no translation, so `Transform.basisConjugationMatrices` is already correct for the full import
transform. It is correct **only if** it is given the full matrix. If it is given `S·B₀` while the
vertices were shifted by `c`, the skinned vertex comes out off by `(I − R)·c`, where `R` is the
joint's rotation.

- **Tests** (Metal-free; expected values from `scripts/verify_center_of_mass_math.swift`, sections A–H):
  - [ ] `CenterOfMassImportTests.rowVectorTranslationMovesPoints`: the point `(1, 2, 3)` through
    `rowVectorTranslationMatrix((0, −1.845, 0))` → `(1, 0.155, 3)`.
  - [ ] `…rowVectorTranslationLeavesDirections`: the direction `(0, 1, 0)` with `w = 0` →
    `(0, 1, 0)`.
  - [ ] `…columnTranslationIsDroppedByTheBake` (documents the trap): the point `(1, 2, 3)` through
    `rotate180AroundY · Transform.translationMatrix((0, −1.845, 0))` → `(−1, 2, −3)`, the same as
    without the translation.
  - [ ] `…composeOrderPutsCenterOfMassInEngineMeters`: `s = 2.1961696`,
    `B₀ = transformXMinusZYToXYZ`, `c = (0, 1, 0)`, point `(1, 2, 3)`: composed →
    `(2.1961696, 5.5885086, −4.392339)`. The wrong order, `T_row(−c)·S·B₀`, gives
    `(2.1961696, 6.5885086, −2.1961696)`, because it subtracts native z.
  - [ ] `…f18WorkedExample`: `composeImportTransform(rotate180AroundY, none, (0, 1.845, 0))` maps the
    native nose tip `(0, 1.418, −9.085)` → `(0, −0.427, 9.085)` and the native nozzle center
    `(0, 2.205, 7.648)` → `(0, 0.360, −7.648)`.
  - [ ] `…allNoneReturnsNone`, and `…centerOfMassAloneStillBakes` (identity basis, no scale,
    `c = (0, 1, 0)` → a non-none matrix that moves points by −1 in y).
  - [ ] `…recenteringKeepsWindingSign`: the 3×3 determinant of `s·B₀·T_row(−c)` has the same sign
    as that of `B₀` (the verify script prints 10.59 = 2.196³ for the CGTrader basis). `det3x3` is
    `private` to `ModelMeterizationTests`, so either copy it or put these tests in that suite.
  - [ ] `…recenteringKeepsLengthExtent`: `Model.GetLengthAxisExtent` of `(13.654, 5.149, 18.267)`
    through the F-18 import transform = 18.267. (`ModelMeterizationTests.translationDoesNotOffsetExtent`
    already checks the same property with a hand-built matrix.)
  - [ ] `BasisConjugationTests.translationBearingBasisConjugatesExactly`: with `SplitMix64`
    (`TestSupport/SeededRandom.swift`), 200
    random joint deltas (rotation up to ±π about a random axis, translation up to ±3 m) and native
    points up to ±10 m, `bake(J · p, B)` and `conj(J) · bake(p, B)` agree within 1e-4 m, for the F-18,
    F-35 (`s = 0.5431731`, `c = (0, 1.003, 0)`) and CGTrader-like (`c = (0.1, −0.7, 0.4)`) transforms.
    The verify script's worst case over 2,000 samples per transform is 3.9e-6 m.
  - [ ] `BasisConjugationTests.basisWithoutTheTranslationMisplacesSkinnedVertices`: a 90° joint
    rotation about X, with `c = (0, 1.845, 0)` missing from the skeleton's basis → error
    `|(I − R)·c| = 2.609 m`.
  - [ ] `SingleMeshVertexMetadataTests.centroidCarriesRecentering`: the native centroid
    `(−5.462, 2.084, 3.773)` through the F-18 import transform → `(5.462, 0.239, −3.773)`. Without
    `c` it would be `(5.462, 2.084, −3.773)`.
- **Observable completion criteria:** the tests pass; the app is unchanged, because nothing calls
  the new code yet.
- **Edge cases and expected results:**
  - `c = (0, 0, 0)` → the same matrix as no `c`. Multiplying by identity is exact in floating point.
  - Negative `c.y` (origin above the line) → the model moves up. The math is symmetric.
  - `c.x ≠ 0` → an off-center roll axis. The airframes are symmetric, so the probe reports
    `x ≈ 0.000`; treat anything above a few centimeters as a measurement mistake.

### Milestone 3: Thread the center of mass through `Model.init`

- **Learning objective:** one matrix, four consumers. The vertex bake, the winding check, `Skeleton`
  and `TransformComponent` all read the same `basisTransform`, so composing it in one place keeps
  them consistent.
- **Prerequisites:** Milestone 2.
- **Engine integration points:** `Model.init` (new optional `centerOfMassInImportFrame`),
  `ObjModel.init`, `UsdModel.init` (forward it), the `basisTransform` doc comment, and a `DebugLog`
  line.
- **Algorithm:**

```pseudocode
// Model.init. The existing meterization block is unchanged, except that it computes the scale
// factor and does not build the final matrix itself.
function modelInit(modelName, fileExtension, basisTransform or none, realWorldLength_m or none,
                   centerOfMassInImportFrame_m or none)
    asset = loadAsset(modelName)
    meterizationScale = none
    if realWorldLength_m is present
        // measured with w = 0 through the UN-recentered basis; c cannot change a length
        nativeLength = getLengthAxisExtent(drawSpaceNativeExtent(asset), basisTransform)
        meterizationScale = realWorldLength_m / nativeLength
    importTransform = composeImportTransform(basisTransform, meterizationScale, centerOfMassInImportFrame_m)
    if centerOfMassInImportFrame_m is present
        engine: DebugLog("[Model init] <name> recentered: center of mass <c> m (import frame) is the new origin")
    meshes = getMeshes(asset, importTransform)     // bake + winding check + TransformComponent conjugation
    self.basisTransform = importTransform or identity   // UsdModel hands this to every Skeleton
```

- **Tests:** `Model.init` needs a Metal device, so the logic stays in the Milestone 2 helper and this
  milestone is checked by regression: the full suite passes unchanged.
- **Observable completion criteria:** the app looks and behaves exactly as before; no "recentered"
  log line appears, because no registration passes `c` yet.
- **Edge cases and expected results:**
  - The F-35: `basisTransform` is none, a scale is present, `c` is present → `S·T_row(−c)`. It must
    still be applied, and it is, because `composeImportTransform` returns none only when all three
    inputs are none.
  - The F-18: a basis, no scale, `c` → `B₀·T_row(−c)`.

### Milestone 4: Measure and recenter the F-35

- **Learning objective:** estimate a CoM from geometry, and watch the translation survive skinning and
  animated node transforms. The F-35 goes first because it has one import path, skinned gear, and
  animated node transforms (seven meshes, doors and gear parts, move between the animation start and
  end; the measuring script's "animation" line reports a largest matrix change of 171 native units),
  and it has no collider or gear specs to re-express.
- **Prerequisites:** Milestones 1–3.
- **Engine integration points:** `ModelLibrary` `.Sketchfab_F35` registration (add
  `centerOfMassInImportFrame: (0, 1.003, 0)`); `F35.cameraOffset`. The measurement below is
  `scripts/measure_center_of_mass.swift`. It is built on the draw-space ports in
  `scripts/measure_models.swift`, and `--parts` lists the part names that can serve as a nozzle.
- **Algorithm:**

```pseudocode
// Offline probe (scripts/), not engine code. Mirrors the importer: node transform (only when the
// renderer applies it) → basis → meterization, giving import-frame meters.
function measureCenterOfMassHeight(asset, basisTransform, meterizationScale, nozzleSource) -> centerOfMassInImportFrame_m
    importTransform = composeImportTransform(basisTransform, meterizationScale, none)
    importVertices = empty list
    for each mesh in asset
        nodeTransform = scaleStrippedTransform(globalTransform(mesh)) if node transforms apply at draw, else identity
        for each vertex position p in mesh
            append bake(nodeTransform · p, importTransform) to importVertices
    noseTip_m = the vertex in importVertices with the largest z                 // +Z is forward
    // nozzleSource is a part name (--parts), or a region box chosen with --aft-profile when no part is named for it
    nozzleCenter_m = bounding-box center of the named part's vertices, or of the vertices inside the region box
    stationZ_m = 0                                                               // keep today's station; Milestone 6 revisits it
    // the height of the straight nose→nozzle line at that station
    fractionFromNose = (noseTip_m.z - stationZ_m) / (noseTip_m.z - nozzleCenter_m.z)
    lineHeight_m = noseTip_m.y + fractionFromNose * (nozzleCenter_m.y - noseTip_m.y)
    return (0, lineHeight_m, stationZ_m)                                         // x = 0: symmetric airframe

// Re-express every offset that was authored against the old origin (import frame → body frame).
function reexpressInBodyFrame(offsetInImportFrame_m, centerOfMassInImportFrame_m) -> offsetInBodyFrame_m
    return offsetInImportFrame_m - centerOfMassInImportFrame_m
```

F-35 inputs: nose tip `(0, 0.918, 7.835)`; nozzle part `Object_3`, bounding-box center
`(−0.004, 1.063, −5.524)`, radius about 0.6 m, at the tail on the centerline. The fraction is 0.58650,
so the line height is **1.003**, giving `c = (0, 1.003, 0)`. `F35.cameraOffset`: `[0, 6, −18]` →
`[0, 4.997, −18]`.

- **Tests:**
  - [ ] `CenterOfMassImportTests.f35ImportTransform`: `composeImportTransform(none, 0.5431731,
    (0, 1.003, 0))` maps the native nose tip `(0, 1.690069, 14.4245)` → `(0, −0.085, 7.835)` and the
    native nozzle center `(−0.0073641, 1.9570189, −10.169871)` → `(−0.004, 0.060, −5.524)`, both
    within 1e-3.
- **Observable completion criteria:**
  - The console shows `[Model init] F-35A_Lightning_II recentered: …`.
  - X overlay: the blue roll line passes 0.085 m above the nose tip and 0.06 m below the nozzle
    center, so it runs through the fuselage.
  - Roll with the free camera ('C') behind the jet: the nozzle stays almost still while the wings
    sweep.
  - 'G' still raises and lowers the gear with the wheels attached to the fuselage. This checks the
    skeleton conjugation; a stale basis would detach them by up to `(I − R)·c`.
  - The chase-camera framing is unchanged.
  - Parked on the runway on the legacy 2 m sphere, the lowest bind-pose point now rests about 1.0 m
    up instead of 2.0 m.
- **Edge cases and expected results:**
  - Gear-down pose against bind pose: the gear hangs lower when animated, so the parked height above
    differs. The recentering does not depend on it, because the nose tip and the nozzle are not
    animated parts.
  - Aircraft swap to the F-35 and back: the model is cached, so the bake happens once, with no
    accumulation.

### Milestone 5: Recenter the F-18 (two import paths, one constant)

- **Learning objective:** keep two import paths congruent. The fuselage comes through `Model.init`,
  while its ailerons, elevons, flaps, rudders, missiles, bombs and tanks come through
  `SingleSubmeshMeshLibrary`.
- **Prerequisites:** Milestones 1–4.
- **Engine integration points:** the shared F-18 constant `c = (0, 1.845, 0)` (Milestone 6 changes
  it to `(0, 1.928, −1.761)`); the `ModelLibrary` `.F18` registration; the
  `SingleSubmeshMeshLibrary.makeLibrary` factory; `F18.cameraOffset`.
- **Algorithm:**

```pseudocode
// One constant, both paths. The F-18 is not meterized, so the scale is none on both.
constant f18CenterOfMassInImportFrame_m = (0, 1.845, 0)

// ModelLibrary:
register F18 → ObjModel("FA-18F", basisTransform: rotate180AroundY,
                        centerOfMassInImportFrame: f18CenterOfMassInImportFrame_m)

// SingleSubmeshMeshLibrary (bypasses Model.init, so it gets the pre-composed matrix):
f18SubmeshImportTransform = composeImportTransform(rotate180AroundY, none, f18CenterOfMassInImportFrame_m)
factory(submeshName) → createSingleSMMeshFromModel("FA-18F", submeshName, basisTransform: f18SubmeshImportTransform)

// F18.cameraOffset: [0, 9, -20] - (0, 1.845, 0) = [0, 7.155, -20]
```

Why `F18.setupControlSurfaces` needs no change. `SingleSubmeshMesh.init` bakes the submesh with the
import transform, maps its centroid with the same transform (`transformingCentroid(by:)`, `w = 1`),
and then subtracts that centroid from the submesh's vertices. The `−c` is in both, so it cancels, and
the extracted vertex data is identical to today. Only `initialPositionInParentMesh` moves, by `−c`. The
node position `centroid − hingeOffset` therefore moves by `−c`, exactly as the fuselage vertices do.
The hinge offsets (`newAileronOrigin` and the rest) are measured from each surface's own centroid, so
they do not change. Weapon release (`weaponReleaseSetup`) places the store at
`rotation · centroid + aircraftPosition` and follows the body-frame centroid the same way.

- **Tests:**
  - [ ] `SingleMeshVertexMetadataTests.centroidCarriesRecentering` (Milestone 2) covers the centroid
    path.
  - The two paths cannot be compared in a Metal-free test, because both construct meshes. They are
    kept congruent by construction: both read the one shared constant. Check it by eye in the app.
- **Observable completion criteria:**
  - X overlay: the roll line runs through the fuselage, 0.43 m above the nose tip and 0.36 m below
    the nozzle center.
  - The control surfaces sit in their cut-outs and deflect about their hinges.
  - Space (AIM-9) launches from the wingtip rails; J jettisons the tanks from their pylons.
  - The chase framing is unchanged.
  - Parked on the legacy sphere, the wheels float about 0.14 m instead of about 2.0 m.
- **Edge cases and expected results:**
  - Only the fuselage path gets `c` → every control surface and store floats **1.845 m above** its
    slot. That is the tell-tale sign of the forgotten second path.
  - Repeated swaps F-18 → F-22 → F-18 → the extracted meshes are library-cached and baked once, and
    `setSubmeshOrigin` stays idempotent, so nothing accumulates.

### Milestone 6: Move the F-18's and the Sketchfab F-22's station (the pitch and yaw pivot)

- **Learning objective:** the station does not change the roll axis, but it decides where the aircraft
  pitches and yaws. Static balance on a tricycle landing gear gives a physical way to choose it. The
  nose→nozzle line tilts, so the height has to be read again at the new station.
- **Prerequisites:** Milestones 1–5. The F-18 half edits the shared constant introduced in
  Milestone 5.
- **Engine integration points:** the shared F-18 constant, which both F-18 import paths already read;
  `F18.cameraOffset`; the `ModelLibrary` `.Sketchfab_F22` registration (it gains
  `centerOfMassInImportFrame`); the two afterburner `setPosition` calls in `F22.init`;
  `F22.cameraOffset`. The `plannedCenterOfMass` rows in `scripts/measure_center_of_mass.swift`
  already hold these values.
- **Algorithm:**

```pseudocode
// Offline, in scripts/measure_center_of_mass.swift. All positions are import-frame meters.

// The wheels are the lowest points of the geometry: one cluster per gear leg.
function findGearContacts(importVertices) -> (noseWheel_m, leftMain_m, rightMain_m) or unusable
    noseWheel_m = mean of the vertices within 6 cm of the lowest one, among vertices with |x| < 0.4
    leftMain_m  = the same, among vertices with x <= -0.4
    rightMain_m = the same, among vertices with x >= +0.4
    // only a gear-down tricycle works: nose ahead of the mains, mains mirrored, all near the ground
    if noseWheel_m.z <= mainGearZ + 1 or the mains are not mirrored or a wheel sits far above the lowest vertex
        return unusable                                  // the F-35's skinned gear, measured in its bind pose
    return (noseWheel_m, leftMain_m, rightMain_m)

// Level aircraft at rest. Take moments about the main-wheel contact line; the weight acts at the CoM:
//   noseLoad · wheelbase = weight · (stationZ − mainGearZ)
// so the nose wheel's share of the weight is (stationZ − mainGearZ) / wheelbase.
function centerOfMassStationForNoseShare(noseGearZ_m, mainGearZ_m, noseLoadShare) -> stationZ_m
    wheelbase_m = noseGearZ_m - mainGearZ_m
    return mainGearZ_m + noseLoadShare * wheelbase_m

function centerOfMassAtNoseShare(noseTip_m, nozzleCenter_m, gear, noseLoadShare) -> centerOfMassInImportFrame_m
    mainGearZ_m = (gear.leftMain_m.z + gear.rightMain_m.z) / 2
    stationZ_m = centerOfMassStationForNoseShare(gear.noseWheel_m.z, mainGearZ_m, noseLoadShare)
    // the line tilts, so take its height again at the new station (Milestone 4's formula)
    lineHeight_m = noseToNozzleLineHeight(noseTip_m, nozzleCenter_m, stationZ_m)
    return (0, lineHeight_m, stationZ_m)
```

Worked numbers, with `noseLoadShare = 0.12` (all reproduced by `scripts/verify_center_of_mass_math.swift`,
sections D3 and D4):

| Quantity | F-18 | Sketchfab F-22 |
|---|---|---|
| Main wheels (x, z) | (±1.517, −2.490) | (±1.580, 1.785) |
| Nose wheel z | 3.585 | 7.849 (its bottom is 7 cm higher than the mains') |
| Wheelbase | 6.075 | 6.064 (public F-22 data: about 6.0) |
| Nose-wheel share with the CoM at today's origin | **41.0 %** (too much weight on the nose) | **−29.4 %** (origin 1.785 m *behind* the mains: the jet would sit on its tail) |
| Station at 12 % | −2.490 + 0.12 · 6.075 = **−1.761** | 1.785 + 0.12 · 6.064 = **2.512** |
| Nose tip, nozzle center | (0, 1.418, 9.085), (0, 2.205, −7.648) | (0, −0.052, 13.489), (0, 0.000, −3.173) (nozzle-pair region box) |
| Line height at the station | 1.418 + (10.846 / 16.733) · 0.787 = **1.928** | −0.052 + (10.977 / 16.662) · 0.052 = **−0.018** |
| **Final `c`** | **(0, 1.928, −1.761)** | **(0, −0.018, 2.512)** |
| Body-frame nose tip, nozzle center | (0, −0.510, 10.846), (0, 0.277, −5.887) | (0, −0.034, 10.977), (0, 0.018, −5.685) |
| `cameraOffset` | `[0, 9, −20]` → `[0, 7.072, −18.239]` | `[0, 7, −20]` → `[0, 7.018, −22.512]` |
| Other offsets | none (control surfaces and stores follow the constant) | afterburners `(±0.600, 0.098, −4)` → `(±0.600, 0.116, −6.512)` |
| Lowest vertex on the legacy 2 m sphere | 0.061 m above the runway | −0.025 m (2.5 cm into the runway, as today's −0.043; pre-existing) |

Cross-check for the Sketchfab F-22: the same 12 % rule applied to the CGTrader F-22 mesh's own wheels
puts that model's CoM 10.831 m behind its nose tip. For the Sketchfab model it is 10.977 m, so the two
models of the same aircraft agree within 0.15 m. The CGTrader F-22's authored origin (10.124 m behind
the nose) is 0.7 m further forward. Its gear spec places the mains at z = −0.9, where its mesh has
them at −1.471. It stays as it is in this plan (see Not in scope).

`F22.doUpdate`'s ground clamp (`getPositionY() < 0` → 0) holds the node origin at ground level, as it
does today. After this milestone the origin is the CoM, 1.8 cm below the old one, so the clamp's
effect is unchanged.

- **Tests** (Metal-free):
  - [ ] `CenterOfMassImportTests.f18FinalImportTransform`: `composeImportTransform(rotate180AroundY,
    none, (0, 1.928, −1.761))` maps the native nose tip `(0, 1.418, −9.085)` → `(0, −0.510, 10.846)`
    and the native nozzle center `(0, 2.205, 7.648)` → `(0, 0.277, −5.887)`.
  - [ ] `CenterOfMassImportTests.sketchfabF22ImportTransform`:
    `composeImportTransform(transformYMinusZXToXYZ, 0.0996041, (0, −0.018, 2.512))` maps the native
    nose tip `(135.4261, 0, 0.5221)` → `(0, −0.034, 10.977)` and the native nozzle-pair center
    `(−31.8561, 0, 0)` → `(0, 0.018, −5.685)`, within 1e-3; the 3×3 determinant stays negative, so the
    winding flip still happens.
  - [ ] `SingleMeshVertexMetadataTests.centroidCarriesFinalF18Recentering`: the native centroid
    `(−5.462, 2.084, 3.773)` → `(5.462, 0.156, −2.012)`.
  - The station arithmetic itself is offline: `swift scripts/verify_center_of_mass_math.swift` must
    print "All checks passed."
- **Observable completion criteria:**
  - `swift scripts/measure_center_of_mass.swift --model f18` and `--model sketchfab` print a "plan
    value" within 0.003 m of the "CoM estimate".
  - X overlay: on both jets the axis lines now cross about 0.73 m ahead of the main wheels (body
    z = −0.729 for the F-18, −0.727 for the F-22) and about 5.3 m behind the nose wheel.
  - Pitch with the free camera watching from the side. The nose tip moves 1.46 times as far as the
    tail on the F-18 (10.846 m against 7.421 m from the pivot), and 1.38 times on the Sketchfab F-22
    (10.977 m against 7.943 m). Before, the Sketchfab F-22 pivoted 5.43 m from its tail, so the nose
    moved 2.48 times as far as the tail.
  - Sketchfab F-22 at full throttle (above 0.8): the afterburner plumes still come out of the
    nozzles.
  - F-18: the control surfaces and stores are still in place (they read the shared constant), and
    the chase framing is unchanged on both jets.
- **Edge cases and expected results:**
  - Afterburner positions not re-expressed → the plumes start 2.51 m ahead of the nozzles, inside the
    fuselage.
  - Station moved but height not re-read (F-18 with `c = (0, 1.845, −1.761)`) → the roll axis sits
    0.083 m below the line at the new station. That is invisible, but the measuring script reports the
    0.083 m difference between the plan value and the estimate.
  - The F-35: its gear is measured in the bind pose, and the script reports it as not usable (the
    "nose" cluster is behind the mains). Its station stays at 0.
  - Any aircraft with collider or gear specs (today only the CGTrader F-22) would need every
    `localPosition` and `attachLocal` shifted by `−c`. `reachBelowOrigin` and the pinned ride height
    then grow by `c.y`, and the static load split changes with `c.z`.

## Simple version, then optimized version

- **Simple version:** Milestones 1–6, an authored constant per model baked at import. It stays in the
  code as the reference.
- **Optimized version:** not applicable. The bake runs once per process and costs nothing per frame.
  The per-draw alternative (Bullet's `btDefaultMotionState` offset) would cost more, not less. A
  follow-up could compute `c` automatically instead of measuring it (for example, the area-weighted
  surface centroid that Blender's "Origin to Center of Mass (Surface)" uses). That would change the
  estimate, which is a fidelity choice, not a speed-up.
- **Runtime switch:** not practical. `ModelLibrary` caches each model for the process lifetime, so
  switching would mean rebuilding the model and re-expressing the offsets. For A/B, launch once
  without the registration argument and once with it, and compare the Milestone 1 overlay.
- **Comparison:** the same scene (FlightboxWithPhysics, the F-18 and the F-35 selected from the menu),
  the X overlay and the free camera. Measure the displacement of the fuselage centerline during a 90°
  roll. Expected: 2.609 m before and 0 after for the F-18 at Milestone 5 (2.727 m before with the
  Milestone 6 value), and 1.003·√2 = 1.418 m before and 0 after for the F-35. For Milestone 6, compare
  how far the nose and tail move in a pitch: nose-to-tail ratio 1.46 (F-18) and 1.38 (Sketchfab F-22,
  2.48 before).
- **Fidelity note:** this changes the simulated behavior on purpose. The rotation pivot moves to a
  physically plausible point.

## Pitfalls and how to detect them

| Symptom | Likely cause | How to check |
|---|---|---|
| Nothing moves after adding the translation | `Transform.translationMatrix` (column form) was used inside the basis; the bake puts it in `w` and drops it | `columnTranslationIsDroppedByTheBake`; print the composed matrix: the offset must be in `column0…2.w`, not `column3` |
| The model moves along the wrong axis or by the wrong amount (on the CGTrader basis, along z instead of y) | translation composed before the basis (`T_row(−c)·S·B₀`), so `c` is read in native units and axes | `composeOrderPutsCenterOfMassInEngineMeters` |
| Skinned gear, doors or animated parts drift from the fuselage while animating (2.6 m at 90° for the F-18's `c`) | recentering done as a separate vertex pass, so `Skeleton` and `TransformComponent` were given a basis without it; the error is `(I − R)·c` | `basisWithoutTheTranslationMisplacesSkinnedVertices`; toggle the gear ('G') on the F-35 |
| F-18 control surfaces and stores float 1.845 m above the wings | `SingleSubmeshMeshLibrary` still passes the bare `rotate180AroundY` | one shared constant read by both libraries; check in the app with the X overlay |
| Chase camera suddenly 1.85 m (F-18) or 1.0 m (F-35) higher relative to the jet, or 2.5 m closer (Sketchfab F-22) | `cameraOffset` not re-expressed | `new = old − c`; the measuring script prints every re-expressed offset |
| Sketchfab F-22 afterburner plumes start 2.5 m ahead of the nozzles | the `F22.init` afterburner positions were not re-expressed | `(±0.600, 0.098, −4)` → `(±0.600, 0.116, −6.512)` |
| Parked F-18 or F-35 sits much lower than before | expected: the legacy 2 m sphere is now centered on the CoM (wheels 0.144 m and about 1.0 m up) | X overlay, yellow sphere |
| The default CGTrader F-22 still seems to roll about its wheels | on the ground the struts push back, which is correct; its pivot is already on the centerline | Milestone 1 line; roll in the air |
| Animated USD meshes suddenly take DrawManager's animated-uniforms path | `Bᵀ·I·(Bᵀ)⁻¹` is not bit-exact in Float for some transforms (2.4e-7 for the Sketchfab F-22's final transform), so `localTransform != .identity` turns true | only the F-35 has animated node transforms among the recentered jets, and its transform is bit-exact (verify script, section F); the Sketchfab F-22's time range is empty, so its node transforms are identity regardless; if it appears elsewhere, compare with a tolerance instead of `!=` |
| Meterized length or winding changes | should not happen: the extent uses `w = 0`, and the determinant reads only the 3×3 block | `recenteringKeepsLengthExtent`, `recenteringKeepsWindingSign` |

## References

1. **Origin.**
   - David Baraff, *An Introduction to Physically Based Modeling: Rigid Body Simulation I:
     Unconstrained Rigid Body Dynamics*, SIGGRAPH course notes (Pixar / CMU, 1997; revised 2001). Read
     the body-space and center-of-mass sections: body space is defined with the center of mass at its
     origin, so the body's world position is the CoM and torques are taken about it. That is the
     invariant `RigidBody` documents. The mechanics itself is classical Newton–Euler; Baraff is the
     standard statement of it in the graphics literature.
   - Fabian Giesen, "Row major vs. column major, row vectors vs. column vectors" (2012),
     https://fgiesen.wordpress.com/2012/02/12/row-major-vs-column-major-row-vectors-vs-column-vectors/.
     It explains that a row-vector translation matrix is the identity with the last row replaced by
     `tx ty tz 1`, the transpose of the column-vector one, and that composition order reverses between
     the conventions. That is exactly the bake's trap.
2. **Detailed explanation.**
   - *Bullet 2.80 Physics SDK Manual* (Erwin Coumans), rigid-body section: "the world transform of a
     btRigidBody is its center of mass". To put the center of mass elsewhere, you wrap the shape in a
     `btCompoundShape` with a child offset. That is the collision-shape version of this plan's vertex
     shift.
   - Jolt Physics documentation, class `Body` (https://jrouwe.github.io/JoltPhysics/class_body.html):
     `GetPosition()` against `GetCenterOfMassPosition()`, and `OffsetCenterOfMassShape`. This is the
     stored-offset alternative the plan rejected.
   - Unity Scripting API, `Rigidbody.centerOfMass`
     (https://docs.unity3d.com/ScriptReference/Rigidbody-centerOfMass.html): "the center of mass
     relative to the transform's origin". This is the offset-field alternative.
   - Daniel Raymer, *Aircraft Design: A Conceptual Approach*, landing-gear chapter: the nose wheel
     should carry about 8–15 % of the weight (Milestone 6). Attribution note: I verified the 8–15 %
     figure through the METU AE 451 lecture notes "Landing Gear Sizing and Placement"
     (http://www.ae.metu.edu.tr/~ae451/landing_gear.pdf), which follow Raymer, not against the book's
     page.
3. **Reference implementation.**
   - bullet3, `src/LinearMath/btDefaultMotionState.h`: `getWorldTransform` computes
     `centerOfMassWorldTrans = m_graphicsWorldTrans * m_centerOfMassOffset.inverse()`, and
     `setWorldTransform` computes `m_graphicsWorldTrans = centerOfMassWorldTrans * m_centerOfMassOffset`.
     It is the per-draw offset approach in about 20 lines; read it to see what the bake replaces.
   - JoltPhysics, `Jolt/Physics/Body/Body.h`: `GetPosition()` returns
     `mPosition - mRotation * mShape->GetCenterOfMass()`, and `GetCenterOfMassPosition()` returns
     `mPosition`. Jolt stores the CoM and derives the artist's origin, the mirror image of this plan.
   - Blender manual, Object ▸ Set Origin (Origin to Geometry, Origin to Center of Mass (Surface or
     Volume)): the asset-side alternative, re-exporting the model with its origin moved. Those options
     compute geometric centroids (vertex mean, or a uniform shell or volume), not a mass-weighted CoM.
   - In this repo: `scripts/measure_center_of_mass.swift` (the measurement: bounds, nose tip, nozzle,
     wheels, the `c` estimate and the re-expressed offsets), `scripts/verify_center_of_mass_math.swift`
     (self-checking math and every derived number), `scripts/measure_models.swift` (the draw-space
     measurement both build on),
     `Transform.basisConjugationMatrices`, and
     `ModelMeterizationTests.translationDoesNotOffsetExtent`, which already builds a
     translation-bearing basis in row-vector form.

Adaptations made for this engine:
- Bullet shifts collision shapes. This engine shifts the render vertices and the whole import frame at
  once, because its colliders and struts are authored as offsets from the node origin.
- The CoM height comes from the nose→nozzle line, a geometric proxy (the owner's heuristic), not a
  mass computation. The station comes from gear static balance for the F-18 and the Sketchfab F-22,
  and stays at the current origin for the F-35.
- `c` is authored in the import frame so that one subtraction re-expresses every existing offset.
