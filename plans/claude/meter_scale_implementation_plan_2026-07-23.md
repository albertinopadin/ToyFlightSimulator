# Per-Aircraft Meterization — Implementation Plan

**Date:** 2026-07-23
**Builds on:** `research/claude/meter_scale_units_research_2026-07-20.md` (design), the unstaged
`realWorldLength` changes in `Model.swift` / `ObjModel.swift` / `UsdModel.swift` / `ModelLibrary.swift` (mechanism, working).
**Status of your diff:** the import-time mechanism is **correct and confirmed working** — both F-22s log
18.92 m with exactly the factors the research doc predicted (2.196, 0.017228). What's left is (1) one real
bug the scale-bearing basis exposes in the skeleton/mesh-animation conjugation, (2) two small hardenings
to `GetLengthAxisExtent`, and (3) the consumer migration (scene scales, camera offsets, emitter offsets)
— which is also the entire explanation for the "tiny" Sketchfab F-22.

---

## 1. Why the Sketchfab F-22 renders tiny (no bug in your change)

Nothing in the meterization is wrong — the consumers just haven't been migrated:

1. **The scene still applies the old magic scale.** `FlightboxWithPhysics.getPlayerAcF22()` constructs
   `F22(scale: 0.25)` (FlightboxWithPhysics.swift:245). Before your change that turned the 1098-unit
   native model into a 274.6-unit giant; now it turns the 18.92 m meterized model into a **4.73 m** jet.
2. **The chase-camera offset is tuned for the giant.** `F22.cameraOffset` is `[0, 55, -150]`
   (F22.swift:16-18). `AttachedCamera.attach` sets that as the camera's **local position under the
   aircraft node** (AttachedCamera.swift:38), so world distance = offset × node scale =
   `0.25 × [0,55,-150]` ≈ **40 m** from the jet — same as before the change. A 4.73 m jet seen from
   40 m with a 75° FOV subtends ~7°, about 9% of screen height. That is the "tiny".

The CGTrader F-22 "looks right" for the accidental reason the research predicted: at `scale: 3.0` it's
now 3× real size (56.8 m), which reads as "nicely big" from its close-in `[0,3,-9]` camera. Both jets
converge to correct once the scenes stop scaling (§5).

---

## 2. `GetLengthAxisExtent` — verdict: correct, with two hardenings

**Correct as written** for every current registration:

- The row-vector convention `simd_float4(extent, w) * B` matches `Mesh.transformMeshBasis` exactly
  (Mesh.swift:163 does `simd_mul(float4(position, 1), basisTransform)`), so the measured axis is the
  axis the vertices actually land on.
- `abs(...z)` handles sign-flipping bases (`rotate180AroundY` maps native Z → engine −Z).
- Verified against all five aircraft (research §2.2 measurements + your logs):
  F16 `2.253` (native Z), F18 `18.267` (native Z), CGTrader `8.615` (native Y →
  `transformXMinusZYToXYZ` → Z), Sketchfab F-22 `1098.22` (native X → `transformYMinusZXToXYZ` → Z),
  F-35 `433.6` (native Z, **nil basis — works because the parameter defaults to identity**).

**Hardening 1 — use w = 0, not w = 1.** An extent is a *size vector*, not a point. With `w = 1` the
basis matrix's translation row is added into the extent; all current bases are pure
permutations/rotations with zero translation, so it's benign today, but a future recentering basis
would silently corrupt the calibration. `w = 0` also matches how `transformMeshBasis` treats
direction attributes (normals/tangents use `w = 0`).

**Hardening 2 — guard against a degenerate length** (missing/empty mesh ⇒ division by zero ⇒
`inf` scale correction ⇒ NaN vertices downstream).

```swift
// Model.swift
/// Extent of the model along the engine's forward axis (+Z) after `basisTransform`.
/// Contract: aircraft bases map the model's nose-to-tail axis onto ±Z (aircraft face
/// +Z in this engine), so this is the aircraft's length. Valid for the axis-permutation
/// /rotation bases used here; w = 0 so a translation-bearing basis can't offset a size.
static func GetLengthAxisExtent(nativeExtent: simd_float3, basisTransform: float4x4? = nil) -> Float {
    let transformedExtent: float3 = (simd_float4(nativeExtent, 0) * (basisTransform ?? .identity)).xyz
    return abs(transformedExtent.z)
}
```

