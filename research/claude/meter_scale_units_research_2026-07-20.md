# A True Meter Scale for ToyFlightSimulator

**Date:** 2026-07-20
**Question:** How do we make 1 scene unit = 1 meter, so an aircraft at `setScale(1)` is its real-world size — instead of hand-tuning per-model scales until things "look somewhat right"?
**Related docs:** `research/claude/compound_rigid_bodies_research_combined.md` (§4.1 units contract), `plans/claude/compound_rigid_bodies_implementation_plan.md` (step 0.5).

---

## Executive Summary

1. **The engine is already meters-native everywhere except the assets.** Gravity is `[0, -9.81, 0]` m/s² (PhysicsWorld.swift:21), mass is 30,000 kg, the flight model's thrust constant is a real F-22 number (with a known kgf-vs-newton bug its own doc comment admits), and the Phase B suspension math in the compound-bodies research already assumed meters. Nothing in the physics or rendering core needs a unit change — only the imported models and a handful of scene scalars are unitless.

2. **Industry practice is unanimous on the shape of the fix:** pick a canonical engine unit (Unity, Godot, glTF, X-Plane, USD-default-workflows: 1 unit = 1 m; Unreal: 1 unit = 1 cm), then convert every asset **once at import time** with a per-asset scale factor — never per-frame, never via node scale. Node/actor scale is reserved for gameplay effects; using it for unit repair is the known anti-pattern this project currently lives in.

3. **File metadata cannot be trusted to deliver real-world size.** I measured every model in the repo (ModelIO bounding boxes) and read their USD `metersPerUnit`: the Sketchfab F-22 declares centimeters but is only 58% of real size even after honoring that; the CGTrader F-22 declares meters and is 46% of real size; the F-18 OBJ (a format with *no* unit metadata) turns out to be the only asset authored in true meters. USD's own spec says values are copied literally with no auto-conversion, and DCC tools are inconsistent about writing/honoring MPU. Conclusion: **calibrate against published real aircraft dimensions, use metadata only as a sanity cross-check.**

4. **Recommended implementation:** extend the exact mechanism the engine already has — the import-time `basisTransform` — by folding a per-model *meterization scale* into that matrix. A small calibration table (real length ÷ measured native length, mirroring the `AircraftThumbnailSpec` per-aircraft-table pattern) drives it. Scenes then drop their magic scales (`12.0`, `1.4`, `3.0`, `0.25`, `0.8` → all `1.0`). This is a contained diff: `ModelLibrary` registrations, `Mesh`'s basis path (already transforms positions *and* normals; shaders renormalize, so a uniform scale is lighting-safe and cannot flip winding), plus a short migration checklist (camera offsets, far plane, flight-model thrust fix).

5. **Sequencing:** land this **before** the collider-overlay tuning step of compound-bodies Phase 0 (exit criterion "spec numbers eyeballed"), so `AircraftColliderSpec` gets authored **once, in meters**, and the Phase 0 units contract collapses from "world m = model units × scale" to the trivial "model units *are* meters, scale ≈ 1."

---

## Part 1 — How engines and formats standardize units

### 1.1 Engine conventions