```swift
// Model.init, after computing nativeLength:
precondition(nativeLength > 0.001,
             "[Model init] \(modelName): degenerate native length \(nativeLength) — cannot meterize")
```

One more property worth stating in a comment near the compose site: `det(S·B) = s³·det(B)`, so the
scale never flips the winding decision in `Mesh.transformMeshBasis` (Mesh.swift:171-176), and the
uniformly scaled normals/tangents are renormalized by every GBuffer variant
(GBuffer.metal:57-59, 102-104) — lighting is safe. Optionally renormalize in
`transformMeshBasis` as belt-and-suspenders.

---

## 3. Asset units: how to read them, and why we don't

**Ground truth (dev-time):** `usdcat` (macOS ships it; works directly on `.usdz`). Verified today:

| File | `metersPerUnit` | `upAxis` | Honoring MPU would give | Real |
|---|---|---|---|---|
| `F-22_Raptor.usdz` (Sketchfab) | **0.01** (cm) | Y | 10.98 m (58% of real) | 18.92 m |
| `F-35A_Lightning_II.usdz` (Sketchfab) | **0.01** (cm) | Y | 4.34 m (28% of real) | 15.67 m |
| `cgtrader_F22.usdz` (CGTrader/Blender) | **1** (m) | Z | 8.62 m (46% of real) | 18.92 m |
| OBJ files (F16, F18, …) | *format has no unit metadata* | — | — | — |

**Runtime:** there is no API. I grepped the macOS SDK's ModelIO and SceneKit headers for
`metersPerUnit` — zero hits. `MDLAsset` drops stage metadata entirely and returns bounds in raw file
units (your logs: 1098.2, not 10.98). RealityKit's USDZ loader does honor MPU, but it's not our
import path — and the table above shows MPU is *wrong* for every aircraft anyway, in both directions.

**Conclusion (unchanged from research §2.3):** the per-aircraft `realWorldLength` table is the
authoritative calibration; declared MPU stays a dev-time cross-check in
`scripts/measure_models.swift`. Record it as a comment next to each registration so a silent
re-export shows up in review (§4 diff). Caveat to remember: `MDLAsset.boundingBox` unions **all**
meshes in the file — an asset that ships with a pilot figure/ground crew/display stand would skew
calibration; the import log is the guard (eyeball it whenever a model file changes).

---

## 4. REQUIRED FIX before registering more aircraft: basis conjugation breaks under scale

`Skeleton.evaluateWorldPoses` (Skeleton.swift:187) and `TransformComponent.init`
(TransformComponent.swift:80-81) both map native-space animation deltas into engine space as
`B⁻¹ · M · B`. That is only correct while **Bᵀ = B⁻¹** (orthonormal bases — true for every
pre-meterization basis). Derivation of the general form:

- Mesh rewrite is row-vector: `v_e = v_n · B`, i.e. column form `v_e = Bᵀ · v_n`.
- The shader skins column-vector: `v' = P · v_e`, and ModelIO joint deltas `M = pose · bindInverse`
  are column-convention native-space maps.
- Requirement: `v_e' = Bᵀ · M · v_n = Bᵀ · M · (Bᵀ)⁻¹ · v_e` ⇒ **`P = Bᵀ · M · (Bᵀ)⁻¹`**.
- Orthonormal B: `Bᵀ = B⁻¹` ⇒ reduces exactly to today's `B⁻¹ · M · B`. ✓
- Meterized `B = S·B₀`: correct form gives `B₀ᵀ · (S·M·S⁻¹) · B₀` — joint **translations scale
  by s** (right). Today's form gives `S⁻¹·M·S` in the middle — translations **divide** by s:
  an **s² error**.