- **Unity: 1 unit = 1 m.** Unity's asset-preparation guidance treats one world unit as one meter and provides a per-model import **Scale Factor** to convert assets authored in other units (e.g. 0.01 for cm-authored content). Its recommended verification ritual — export a 1×1×1 m cube from the DCC and compare against a native engine cube — is worth stealing. ([Unity Manual: Preparing Assets](https://docs.unity3d.com/2020.1/Documentation/Manual/BestPracticeMakingBelievableVisuals1.html), [techarthub: Untangling Unit Scale in Unity](https://techarthub.com/untangling-unit-scale-in-unity/))
- **Unreal: 1 uu = 1 cm.** Epic standardized on centimeters (default character = 180 uu = 180 cm); VR even exposes a `WorldToMeters` conversion (default 100). Different constant, same discipline: one global unit, per-asset import conversion. ([techarthub: Scale and Measurement Inside Unreal](https://techarthub.com/scale-and-measurement-inside-unreal-engine/), [worldofleveldesign UE5 scale guide](https://www.worldofleveldesign.com/categories/ue5/guide-to-scale-dimensions-proportions.php), [Epic: Set World to Meters Scale](https://dev.epicgames.com/documentation/en-us/unreal-engine/BlueprintAPI/Input/HeadMountedDisplay/SetWorldtoMetersScale))
- The common pattern in both: **the world unit is a project-wide constant; per-asset scale factors are applied at import; runtime node scale is for gameplay, not unit conversion.**

### 1.2 Format conventions

- **glTF 2.0 mandates meters** for all linear distances (and radians for angles) — no per-file unit metadata exists, which is exactly why glTF assets interchange predictably. ([Khronos glTF 2.0 spec](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html), [spec source on GitHub](https://github.com/KhronosGroup/glTF/blob/main/specification/2.0/Specification.adoc), [units discussion, glTF issue #1725](https://github.com/KhronosGroup/glTF/issues/1725))
- **USD parameterizes units via stage metadata `metersPerUnit`** (MPU). Fallback when unauthored is `UsdGeomLinearUnits::centimeters = 0.01`. Crucially, the USD runtime **never converts**: "geometric values are copied literally without unit conversion" — a meters-authored prim referenced into a cm stage comes in 100× too small unless the assembler applies corrective scaling. That responsibility lands on *us*, the importer. ([OpenUSD: Encoding Stage Linear Units](https://openusd.org/dev/api/group___usd_geom_linear_units__group.html), [NVIDIA: Units in OpenUSD](https://docs.nvidia.com/learn-openusd/latest/beyond-basics/units.html), [Omniverse: Set the Stage Linear Units](https://docs.omniverse.nvidia.com/dev-guide/latest/programmer_ref/usd/stage/set-stage-linear-units.html))
- **Tooling is inconsistent about MPU in practice** — e.g. Blender for years neither honored it on import nor scaled on export ([Blender issue #100448](https://projects.blender.org/blender/blender/issues/100448)), and Apple's ModelIO ignores it entirely (measured below). USDZ is *supposed* to be real-world scale for AR Quick Look, but that only holds when authors cooperate. ([Tsutsumi: How to use USDZ files with ARKit / SceneKit](https://medium.com/@shu223/how-to-use-usdz-files-with-arkit-scenekit-d2615bbb9963), [RapidPipeline: optimizing models for ARKit](https://rapidpipeline.com/en/a/optimize-3d-models-for-arkit/))

### 1.3 Flight-sim precedent

- **X-Plane's OBJ8 model format is specified in meters** (Y up, origin at the ground placement point) — aircraft and scenery alike. A meters world is the genre norm; it's what makes published performance numbers (thrust, wing area, gear travel) directly usable. ([X-Plane Developer: OBJ8 File Format Specification](https://developer.x-plane.com/article/obj8-file-format-specification/), [xp-obj OBJ8 reference](https://xp-obj.readthedocs.io/en/latest/obj8/reference.html))

### 1.4 The takeaway pattern

Every surveyed system converges on the same three rules, which are the design for Part 3:

1. **One canonical world unit** (meters, for a flight sim — it makes gravity, thrust, IAS, and gear-spring constants physical).
2. **Convert at import, per asset, once** — a scale factor baked into the vertex data (or the importer's root transform), driven by asset metadata *when trustworthy* and by explicit per-asset calibration when not.
3. **Verify with a reference object** (Unity's 1 m cube ritual; ours will be "log the loaded aircraft's bounding length and compare to the fact sheet").

---

## Part 2 — Where ToyFlightSimulator is today (measured)

### 2.1 The engine half is already SI

| Constant | Value | Location |
|---|---|---|
| Gravity | `[0, -9.81, 0]` | PhysicsWorld.swift:21 |
| F-22 mass | `30_000` kg | F22SimpleFlightModel.swift:9 |
| F-22 max thrust | `31_751` **kgf** (≈311 kN) | F22SimpleFlightModel.swift:10 |
| Camera near/far | 0.1 / 1000 | Camera.swift:71–72 |
| Sky dome | mesh radius 150 × `setScale(1000)` | BasicMeshes.swift:173, SkyBox/SkySphere.swift |
| Ground quad | `setScale(1_000_000)` | FlightboxWithPhysics.swift:29,104 |

The thrust constant is used **as if it were newtons** (`worldForward * engineMaxThrust * throttle`), understating real thrust by g ≈ 9.81× — `FlightModel.swift:25`'s doc comment already flags the mixed units. This is exactly the class of bug a meters contract makes visible: in a meters/kg/s world, thrust in N with mass in kg gives a full-afterburner acceleration of ~10.4 m/s² (T/W > 1, correct for an F-22) instead of the current ~1.06 m/s².

### 2.2 Measured model dimensions (ModelIO `MDLAsset.boundingBox`, native units, pre-basis-transform)

Script: `measure_models.swift` (scratchpad; trivially re-runnable). Declared units read with macOS's `/usr/bin/usdcat`.

| Model file | Native extent (X, Y, Z) | Declared units | Length axis → engine Z | Scene scale | In-world length today | Real length | Today vs real |
|---|---|---|---|---|---|---|---|
| `f16r.obj` | 1.47 × 0.69 × 2.25 | none (OBJ) | 2.253 | ×12.0 | 27.0 u | 15.06 m | **1.79×** |
| `FA-18F.obj` | 13.65 × 5.15 × 18.27 | none (OBJ) | 18.267 | ×1.4 | 25.6 u | 18.31 m | **1.40×** |
| `cgtrader_F22.usdz` | 6.22 × 8.62 × 2.46 | **MPU = 1 (meters)**, Z-up, Blender 4.5 | 8.615 (native Y) | ×3.0 | 25.8 u | 18.92 m | **1.37×** |
| `F-22_Raptor.usdz` (Sketchfab) | 1098.2 × 300.0 × 784.0 | **MPU = 0.01 (cm)**, Y-up | 1098.2 (native X) | ×0.25 | 274.6 u | 18.92 m | **14.5×** |
| `F-35A_Lightning_II.usdz` (Sketchfab) | 302.5 × 111.9 × 433.6 | **MPU = 0.01 (cm)**, Y-up | 433.6 | ×0.8 | 346.9 u | 15.67 m | **22×** |
| `sphere.obj` | 2 × 2 × 2 | — | — | — | — | — | radius exactly **1.0** ✓ |
| `quad.obj` | 2 × 2 × 0 | — | — | — | — | — | |
| `Temple.obj` | 1024 × 722 × 1024 | — | — | — | — | — | scenery, own problem |

("Length axis → engine Z" applies each model's registered `basisTransform` permutation: `rotate180AroundY` for the OBJs, `transformXMinusZYToXYZ` for the CGTrader F-22, `transformYMinusZXToXYZ` for the Sketchfab F-22. `sphere.obj` at radius exactly 1.0 confirms `ColliderOverlayMapping.sphereMeshRadius = 1.0` from compound-bodies plan step 0.4 by measurement.)

Real-dimension sources: F-22A 18.92 m length / 13.56 m span ([USAF fact sheet](https://www.af.mil/About-Us/Fact-Sheets/Display/Article/104506/f-22-raptor/), [Wikipedia](https://en.wikipedia.org/wiki/Lockheed_Martin_F-22_Raptor)); F/A-18F 18.31 m / 13.62 m ([NAVAIR](https://www.navair.navy.mil/product/FA-18EF-Super-Hornet), [RAAF](https://www.airforce.gov.au/aircraft/18f-super-hornet)); F-16C 15.06 m / 9.96 m with tip missiles ([Wikipedia](https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon), [AeroCorner comparison](https://aerocorner.com/comparison/f-35-vs-f-16/)); F-35A 15.67 m / 10.7 m ([USAF fact sheet](https://www.af.mil/About-Us/Fact-Sheets/Display/Article/478441/f-35a-lightning-ii/)).

### 2.3 What the measurements prove

1. **Proportions are fine; absolute scale is arbitrary.** CGTrader F-22 span/length = 6.220/8.615 = 0.722 vs real 13.56/18.92 = 0.717; Sketchfab F-22 = 784/1098 = 0.714. Every model is internally correct — only the meter mapping is missing, so a single uniform factor per model fixes everything.
2. **Metadata would have failed us in both directions.** Honoring the Sketchfab F-22's declared centimeters yields a 10.98 m jet (58% of real). The CGTrader F-22's declared *meters* yields 8.6 m (46%). The unlabeled F-18 OBJ is the only true-meters asset (18.267 ≈ 18.31 m, off by 0.2%). **Real-dimension calibration is mandatory; MPU is at best a cross-check.**
3. **ModelIO ignores MPU entirely** — measured bounds come back in raw file units (1098, not 10.98). Consistent with USD's "values are copied literally" contract: unit handling is the importer's job, and our importer currently doesn't do it.
4. **The hand-tuned scales already encode an implicit calibration.** The three jets flown most (F-16, F-18, CGTrader F-22) all converge to ~26 world units long — an accidentally consistent world that is ~1.4–1.8× real size if we call a unit a meter. Physics (9.81 gravity) has been acting on oversized bodies, which is why falls/arcs read slightly "floaty" relative to visual size. The Sketchfab pair (275 u, 347 u) never got folded into that consistency.

---

## Part 3 — Design: 1 scene unit = 1 meter

### 3.1 The contract

- **1 engine/scene unit = 1 meter, in every scene.** Physics constants stay exactly as they are (they were already SI).
- **Models are meterized at import**, inside the asset pipeline. After import, a model's vertex data *is* in meters.
- **Node scale returns to being a gameplay knob** with an expected value of 1.0 for aircraft. `Node.uniformScale` (already implemented, step 0.3 of the compound plan) remains the debug-assert guard; the compound-collider units contract simplifies to "spec dimensions are meters."

### 3.2 Mechanism: fold meterization into the existing `basisTransform`

The engine already rewrites vertex data once at import: `Mesh.transformMeshBasis` multiplies position/normal/tangent/bitangent by the registered basis matrix and reverses winding iff det < 0 (Mesh.swift:156). A uniform scale composes cleanly into that same matrix:

- `det(s·B) = s³·det(B)` — sign unchanged, so the winding logic is untouched.
- Normals come out uniformly scaled, and every GBuffer shader normalizes after the normal-matrix multiply (GBuffer.metal:57–59), so lighting is safe. (Renormalizing at import anyway is a cheap belt-and-suspenders if we ever add a shader that skips it.)
- `UsdModel` also feeds `basisTransform` into `Skeleton` for the `B⁻¹·J·B` conjugation. With B = S·R and uniform S, rotations conjugate exactly as before (uniform scale commutes) and **joint translations scale by s — which is the correct meterization of the skeleton**. Verify visually with the F-35 gear animation once wired; this is the one subsystem where the scale flows somewhere non-obvious.

Concretely, registration grows a calibration argument (sketch):

```swift
// ModelLibrary.makeLibrary()
register(.F16) { ObjModel("f16r",
                          basisTransform: rotate180AroundY,
                          realWorldLength: 15.06) }        // meters, nose-to-tail

register(.CGTrader_F22) {
    UsdModel("cgtrader_F22",
             fileExtension: .USDZ,
             basisTransform: Transform.transformXMinusZYToXYZ,
             realWorldLength: 18.92)
}
```

Inside the loader, after the MDLAsset is parsed and *before* `transformMeshBasis` runs:

```swift
// Pseudocode — Model/Mesh import path
let nativeExtent = asset.boundingBox.maxBounds - asset.boundingBox.minBounds
// Length axis is engine +Z AFTER the basis permutation, so measure the
// native axis that the basis maps onto Z (pure permutation ⇒ just index).
let nativeLength = lengthAxisExtent(nativeExtent, basisTransform)
let s = realWorldLength / nativeLength            // meterization factor
let meterizedBasis = Transform.scaleMatrix(float3(repeating: s)) * (basisTransform ?? .identity)
// ...existing pipeline continues with meterizedBasis; log the result:
// "[ModelLibrary] F16 loaded: 15.06 m long (native 2.253 × 6.684)"
```

Alternative shape: a static `ModelMeterization` table keyed by `ModelType` holding *precomputed* factors (6.684, 1.002, 2.196, 0.01723, 0.03614) with the measured native lengths as comments. That skips the load-time bounding-box pass but goes stale if a model file is re-exported; measuring at import is one pass over data we're about to rewrite anyway, so **prefer measuring + the real-length table**. (This mirrors `AircraftThumbnailSpec`: one authored number per aircraft, next to its model registration.)

Where MPU is authored (USD), log the cross-check: `declared 0.01 ⇒ 10.98 m ≠ 18.92 m calibrated` — catches silently swapped/re-exported assets.

### 3.3 Migration checklist (what actually changes)

| Item | Today | After | Notes |
|---|---|---|---|
| `F16(scale:)` | 12.0 | 1.0 | FlightboxWithPhysics.swift:195 |
| `F18(scale:)` | 1.4 | 1.0 | :197 |
| `F22_CGTrader(scale:)` | 3.0 | 1.0 | :251 — **collider spec interplay, §3.5** |
| `F22(scale:)` (Sketchfab) | 0.25 | 1.0 | shrinks 14.5× on screen |
| `F35(scale:)` | 0.8 | 1.0 | shrinks 22× on screen |
| `Aircraft.cameraOffset` | default `[0,10,-20]` | retune per aircraft | tuned for ~26 u jets; jets become 15–19 m, so default is close but the oversized-jet overrides need a look |
| Camera `far` | 1000 | 20_000–50_000 | 1 km visibility is nothing in a jet; reverse-Z projection (already in place) is specifically what makes a 50 km far plane precise |
| Sky dome | 150 × 1000 = 150 km | keep | already beyond any sane far plane |
| Ground | 1e6 u = 1000 km | keep | |
| `engineMaxThrust` | 31_751 (kgf-as-N) | 311_410 N (×9.80665) | separate, behavior-changing commit; lift/drag constants were fit around the weak thrust and need a retune pass |
| Physics/gravity/masses | — | unchanged | already SI |
| Thumbnails | — | unchanged | `AircraftThumbnailGenerator` renders from the *file* via SceneKit with its own bounding-sphere framing; engine-side meterization never touches it |
| Parity baselines (plan step 0.7) | — | unchanged | synthetic sphere/plane scenarios, no models involved |

Float precision at meters is a non-issue for this game's envelope: Float32 has ~1 mm ULP at 10 km from origin, ~1 cm at 100 km. Camera-relative rendering / origin rebasing only becomes a topic with cross-country flights, and can stay out of scope.

### 3.4 Verification (the "1 m cube" ritual, adapted)

1. **Import-time log** (`realWorldLength` path above) — every aircraft load prints its meterized length; eyeball against the fact-sheet number.
2. **Unit test per aircraft**: load model Metal-free? — not possible today (Model needs Metal); instead test the *pure* factor math (`lengthAxisExtent` + factor computation) with the measured native extents as fixtures, exactly the Metal-free-helper pattern used everywhere else in the test suite.
3. **The collider overlay** (compound plan step 0.4) doubles as the visual check: a 0.45 m-radius sphere should look exactly torso-sized against the jet.
4. Optional: a literal 1 m reference cube GameObject in SandboxScene.

### 3.5 Sequencing against the compound-rigid-bodies plan

Do this **between Phase 0's harness and the collider-tuning exit criterion**:

- Phase 0 steps 0.1–0.3 (done) are unaffected — `ColliderShape`, specs, `uniformScale` all survive; only the *numbers* in `AircraftColliderSpec` change meaning.
- Land meterization, then author/tune the F-22 collider numbers **once, in meters** (fuselage capsule becomes roughly r ≈ 1.0 m, halfHeight ≈ 7.5 m, total ≈ 17 m — vs today's model-unit numbers that cover only ~66% of the fuselage: capsule total 5.7 u vs fuselage 8.6 u, a mismatch the overlay would have flagged anyway).
- The plan's step 0.5 "17.1 m anchor" arithmetic (`2·(2.4+0.45)·3.0`) becomes a direct read: the capsule's total height *is* its world meters.
- Phase B's suspension spring sizing (research doc §2.4: k ≈ 1.1 MN/m from a 0.45 m travel budget) stops depending on the ×3 scale assumption and uses real travel directly.

---

## Part 4 — Open questions / flags

1. **Keep the Sketchfab pair?** The F-22_Raptor.usdz embeds a **CC-BY-NC-SA-4.0** license (non-commercial, share-alike) in its metadata; the F-35 is CC-BY-4.0. Worth a conscious decision independent of scale work. Provenance URLs (from the files' own metadata): [Sketchfab F-22](https://sketchfab.com/3d-models/f-22-raptor-updated-fighter-jet-free-7bfc05d3916b454da4960fc17c093874), [Sketchfab F-35A](https://sketchfab.com/3d-models/f-35a-lightning-ii-a06d6113cfb44a0aa7b8f17106aca9c4).
2. **Reference dimension choice**: length is the best single calibration axis (unambiguous nose-to-tail; wingspan varies with tip missiles/pods — the F-16's quoted span differs by 0.5 m depending on source). Using length and *checking* span catches models with wrong aspect (none of ours).
3. **Temple / scenery**: 1024 u wide — meterize with its own plausible target (a 1 km temple is a choice, not a default) when scenery matters.
4. **`F35_JSF.usdc`** (CGTrader, unregistered): declares meters, Blender-authored; if it ever gets registered, same calibration path applies.

---

## References

Engine unit conventions:
- https://docs.unity3d.com/2020.1/Documentation/Manual/BestPracticeMakingBelievableVisuals1.html — Unity: 1 unit = 1 m, import Scale Factor, 1 m-cube verification
- https://techarthub.com/untangling-unit-scale-in-unity/ — Unity unit-scale practice
- https://techarthub.com/scale-and-measurement-inside-unreal-engine/ — Unreal: 1 uu = 1 cm
- https://www.worldofleveldesign.com/categories/ue5/guide-to-scale-dimensions-proportions.php — UE5 scale/dimensions guide
- https://dev.epicgames.com/documentation/en-us/unreal-engine/BlueprintAPI/Input/HeadMountedDisplay/SetWorldtoMetersScale — UE WorldToMeters

Format specifications:
- https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html — glTF 2.0 spec (units: meters) *(page returned 403 to automated fetch; content corroborated via the GitHub spec source below)*
- https://github.com/KhronosGroup/glTF/blob/main/specification/2.0/Specification.adoc — glTF 2.0 spec source
- https://github.com/KhronosGroup/glTF/issues/1725 — glTF units discussion
- https://openusd.org/dev/api/group___usd_geom_linear_units__group.html — USD `metersPerUnit`, cm fallback (0.01), consumer responsibilities
- https://docs.nvidia.com/learn-openusd/latest/beyond-basics/units.html — Units in OpenUSD ("values copied literally")
- https://docs.omniverse.nvidia.com/dev-guide/latest/programmer_ref/usd/stage/set-stage-linear-units.html — setting stage linear units
- https://projects.blender.org/blender/blender/issues/100448 — Blender not honoring MPU on import/export

Flight-sim & Apple ecosystem:
- https://developer.x-plane.com/article/obj8-file-format-specification/ — X-Plane OBJ8: models specified in meters
- https://xp-obj.readthedocs.io/en/latest/obj8/reference.html — OBJ8 reference
- https://medium.com/@shu223/how-to-use-usdz-files-with-arkit-scenekit-d2615bbb9963 — USDZ via MDLAsset/SceneKit
- https://rapidpipeline.com/en/a/optimize-3d-models-for-arkit/ — ARKit real-world-scale asset prep

Aircraft dimensions:
- https://www.af.mil/About-Us/Fact-Sheets/Display/Article/104506/f-22-raptor/ — F-22A: 62 ft 1 in / 44 ft 6 in
- https://en.wikipedia.org/wiki/Lockheed_Martin_F-22_Raptor — F-22A metric dims
- https://www.navair.navy.mil/product/FA-18EF-Super-Hornet — F/A-18E/F
- https://www.airforce.gov.au/aircraft/18f-super-hornet — F/A-18F: 18.31 m / 13.62 m
- https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon — F-16 dims
- https://aerocorner.com/comparison/f-35-vs-f-16/ — F-16 vs F-35A dims
- https://www.af.mil/About-Us/Fact-Sheets/Display/Article/478441/f-35a-lightning-ii/ — F-35A: 51.4 ft / 35 ft

Asset provenance (embedded in the USDZ files' own metadata, not fetched):
- https://sketchfab.com/3d-models/f-22-raptor-updated-fighter-jet-free-7bfc05d3916b454da4960fc17c093874 — Sketchfab F-22 (CC-BY-NC-SA-4.0)
- https://sketchfab.com/3d-models/f-35a-lightning-ii-a06d6113cfb44a0aa7b8f17106aca9c4 — Sketchfab F-35A (CC-BY-4.0)

Local measurements: the script below (run with `swift measure_models.swift`) — ModelIO `MDLAsset.boundingBox` over every model in `Core/Resources/Models/`; `usdcat` (macOS, `/usr/bin/usdcat`) for USD stage metadata (`usdcat file.usdz | head -18`).

## Appendix — measurement script

```swift
// measure_models.swift — native (pre-basis-transform) bounding boxes via ModelIO.
import Foundation
import ModelIO

let base = "<repo>/ToyFlightSimulator Shared/Core/Resources/Models"

let files: [(String, String)] = [
    ("F16  (f16r.obj)",      "\(base)/F16/f16r.obj"),
    ("F18  (FA-18F.obj)",    "\(base)/F18/FA-18F.obj"),
    ("F22 CGTrader (usdz)",  "\(base)/CGTrader/F22_low_poly/cgtrader_F22.usdz"),
    ("F22 Sketchfab (usdz)", "\(base)/Sketchfab/F-22_Raptor.usdz"),
    ("F35 Sketchfab (usdz)", "\(base)/Sketchfab/F-35A_Lightning_II.usdz"),
    ("sphere.obj",           "\(base)/Sphere/sphere.obj"),
    ("quad.obj",             "\(base)/Quad/quad.obj"),
    ("Temple.obj",           "\(base)/Temple/Temple.obj"),
]

func fmt(_ v: SIMD3<Float>) -> String {
    String(format: "[%8.3f, %8.3f, %8.3f]", v.x, v.y, v.z)
}

for (label, path) in files {
    guard FileManager.default.fileExists(atPath: path) else {
        print("\(label): MISSING at \(path)"); continue
    }
    let asset = MDLAsset(url: URL(fileURLWithPath: path))
    let bb = asset.boundingBox
    print(label)
    print("  min    \(fmt(bb.minBounds))")
    print("  max    \(fmt(bb.maxBounds))")
    print("  extent \(fmt(bb.maxBounds - bb.minBounds))   meshes: \(asset.count)")
}
```