Concretely, in your current working tree: the CGTrader F-22 (s = 2.196) computes gear-clip and
control-surface pivot translations at 1/4.82 of their true arcs — toggle the gear and the struts
should sweep visibly wrong. Registering the F-35 (s = 0.0361) without this fix would put its gear
joints off by ~766×. (This corrects research doc §3.2, which claimed the skeleton path was
scale-safe — that derivation assumed row-vector convention end-to-end and missed the row/column
mix between mesh bake and shader skinning.)

**Fix** — swap to the transpose conjugation, which is bit-identical in behavior for the old
orthonormal bases and correct for scale-bearing ones. Single math home in `Transform`:

```swift
// Transform.swift (Math/)
/// Conjugation pair mapping a native-space animation delta M into engine space:
/// P = left · M · right with left = Bᵀ, right = (Bᵀ)⁻¹.
/// Mesh vertices are baked row-vector (v_e = v_n · B) while the shader skins
/// column-vector (P · v), hence the transpose. For orthonormal bases Bᵀ = B⁻¹,
/// so this equals the old B⁻¹ · M · B; with a meterization scale folded in
/// (B = S·B₀) it correctly scales joint translations by s (the old form divided
/// them by s — an s² error).
static func basisConjugationMatrices(for basisTransform: float4x4) -> (left: float4x4, right: float4x4) {
    let t = basisTransform.transpose
    return (t, t.inverse)
}
```

```swift
// Skeleton.swift — init (replaces the inverseBasisTransform cache, line 72)
private let conjugationLeft: float4x4?
private let conjugationRight: float4x4?
...
if let basisTransform {
    let pair = Transform.basisConjugationMatrices(for: basisTransform)
    conjugationLeft = pair.left
    conjugationRight = pair.right
} else {
    conjugationLeft = nil
    conjugationRight = nil
}
```

```swift
// Skeleton.evaluateWorldPoses — pass 2 (line 185-188)
if let conjugationLeft, let conjugationRight {
    for index in 0..<count {
        currentPose[index] = conjugationLeft * (currentPose[index] * inverseBindTransforms[index]) * conjugationRight
    }
}
```

```swift
// TransformComponent.init (lines 76-82)
if let basisTransform {
    let (left, right) = Transform.basisConjugationMatrices(for: basisTransform)
    return left * transformWithoutScale * right
}
```

Also update `TransformComponent`'s "GameObject.setScale() is the sole source of scale" comment
(line 63): the basis now intentionally carries the *meterization* scale; `setScale` remains the sole
source of *gameplay* scale.

---

## 5. Step-by-step

### Commit A — import-path correctness (no visual change)
1. `GetLengthAxisExtent`: `w = 0` + precondition (§2).
2. `Transform.basisConjugationMatrices` + Skeleton/TransformComponent conjugation swap (§4).
3. Tests (§7).

### Commit B — complete the registrations

```swift
// ModelLibrary.makeLibrary()
register(.F16) { ObjModel("f16r", basisTransform: rotate180AroundY,
                          realWorldLength: 15.06) }   // F-16C; OBJ has no unit metadata. native 2.253

// F18: native units ARE meters (measured 18.267 vs 18.31 real, −0.2%) — deliberately NOT
// meterized. SingleSubmeshMeshLibrary extracts its weapons/control surfaces through a path
// that bypasses Model.init; skipping both keeps fuselage and extracted parts exactly congruent.
register(.F18) { ObjModel("FA-18F", basisTransform: rotate180AroundY) }

register(.CGTrader_F22) {
    UsdModel("cgtrader_F22", fileExtension: .USDZ,
             basisTransform: Transform.transformXMinusZYToXYZ,
             realWorldLength: 18.92)   // declared MPU=1 would give 8.6 m (46% of real). native 8.615
}

register(.Sketchfab_F35) { UsdModel("F-35A_Lightning_II",
                                    realWorldLength: 15.67) }  // declared MPU=0.01 (cm). native 433.6

register(.Sketchfab_F22) {
    UsdModel("F-22_Raptor", basisTransform: Transform.transformYMinusZXToXYZ,
             realWorldLength: 18.92)   // declared MPU=0.01 would give 10.98 m (58% of real). native 1098.2
}
```

Expected import logs (the "1 m cube ritual"):

```
[Model init] Model f16r is 15.06m long (native: 2.253m, scale correction: 6.6844)
[Model init] Model cgtrader_F22 is 18.92m long (native: 8.615m, scale correction: 2.1961696)   ✓ already seen
[Model init] Model F-22_Raptor is 18.92m long (native: 1098.2236m, scale correction: 0.017227821)   ✓ already seen
[Model init] Model F-35A_Lightning_II is 15.67m long (native: 433.6m, scale correction: 0.0361394)
```

### Commit C — the world goes to meters (one atomic visual change)

**Scene scales → 1.0** (constructors already default to 1.0 — drop the arguments):

| Site | Today | After |
|---|---|---|
| FlightboxWithPhysics.swift:195 | `F16(scale: 12.0)` | `F16()` |
| FlightboxWithPhysics.swift:197 | `F18(scale: 1.4)` | `F18()` |
| FlightboxWithPhysics.swift:203 | `F35(scale: 0.8)` | `F35()` |
| FlightboxWithPhysics.swift:245 | `F22(scale: 0.25)` | `F22()` |
| FlightboxWithPhysics.swift:251 | `F22_CGTrader(scale: 3.0)` | `F22_CGTrader()` |
| FlightboxWithPhysics.swift:142 | `f16.setScale(10.0)` (static prop) | delete (or `1.0`) |
| FlightboxScene.swift:26 | `F22(scale: 0.25)` | `F22()` |
| FlightboxScene.swift:88 | `f16.setScale(4.0)` | delete |
| FlightboxWithTerrain.swift:30 | `F22(scale: 0.25)` | `F22()` |
| FlightboxWithTerrain.swift:67 | `f16.setScale(10.0)` | delete |
| FreeCamFlightboxScene.swift:48 | `jet.setScale(0.125)` | delete |
| FreeCamFlightboxScene.swift:54, 62 | missiles `setScale(4.0)` | `1.0` — extractions are native≈meters, so 1.0 = real size |

Unchanged on purpose: ground (`1_000_000` = 1000 km), sky domes, `aircraftStartPosition [0,100,0]`
(100 m altitude), random-object sizes 2–10 (now honest meters), `collisionRadius = 2.0`
(FlightboxWithPhysics.swift:208 — now a literal 2 m fuselage sphere; the compound-bodies plan
replaces it), `attachedCamera` far plane (already 1 000 000 in this scene).

**Camera offsets** — with scale = 1, `cameraOffset` is now literal meters. Values below preserve
each jet's old on-screen framing where the old framing was sane, and adopt sane values where it
never was (both Sketchfab jets had the camera *inside* the old giant model):

| Aircraft | Today | After | Rationale |
|---|---|---|---|
| `Aircraft` default | `[0, 10, -20]` | keep | ~1.1 jet-lengths behind a 15–19 m jet — good default |
| F16.swift:12 | `[0, 2, -5]` | `[0, 13, -33]` | preserves old world framing (loosest of the fleet — consider tightening toward `[0, 8, -22]`) |
| F18.swift:294 | `[0, 9, -20]` | keep | old world framing × new size lands on the same numbers |
| F22_CGTrader.swift:12 | `[0, 3, -9]` | `[0, 7, -20]` | preserves old world framing |
| F22.swift:17 | `[0, 55, -150]` | `[0, 7, -20]` | adopt CGTrader framing (same aircraft) |
| F35.swift:12 | `[0, -2, -24]` | `[0, 6, -18]` | F18-like framing for 15.67 m |

**Hardcoded child offsets on meterized aircraft are in model-local space and shrink by s.**
Audit result: only the Sketchfab F22's afterburners qualify (F22.swift:33,37 — the CGTrader F22 has
none; F18 parts self-position from submesh metadata). Mechanical conversion preserving the exact
model-relative point: `(±7, 1, -30) × 0.017228 = (±0.121, 0.017, -0.517)` — then re-place by eye;
for a center-origined 18.92 m jet the nozzles sit near `(±0.7, 0.1, -9.3)`, which suggests the old
values were never truly at the nozzles. While there: `Afterburner`/`Fire` particle descriptor
constants (speed, scale) are world-unit-based and were tuned against the giant jets — expect an
eyeball pass to shrink the plume.

### Ordering note
Commit A must land **before or with** B — your current tree already registers both F-22s, so the
CGTrader's gear/control-surface animation is running through the broken conjugation right now.
B and C can merge into one commit if you prefer the world to change size exactly once.

---

## 6. Verification ritual

1. **Logs** match the §5 table (every meterized aircraft prints its fact-sheet length).
2. **Gear toggle** on CGTrader F-22 and F-35, **stick deflection** on CGTrader (procedural
   surfaces): struts/surfaces sweep the same arcs as on a pre-meterization build. This is the
   regression test for §4 — wrong looks like surfaces orbiting tight/wide of their hinges.
3. **'C' → DebugCamera** fly-by: F-16 (15.06), F-18 (18.27), F-22s (18.92), F-35 (15.67) parked at
   scale 1 should look like siblings, not Russian dolls. A 2 m-radius debug sphere next to a jet
   should look torso-of-the-fuselage sized.
4. `swift scripts/measure_models.swift` still cross-checks declared MPU vs calibration offline.
5. Physics feel: falls/arcs stop reading "floaty" (gravity now acts on true-size bodies).

## 7. Tests (Metal-free, per project pattern)

New `ToyFlightSimulatorTests/AssetPipeline/ModelMeterizationTests.swift` (`.assetPipeline` tag) —
`Model.GetLengthAxisExtent` is a pure static, callable without constructing a Model:

- Fixture per aircraft: measured native extent × registered basis → expected length
  (`[1.47, 0.69, 2.253]` + `rotate180AroundY` → 2.253; `[6.22, 8.615, 2.456]` +
  `transformXMinusZYToXYZ` → 8.615; `[1098.22, 300.0, 784.0]` + `transformYMinusZXToXYZ` → 1098.22;
  `[302.5, 111.9, 433.6]` + nil → 433.6).
- Translation-bearing basis leaves the extent untouched (encodes the w = 0 hardening).
- Factor math: `18.92 / 8.615 ≈ 2.1962`; meterized basis = `scaleMatrix(s) * B` maps a native point
  to s × permuted point; `det` sign preserved (winding decision unchanged).

New `ToyFlightSimulatorTests/Math/BasisConjugationTests.swift` (`.math` tag) for
`Transform.basisConjugationMatrices`:

- Orthonormal basis (permutation, `rotate180AroundY`): `left·M·right ≈ B⁻¹·M·B` (old behavior
  preserved).
- `B = scaleMatrix(s) * B₀`: conjugating a pure translation `T(t)` yields translation `s · (B₀ᵀ t)`
  — the s-scaling property that was previously inverted; rotation blocks pass through unchanged.

## 8. Out of scope / follow-ups (unchanged from research §3.3–§3.5, Part 4)

- **Thrust fix** `31_751 → 311_410 N` + lift/drag retune — separate behavior-changing commit,
  much more visible now that masses act on true-size bodies.
- **Camera far defaults**: `Camera` base still defaults `far = 1000`; FlightboxWithPhysics'
  attached camera already overrides to 1e6. Align the default (20–50 km, reverse-Z handles it)
  when next touching Camera.
- **Collider specs in meters** — author `AircraftColliderSpec` numbers only after this lands
  (compound-bodies plan step 0.5 becomes a direct read).
- **Temple/scenery** meterization; **`F35_JSF.usdc`** if ever registered.
- **SingleSubmeshMesh meterization plumbing** — only needed if a non-meters asset ever feeds the
  extraction path (F18 doesn't need it).
- **Sketchfab licensing** (F-22 is CC-BY-NC-SA) — conscious decision, independent of scale.
- One-line CLAUDE.md note in the Asset System section: aircraft registrations pass
  `realWorldLength` (meters); imports meterize by folding the factor into `basisTransform`.
