# Sketchfab F-22 / F-35 render tiny after meterization — USD node-hierarchy scale counted in calibration but stripped at draw

**Date:** 2026-07-23
**Commit under investigation:** `77e33c2` "Implement per-aircraft meterization: 1 scene unit = 1 meter"
**Status:** Root cause confirmed by measurement. Fix (§5 diffs) APPLIED after review approval;
full suite green — 207 Swift Testing tests in 33 suites (201 pre-existing + 6 new) plus the
legacy XCTest suites, via `build-for-testing` + `test-without-building -parallel-testing-enabled NO`.
Remaining manual step: visual check of the Sketchfab F-22/F-35 against the 1 m cube (§6.3).

## 1. Symptom

After the meterization commit, with the red 1 m calibration cube in `FlightboxWithPhysics`:

| Screenshot | Aircraft | Expected | Observed |
|---|---|---|---|
| `debugging/screenshots/cgtrader_F22_correct_size.png` | CGTrader F-22 | 18.92 m | ~19 m ✓ |
| `debugging/screenshots/F22_tiny.png` | Sketchfab F-22 | 18.92 m | **~3 m** |
| `debugging/screenshots/F35_tiny.png` | Sketchfab F-35 | 15.67 m | **~1 m** |

Red herring eliminated early: both "tiny" screenshots show a large, correctly-sized aircraft
shadow near the player jet. That is **not** the player jet's shadow rendering at a different
size than its mesh — it's the F-16 prop that `FlightboxWithPhysics.buildScene` parks at
`jetPos + (0, +10, +15)` rotated 90° (`FlightboxWithPhysics.swift:138-141`), casting its
(correctly meterized, 15.06 m) shadow onto the ground while sitting above/off-frame. Shadow
pass and main pass draw the same geometry; there was never a pass mismatch.

## 2. Debugging log

### 2.1 What the meterization commit does

`Model.init` (`ToyFlightSimulator Shared/AssetPipeline/Model.swift:88-101`):

```swift
if let realWorldLength {
    let nativeExtent = loadedAsset.boundingBox.maxBounds - loadedAsset.boundingBox.minBounds
    let nativeLength = Self.GetLengthAxisExtent(nativeExtent: nativeExtent, basisTransform: basisTransform)
    ...
    let scaleCorrection = realWorldLength / nativeLength
    meterizedBasisTransform = scaleCorrectionTransform * (basisTransform ?? .identity)
```

`nativeLength` is measured from **`MDLAsset.boundingBox`** — *stage space*, i.e. with every
USD node-hierarchy transform (including **scale**) composed in. The resulting `s` is folded
into the basis transform and baked into **raw mesh-local vertex data** by
`Mesh.transformMeshBasis` (`Mesh.swift:159-177`).

### 2.2 What the renderer actually draws

Walking the draw path for a USDZ mesh:

1. **Vertex bake** — `Mesh.transformMeshBasis` multiplies *mesh-local* vertices by `s·B`
   (row-vector `v * B`). Node-hierarchy transforms are **not** part of the vertex data.
2. **Draw-time node transform** — `TransformComponent.init`
   (`Animation/TransformComponent.swift:59-85`) samples
   `MDLTransform.globalTransform(with:atTime:)` (the full composed node chain) but then
   **decomposes TRS and deliberately drops the scale**, keeping only rotation +
   scale-normalized translation:

   ```swift
   let (worldTranslation, rotation, scale) = Transform.decomposeTRS(globalTransform)
   let normalizedTranslation = float3(worldTranslation.x / scale.x, ...)   // scale divided out
   let transformWithoutScale = Transform.matrixFromTR(...)                  // scale dropped
   ```

   This is by design: *"This keeps GameObject.setScale() the sole source of gameplay scale."*
   `DrawManager.DrawFromRingBuffer` then applies it as `constants.modelMatrix *= localTransform`
   (`DrawManager.swift:553`).
3. **Skinning** — `Skeleton.evaluateWorldPoses` palettes are `Bᵀ·(pose·bindInverse)·(Bᵀ)⁻¹`;
   at bind pose that's ≈ identity. The skel-root/node scale never enters the palette either
   (all measured bind/rest transforms below have scale 1.0).

**Conclusion of the code walk:** a USD node-hierarchy scale `k` is *counted by the
calibration measurement* (stage-space bbox) but *never applied at draw*. Everything the
renderer draws is mesh-local geometry (`× s·B`) plus scale-stripped node rotation/translation.
So the drawn length = `realWorldLength / k`.

### 2.3 Measuring the actual files (diagnostic script, ModelIO)

Ran a standalone ModelIO script over the three USDZs (hierarchy walk + per-mesh local bboxes;
script content in Appendix A):

| Model | Stage bbox extent | Composed node scale k | Union of mesh-local bboxes | Skeletons |
|---|---|---|---|---|
| CGTrader F22 | [6.220, **8.615**, 2.457] | **1.0** everywhere | identical to stage | 1 (25 joints, bind scale 1.0) |
| Sketchfab F22 | [**1098.224**, 300.0, 784.017] | **5.7816** (`Meshes` node) | [**189.952**, 135.606, 51.889] | none (gear = separate `landingOn/Off` meshes) |
| Sketchfab F35 | [302.544, 111.936, **433.617**] | **15.0306** (`Meshes` node; inner 3.5533 × 0.2814 chains cancel) | [20.129, 28.849, 21.286] | 6 tiny 3-joint skins, bind scale 1.0 |

Cross-checks that nail the root cause:

- Sketchfab F22: 189.952 × 5.7816 = 1098.22 ✓ (stage = mesh-local × k)
- Predicted rendered length today: 18.92 / 5.7816 = **3.27 m** → matches `F22_tiny.png`
- Sketchfab F35: 28.849 × 15.0306 = 433.62 ✓
- Predicted rendered length today: 15.67 / 15.0306 = **1.04 m** → matches `F35_tiny.png`
- CGTrader: k = 1 → measurement space and draw space coincide → renders correctly. That's
  the *only* reason the CGTrader jet (and the runtime smoke test in the commit message)
  looked right: it has no node-hierarchy scale to disagree about.
- F16/F18 (OBJ): no node transforms at all → unaffected.

The research doc / `scripts/measure_models.swift` caveat had spotted the space mismatch but
only worried about **rotation** ("A USD root rotation ... can permute the NON-length axes"),
not **scale**:

> Caveat: MDLAsset.boundingBox is stage-space (USD root transforms applied), while the
> engine's basisTransform operates on mesh-local vertex data.

Sketchfab exports routinely carry root scales (glTF→USD unit conversion baked as a node
scale), and both Sketchfab models do.

### 2.4 Bonus finding: the Sketchfab F-22's node transforms are never applied at all

`MDLAsset.startTime == endTime == 0.0` for `F-22_Raptor.usdz`. `TransformComponent`'s
`keyTransforms` stride is empty and `setCurrentTransform` guards `duration > 0` →
`currentTransform` stays `.identity` forever. So for this model even the node *rotation* and
*translation* are dropped at draw; the hand-tuned `transformYMinusZXToXYZ` basis was
(correctly) authored against **mesh-local** axes, which is why the tiny jet still renders
upright. The F-35 (`endTime = 7.292`) *does* get node rotations/translations applied.
The fix must mirror this exactly (see `nodeTransformsApplyAtDraw` below).

### 2.5 Verifying the proposed measurement against the real files

Simulated the proposed draw-space measurement (mesh-local bounds → scale-stripped node
transform → union; script in Appendix B) on the actual assets:

```
=== CGTrader F22 ===   nodeTransformsApplyAtDraw=true
  stage  length 8.6150    s_old = 2.196170
  draw   length 8.6150    s_new = 2.196170       correction vs today: 1.0000x  → 18.92 m ✓
=== Sketchfab F22 ===  nodeTransformsApplyAtDraw=false   (empty time range)
  stage  length 1098.2236 s_old = 0.017228  → renders 3.27 m today
  draw   length 189.9520  s_new = 0.099604       correction vs today: 5.7816x  → 18.92 m ✓
=== Sketchfab F35 ===  nodeTransformsApplyAtDraw=true
  stage  length 433.6170  s_old = 0.036138  → renders 1.04 m today
  draw   length 28.8490   s_new = 0.543173       correction vs today: 15.0306x → 15.67 m ✓
```

CGTrader and the OBJ aircraft are bit-identical under the new measurement (k = 1 / no node
transforms), so nothing else moves.

## 3. Root cause (one paragraph)

Meterization calibrates `s = realWorldLength / nativeLength` with `nativeLength` measured in
**USD stage space** (`MDLAsset.boundingBox`, node-hierarchy transforms *including scale*
composed), but bakes `s` into **mesh-local** vertex data, and the engine's draw path
deliberately strips node-hierarchy scale (`TransformComponent` keeps only rotation +
normalized translation so `GameObject.setScale()` stays the sole gameplay scale). Any USD
root scale `k` therefore inflates the measured native length by `k` without ever being drawn,
and the aircraft renders at `realWorldLength / k`: Sketchfab F-22 `k = 5.7816` → 3.27 m,
Sketchfab F-35 `k = 15.0306` → 1.04 m, CGTrader `k = 1` → correct, which masked the bug in
the commit's smoke test.

## 4. Fix

### 4.1 Options considered

1. **Measure in draw space** (chosen): compute the calibration extent exactly the way the
   renderer composes geometry — union of per-mesh *local* bounding boxes carried through each
   mesh's *scale-stripped* node transform, applied only when the renderer would apply it.
   Surgical: only the measurement changes; every downstream consumer (vertex bake, skeleton
   conjugation, TransformComponent conjugation) picks up the corrected `s` coherently.
2. **Stop stripping node scale at draw** (rejected): would honor stage space, but it breaks
   the documented `GameObject.setScale()` contract, doesn't reach the skinned path (palettes
   don't carry node transforms — F-35 skinned parts would mismatch their non-skinned
   neighbors), and would resize every already-tuned USDZ asset. Far larger blast radius for
   the same visual result.
3. **Hand-tune `realWorldLength` by k** (rejected): e.g. register the F-35 as `15.67 × 15.03`.
   Works numerically but re-introduces exactly the magic-number problem meterization removed,
   and breaks the "registration states the real aircraft length" contract.

### 4.2 Design of the chosen fix

- New `Transform.scaleStrippedTransform(_:)` — extracts the *exact* strip logic
  `TransformComponent` uses today (decomposeTRS → translation ÷ scale → matrixFromTR).
  `TransformComponent` switches to call it, so the measurement and the draw path share one
  implementation and cannot drift.
- New `Model.DrawSpaceNativeExtent(asset:mdlMeshes:)` — per-mesh local bbox through the
  scale-stripped composed node transform, unioned. A mesh's node transform participates
  **exactly when the renderer applies it**: `mesh.transform != nil` (that's when `Mesh`
  creates a `TransformComponent`) **and** `asset.endTime > asset.startTime` (otherwise
  `setCurrentTransform` leaves identity — the Sketchfab F-22 case).
- New `Model.UnionTransformedExtent(meshBounds:)` — the pure simd 8-corner union, split out
  so it's Metal-free unit-testable (per the project's Metal-free test design rule).
- `Model.init` feeds `GetLengthAxisExtent` from `DrawSpaceNativeExtent` instead of
  `loadedAsset.boundingBox`. `GetLengthAxisExtent` itself is unchanged — the union is in
  stage *axes* (rotations applied where the renderer applies them), which is the same space
  the registered basis transforms were authored against, so the length-axis mapping
  (`F22 → X`, `F35 → Z`, `CGTrader → Y`) still holds. (For the F-22, whose node transforms
  never apply, mesh-local X is the length axis and the measured 189.952 confirms it.)
- Knock-on: the Sketchfab F-22 afterburner offsets in `F22.swift` were mechanically rescaled
  by the old (wrong) `s = 0.01723`; they get the same ×5.7816 correction so they keep their
  model-relative placement. (The "eyeball against actual nozzles" TODO stands.)
- Fixtures in `ModelMeterizationTests` move to draw-space extents; new tests pin the
  scale-stripping + union behavior, including a regression test for this exact bug.

Why per-mesh union instead of `stage bbox ÷ k`: k is not guaranteed uniform per mesh (the
F-35 has 3.5533 × 0.2814 chains), and the renderer's translation normalization
(`worldTranslation / composedScale`) is a heuristic that this measurement must *mirror*, not
idealize. Mirroring the draw path exactly is the only definition of "native length" that
can't drift from what's on screen.

### 4.3 Predicted post-fix values

| Model | nativeLength (draw space) | s | Rendered length |
|---|---|---|---|
| CGTrader F22 | 8.615 (Y) | 2.196170 (unchanged) | 18.92 m (unchanged) |
| Sketchfab F22 | 189.952 (X) | 0.099604 (was 0.017228) | 18.92 m (was 3.27) |
| Sketchfab F35 | 28.849 (Z) | 0.543173 (was 0.036138) | 15.67 m (was 1.04) |
| F16 (OBJ) | 2.253 (Z) | 6.684 (unchanged) | 15.06 m (unchanged) |

Coherence of everything `s` touches, at the new values: vertex bake ×s; skeleton palette
conjugation scales joint translations ×s (F-35 gear-door skins); TransformComponent
conjugation scales node translations ×s (F-35 part placement). All three scale together, so
the aircraft grow uniformly — same guarantee the original commit argued for, now with the
right `s`.

## 5. Proposed diffs

> Base: current working tree (includes the uncommitted `DebugLog` tweak in `Model.swift`
> and the calibration cubes in `FlightboxWithPhysics.swift`, which are kept — the red
> ground-level cube is the verification prop).

### 5.1 `ToyFlightSimulator Shared/Math/Transform.swift`

Add the shared strip helper right after `matrixFromTR` (line ~219):

```diff
     /// Reconstructs a 4x4 matrix from translation and rotation only (no scale).
     static func matrixFromTR(translation: float3, rotation: float4x4) -> float4x4 {
         var result = rotation
         result.columns.3 = float4(translation, 1)
         return result
     }
+
+    /// The node-transform shape the renderer actually applies: rotation plus
+    /// scale-normalized translation, with the scale itself dropped.
+    ///
+    /// `TransformComponent` strips USD node scale so `GameObject.setScale()` stays the
+    /// sole source of gameplay scale (the import-time meterization scale rides in the
+    /// mesh bake / basis conjugation instead), and `Model.DrawSpaceNativeExtent` must
+    /// measure in exactly that space — both call this one helper so the draw path and
+    /// the calibration measurement cannot drift apart.
+    ///
+    /// The composed matrix's translation is in scaled (stage) units; dividing by the
+    /// decomposed scale returns it to the node's unscaled space. Zero-ish scale
+    /// components pass the translation through unchanged.
+    static func scaleStrippedTransform(_ matrix: float4x4) -> float4x4 {
+        let (worldTranslation, rotation, scale) = decomposeTRS(matrix)
+        let normalizedTranslation = float3(
+            scale.x > 0.0001 ? worldTranslation.x / scale.x : worldTranslation.x,
+            scale.y > 0.0001 ? worldTranslation.y / scale.y : worldTranslation.y,
+            scale.z > 0.0001 ? worldTranslation.z / scale.z : worldTranslation.z
+        )
+        return matrixFromTR(translation: normalizedTranslation, rotation: rotation)
+    }
 }
```

### 5.2 `ToyFlightSimulator Shared/Animation/TransformComponent.swift`

Replace the inline strip block with the shared helper (behavior-identical — the code moved
into `Transform.scaleStrippedTransform` verbatim):

```diff
         keyTransforms = Array(timeStride).map { time in
             let globalTransform = MDLTransform.globalTransform(with: object, atTime: time)
 
-            // Decompose the USDZ transform into T, R, S components.
-            // The globalTransform's translation is in WORLD coordinates (after USDZ scale applied),
-            // so we must normalize it by dividing by the scale to get model-local translation.
-            // This keeps GameObject.setScale() the sole source of gameplay scale (the basis
-            // conjugation below may still carry the import-time meterization scale).
-            let (worldTranslation, rotation, scale) = Transform.decomposeTRS(globalTransform)
-
-            // Normalize translation: convert from world coords back to model-local coords
-            // by dividing by the USDZ scale. Avoid division by zero.
-            let normalizedTranslation = float3(
-                scale.x > 0.0001 ? worldTranslation.x / scale.x : worldTranslation.x,
-                scale.y > 0.0001 ? worldTranslation.y / scale.y : worldTranslation.y,
-                scale.z > 0.0001 ? worldTranslation.z / scale.z : worldTranslation.z
-            )
-
-            let transformWithoutScale = Transform.matrixFromTR(translation: normalizedTranslation, rotation: rotation)
+            // Strip the USDZ node scale — rotation + scale-normalized translation only.
+            // GameObject.setScale() stays the sole source of gameplay scale (the basis
+            // conjugation below may still carry the import-time meterization scale), and
+            // Model.DrawSpaceNativeExtent measures calibration extents through this same
+            // helper so imports are calibrated in the space that is actually drawn.
+            let transformWithoutScale = Transform.scaleStrippedTransform(globalTransform)
 
             if let conjugation {
                 // Map the native-space delta into engine space — Bᵀ * M * (Bᵀ)⁻¹, see
                 // Transform.basisConjugationMatrices.
                 return conjugation.left * transformWithoutScale * conjugation.right
             }
             return transformWithoutScale
         }
```

### 5.3 `ToyFlightSimulator Shared/AssetPipeline/Model.swift`

Measurement space change + the two new statics:

```diff
     /// Extent of the model along the engine's forward axis (+Z) after `basisTransform`.
     /// Aircraft bases map the model's nose-to-tail axis onto ±Z (aircraft face +Z in
     /// this engine), so this is the aircraft's length. Row-vector `v * B`, matching
     /// `Mesh.transformMeshBasis`; w = 0 because an extent is a size, not a point — a
     /// translation-bearing basis must not offset it.
     static func GetLengthAxisExtent(nativeExtent: simd_float3, basisTransform: float4x4? = nil) -> Float {
         let transformedExtent: float3 = (simd_float4(nativeExtent, 0) * (basisTransform ?? .identity)).xyz
         return abs(transformedExtent.z)
     }
+
+    /// The native-space extent the renderer will actually draw (before `basisTransform`):
+    /// the union, over the asset's meshes, of each MESH-LOCAL bounding box carried through
+    /// that mesh's scale-stripped composed node transform.
+    ///
+    /// `MDLAsset.boundingBox` is the wrong measurement space for meterization: it composes
+    /// the full node-hierarchy transforms INCLUDING scale, but the engine bakes mesh-local
+    /// vertex data (`Mesh.transformMeshBasis`) and applies node transforms at draw time
+    /// with the scale stripped (`TransformComponent` — `GameObject.setScale()` is the sole
+    /// source of gameplay scale). Sketchfab exports carry root node scales (F-22 Raptor
+    /// ×5.78, F-35A ×15.03) that made the stage-space measurement over-report the native
+    /// length — and the meterized aircraft rendered smaller by exactly that factor. See
+    /// debugging/claude/sketchfab_f22_f35_meterization_node_scale.md.
+    ///
+    /// A mesh's node transform participates exactly when the renderer would apply it: the
+    /// mesh has a transform component AND the asset is animated —
+    /// `TransformComponent.setCurrentTransform` leaves `currentTransform` at identity when
+    /// the asset time range is empty (the Sketchfab F-22 is such an asset: its node
+    /// transforms exist but never apply at draw).
+    static func DrawSpaceNativeExtent(asset: MDLAsset, mdlMeshes: [MDLMesh]) -> simd_float3 {
+        let nodeTransformsApplyAtDraw = asset.endTime > asset.startTime
+        let meshBounds: [(minBounds: float3, maxBounds: float3, nodeTransform: float4x4)] = mdlMeshes.map { mesh in
+            let bounds = mesh.boundingBox
+            let nodeTransform: float4x4 = (nodeTransformsApplyAtDraw && mesh.transform != nil)
+                ? Transform.scaleStrippedTransform(MDLTransform.globalTransform(with: mesh, atTime: asset.startTime))
+                : .identity
+            return (bounds.minBounds, bounds.maxBounds, nodeTransform)
+        }
+        return UnionTransformedExtent(meshBounds: meshBounds)
+    }
+
+    /// Union AABB extent of local bounds each carried through its own node transform
+    /// (column-vector ModelIO convention, `p' = M · p`). Pure simd — Metal-free and
+    /// unit-testable (ModelMeterizationTests).
+    static func UnionTransformedExtent(meshBounds: [(minBounds: float3, maxBounds: float3, nodeTransform: float4x4)]) -> simd_float3 {
+        guard !meshBounds.isEmpty else { return .zero }
+        var unionMin = float3(repeating: .greatestFiniteMagnitude)
+        var unionMax = float3(repeating: -.greatestFiniteMagnitude)
+        for (minBounds, maxBounds, nodeTransform) in meshBounds {
+            for cornerIndex in 0..<8 {
+                let corner = float3(cornerIndex & 1 == 0 ? minBounds.x : maxBounds.x,
+                                    cornerIndex & 2 == 0 ? minBounds.y : maxBounds.y,
+                                    cornerIndex & 4 == 0 ? minBounds.z : maxBounds.z)
+                let transformed = simd_mul(nodeTransform, float4(corner, 1)).xyz
+                unionMin = simd_min(unionMin, transformed)
+                unionMax = simd_max(unionMax, transformed)
+            }
+        }
+        return unionMax - unionMin
+    }
```

```diff
         DebugLog("[Model init] \(modelName) asset has \(loadedAsset.count) top level objects.", true)
-        
+
+        let mdlMeshes = loadedAsset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
+
         let meterizedBasisTransform: float4x4?
         
         if let realWorldLength {
-            let nativeExtent = loadedAsset.boundingBox.maxBounds - loadedAsset.boundingBox.minBounds
+            // Draw-space, NOT loadedAsset.boundingBox (stage space): the renderer strips
+            // node-hierarchy scale, so calibration must measure what is actually drawn.
+            let nativeExtent = Self.DrawSpaceNativeExtent(asset: loadedAsset, mdlMeshes: mdlMeshes)
             let nativeLength = Self.GetLengthAxisExtent(nativeExtent: nativeExtent, basisTransform: basisTransform)
             precondition(nativeLength > 0.001,
                          "[Model init] \(modelName): degenerate native length \(nativeLength) — cannot meterize")
             let scaleCorrection = realWorldLength / nativeLength
             // Uniform scale: det(s·B) = s³·det(B) keeps the sign, so the winding decision in
             // Mesh.transformMeshBasis is unchanged; shaders renormalize the scaled normals.
             let scaleCorrectionTransform = Transform.scaleMatrix(float3(repeating: scaleCorrection))
             meterizedBasisTransform = scaleCorrectionTransform * (basisTransform ?? .identity)
             DebugLog("[Model init] Model \(modelName) is \(realWorldLength)m long (native: \(nativeLength)m, scale correction: \(scaleCorrection)), result: \(nativeLength * scaleCorrection)", true)
         } else {
             meterizedBasisTransform = basisTransform
         }
 
-        let mdlMeshes = loadedAsset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
-
         Self.InspectMeshes(mdlMeshes: mdlMeshes)
```

### 5.4 `ToyFlightSimulator Shared/AssetPipeline/Libraries/Models/ModelLibrary.swift`

Comment-only: record the draw-space native lengths the registrations now calibrate against.

```diff
-        // Declared MPU=0.01 (cm) would give 4.34 m — 28% of real; native length 433.6 on Z (no basis needed).
+        // Declared MPU=0.01 (cm) would give 4.34 m — 28% of real. Draw-space native length
+        // 28.85 on Z (stage 433.6 ÷ the ×15.03 'Meshes' node scale, which the renderer strips).
         register(.Sketchfab_F35) { UsdModel("F-35A_Lightning_II", realWorldLength: 15.67) }
 
-        // Declared MPU=0.01 (cm) would give 10.98 m — 58% of real; native length 1098.2 on X.
+        // Declared MPU=0.01 (cm) would give 10.98 m — 58% of real. Draw-space native length
+        // 189.95 on X (stage 1098.2 ÷ the ×5.78 root node scale; this asset's time range is
+        // empty, so its node transforms never apply at draw and vertices render mesh-local).
         register(.Sketchfab_F22) {
             UsdModel("F-22_Raptor", basisTransform: Transform.transformYMinusZXToXYZ, realWorldLength: 18.92)
         }
```

### 5.5 `ToyFlightSimulator Shared/GameObjects/F22.swift`

The afterburner offsets were the old native-unit offsets × the old (wrong) s = 0.017228;
multiply by the 5.7816 correction so they keep the same model-relative placement under the
new s = 0.099604.

```diff
-        // Mechanical ×s rescale (s = 0.01723, the meterization factor) of the old
-        // native-unit offsets — same model-relative placement as before.
+        // Mechanical ×s rescale (s = 0.09960, the draw-space meterization factor) of the
+        // old native-unit offsets — same model-relative placement as before.
         // TODO(meterization): eyeball against the actual nozzles in meters.
         afterburnerLeft.off()
-        afterburnerLeft.setPosition(-0.121, 0.017, -0.517)
+        afterburnerLeft.setPosition(-0.700, 0.098, -2.989)
         addChild(afterburnerLeft)
 
         afterburnerRight.off()
-        afterburnerRight.setPosition(0.121, 0.017, -0.517)
+        afterburnerRight.setPosition(0.700, 0.098, -2.989)
         addChild(afterburnerRight)
```

### 5.6 `ToyFlightSimulatorTests/AssetPipeline/ModelMeterizationTests.swift`

Fixtures move to draw-space extents; new tests pin the strip + union helpers and the
regression itself.

```diff
-/// Pure meterization math in `Model` — no Metal, no Model construction. Native
-/// (pre-basis) bounding-box extents measured by `scripts/measure_models.swift`
-/// (research/claude/meter_scale_units_research_2026-07-20.md §2.2) serve as fixtures.
+/// Pure meterization math in `Model` — no Metal, no Model construction. Fixtures are
+/// DRAW-SPACE native extents (mesh-local bounds through scale-stripped node transforms —
+/// the space `Model.DrawSpaceNativeExtent` measures and the renderer draws), measured in
+/// debugging/claude/sketchfab_f22_f35_meterization_node_scale.md §2. Stage-space numbers
+/// (`MDLAsset.boundingBox`, scripts/measure_models.swift §2.2) over-count USD node scale
+/// and must NOT be used as fixtures here.
 @Suite("Model meterization", .tags(.assetPipeline))
 struct ModelMeterizationTests {
```

```diff
     @Test("nil basis reads the native Z extent (F-35 registration shape)")
     func nilBasisReadsNativeZ() {
-        let f35Extent = SIMD3<Float>(302.5, 111.9, 433.6)
-        #expect(approxEqual(Model.GetLengthAxisExtent(nativeExtent: f35Extent), 433.6))
+        let f35Extent = SIMD3<Float>(25.306, 6.175, 28.849)
+        #expect(approxEqual(Model.GetLengthAxisExtent(nativeExtent: f35Extent), 28.849))
     }
```

```diff
     @Test("Sketchfab F-22 basis maps native X (length axis) onto engine Z")
     func sketchfabBasisReadsNativeX() {
-        let extent = SIMD3<Float>(1098.2236, 300.0, 784.0)
+        // Mesh-local union — this asset's node transforms never apply at draw (empty time range).
+        let extent = SIMD3<Float>(189.952, 135.606, 51.889)
         let length = Model.GetLengthAxisExtent(nativeExtent: extent,
                                                basisTransform: Transform.transformYMinusZXToXYZ)
-        #expect(approxEqual(length, 1098.2236, tolerance: 1e-3))
+        #expect(approxEqual(length, 189.952, tolerance: 1e-3))
     }
```

```diff
     @Test("calibration factors reproduce the research-doc table")
     func calibrationFactors() {
         // realWorldLength / nativeLength — the exact computation Model.init performs.
         let cgtrader = 18.92 / Model.GetLengthAxisExtent(nativeExtent: [6.220, 8.615, 2.456],
                                                          basisTransform: Transform.transformXMinusZYToXYZ)
         #expect(approxEqual(cgtrader, 2.1961696))
 
-        let sketchfabF22 = 18.92 / Model.GetLengthAxisExtent(nativeExtent: [1098.2236, 300.0, 784.0],
+        let sketchfabF22 = 18.92 / Model.GetLengthAxisExtent(nativeExtent: [189.952, 135.606, 51.889],
                                                              basisTransform: Transform.transformYMinusZXToXYZ)
-        #expect(approxEqual(sketchfabF22, 0.017227821, tolerance: 1e-6))
+        #expect(approxEqual(sketchfabF22, 0.0996040, tolerance: 1e-6))
 
         let f16 = 15.06 / Model.GetLengthAxisExtent(nativeExtent: [1.47, 0.69, 2.253],
                                                     basisTransform: Self.rotate180AroundY)
         #expect(approxEqual(f16, 6.6844, tolerance: 1e-3))
 
-        let f35 = 15.67 / Model.GetLengthAxisExtent(nativeExtent: [302.5, 111.9, 433.6])
-        #expect(approxEqual(f35, 0.0361393, tolerance: 1e-5))
+        let f35 = 15.67 / Model.GetLengthAxisExtent(nativeExtent: [25.306, 6.175, 28.849])
+        #expect(approxEqual(f35, 0.5431731, tolerance: 1e-5))
     }
```

```diff
     @Test("uniform scale preserves the winding-decision determinant sign")
     func meterizedBasisPreservesWindingSign() {
         // Sketchfab F-22's basis is orientation-reversing (det < 0) — the case where
         // Mesh.transformMeshBasis reverses triangle winding. det(s·B) = s³·det(B)
         // must keep that decision unchanged.
         let basis = Transform.transformYMinusZXToXYZ
-        let meterized = Transform.scaleMatrix(SIMD3<Float>(repeating: 0.017227821)) * basis
+        let meterized = Transform.scaleMatrix(SIMD3<Float>(repeating: 0.0996040)) * basis
         #expect(det3x3(basis) < 0)
         #expect((det3x3(meterized) < 0) == (det3x3(basis) < 0))
     }
```

New tests, appended before the private `det3x3` helper:

```diff
+    // MARK: - Draw-space measurement (scale-stripped node transforms)
+
+    @Test("scaleStrippedTransform drops scale, keeps rotation, and unscales translation")
+    func scaleStrippedTransformDropsScale() {
+        let rotation = Transform.rotationMatrix(radians: Float(90).toRadians, axis: [1, 0, 0])
+        let trs = Transform.matrixFromTR(translation: [10, -20, 30], rotation: rotation)
+            * Transform.scaleMatrix(SIMD3<Float>(repeating: 5.7816))
+        let stripped = Transform.scaleStrippedTransform(trs)
+        let expected = Transform.matrixFromTR(translation: SIMD3<Float>(10, -20, 30) / 5.7816,
+                                              rotation: rotation)
+        #expect(approxEqual(stripped, expected, tolerance: 1e-5))
+    }
+
+    @Test("scaleStrippedTransform is the identity on scale-free transforms")
+    func scaleStrippedTransformIdentityPassthrough() {
+        let rotation = Transform.rotationMatrix(radians: Float(37).toRadians, axis: [0, 1, 0])
+        let tr = Transform.matrixFromTR(translation: [1, 2, 3], rotation: rotation)
+        #expect(approxEqual(Transform.scaleStrippedTransform(tr), tr, tolerance: 1e-5))
+    }
+
+    @Test("UnionTransformedExtent with identity transforms is the plain bbox union (CGTrader shape)")
+    func unionExtentIdentityTransforms() {
+        let extent = Model.UnionTransformedExtent(meshBounds: [
+            (minBounds: [-3.11, -4.31, -1.23], maxBounds: [3.11, 4.31, 1.23], nodeTransform: .identity),
+        ])
+        #expect(approxEqual(extent, SIMD3<Float>(6.22, 8.62, 2.46), tolerance: 1e-2))
+        #expect(Model.UnionTransformedExtent(meshBounds: []) == .zero)
+    }
+
+    @Test("node rotation reorients a mesh-local box (F-35 'Meshes' node shape)")
+    func unionExtentAppliesNodeRotation() {
+        // 90° about X maps local Y onto stage Z — the F-35's length lands on Z.
+        let rotX90 = Transform.rotationMatrix(radians: Float(90).toRadians, axis: [1, 0, 0])
+        let extent = Model.UnionTransformedExtent(meshBounds: [
+            (minBounds: [0, 0, 0], maxBounds: [20, 29, 7], nodeTransform: rotX90),
+        ])
+        #expect(approxEqual(extent, SIMD3<Float>(20, 7, 29), tolerance: 1e-3))
+    }
+
+    @Test("per-mesh node translations spread the union (multi-part assemblies)")
+    func unionExtentSpreadsTranslatedParts() {
+        let forward = Transform.matrixFromTR(translation: [0, 0, 10], rotation: .identity)
+        let aft = Transform.matrixFromTR(translation: [0, 0, -10], rotation: .identity)
+        let cube: (SIMD3<Float>, SIMD3<Float>) = ([-1, -1, -1], [1, 1, 1])
+        let extent = Model.UnionTransformedExtent(meshBounds: [
+            (minBounds: cube.0, maxBounds: cube.1, nodeTransform: forward),
+            (minBounds: cube.0, maxBounds: cube.1, nodeTransform: aft),
+        ])
+        #expect(approxEqual(extent, SIMD3<Float>(2, 2, 22)))
+    }
+
+    @Test("regression: a scale-bearing node transform, once stripped, cannot shrink the meterized aircraft")
+    func strippedNodeScaleDoesNotShrinkExtent() {
+        // The bug this file now guards against: MDLAsset.boundingBox counted the Sketchfab
+        // F-22's ×5.7816 root node scale, which TransformComponent strips at draw time, so
+        // s came out 5.78× too small and the jet rendered 3.27 m long.
+        let scaleOnlyNode = Transform.scaleMatrix(SIMD3<Float>(repeating: 5.7816))
+        let stripped = Transform.scaleStrippedTransform(scaleOnlyNode)
+        let extent = Model.UnionTransformedExtent(meshBounds: [
+            (minBounds: [0, 0, 0], maxBounds: [189.952, 135.606, 51.889], nodeTransform: stripped),
+        ])
+        #expect(approxEqual(extent, SIMD3<Float>(189.952, 135.606, 51.889), tolerance: 1e-3))
+        let s = 18.92 / Model.GetLengthAxisExtent(nativeExtent: extent,
+                                                  basisTransform: Transform.transformYMinusZXToXYZ)
+        #expect(approxEqual(s, 0.0996040, tolerance: 1e-5))
+    }
+
     private func det3x3(_ m: float4x4) -> Float {
```

## 6. How to verify after applying

1. **Unit tests** (Metal-free suite included):
   `xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
   (or the `build-for-testing` + `test-without-building -parallel-testing-enabled NO` flow).
2. **Import logs**: on selecting each aircraft, `Model init` should print
   - `F-22_Raptor is 18.92m long (native: 189.952m, scale correction: 0.099604...)`
   - `F-35A_Lightning_II is 15.67m long (native: 28.849m, scale correction: 0.543173...)`
   - `cgtrader_F22 is 18.92m long (native: 8.615m, scale correction: 2.19617)` — unchanged.
3. **Visual**: in `FlightboxWithPhysics`, swap to Sketchfab F-22 and F-35 and compare against
   the red 1 m ground cube (same camera framing as the three screenshots). Expect ~19 m and
   ~15.7 m planes; CGTrader and F-16 unchanged. Gear animations should still articulate with
   arcs proportional to the (now larger) aircraft — the Bᵀ conjugation scales joint/node
   translations by the same new s as the vertices.

## 7. Follow-ups and related observations (not part of this fix)

- **`scripts/measure_models.swift` still reports stage space.** Its §2.2 table (and the
  research doc) will no longer match the registration comments for the two Sketchfab models.
  Follow-up: port `DrawSpaceNativeExtent` (mesh-local union through
  `scaleStrippedTransform`, honoring the empty-time-range rule) into the script and refresh
  the table. Until then the script's own caveat comment under-states the problem (it only
  mentions axis permutation, not scale).
- **Player collider is still `collisionRadius = 2.0`** (`FlightboxWithPhysics.swift:220`) —
  the "collider specs authored in meters" follow-up from the meterization plan gets more
  visible now that the F-22/F-35 are full-size.
- **F-35 assembly is defined by the engine's translation heuristic, not the USD stage.** The
  draw-space union `[25.31, 6.17, 28.85]` differs from `stage ÷ k = [20.13, 7.45, 28.85]` on
  the non-length axes: `TransformComponent` divides the *composed* translation by the
  *composed* scale, which is not the same as unscaling each hierarchy level (the F-35 has
  nested 3.55 × 0.28 chains). Parts therefore sit slightly differently than the stage
  intends — a pre-existing behavior this fix deliberately mirrors rather than changes. If
  F-35 part placement looks off at full size, that heuristic is the place to look.
- **Afterburner nozzle placement** on the Sketchfab F-22 keeps its "mechanical rescale +
  eyeball later" TODO; the diff above only preserves the pre-meterization relative placement.
- The Sketchfab F-22's gear is not skeletal and not node-animated (empty asset time range,
  no skeletons) — it ships alternate `landingOn/landingOff` meshes; nothing in this fix
  touches that path.

## Appendix A — hierarchy/scale diagnostic (run with `swift <file> ` from the repo root)

Saved during the session at
`scratchpad/inspect_node_scales.swift`; key logic:

```swift
let asset = MDLAsset(url: URL(fileURLWithPath: path))
let stageExtent = asset.boundingBox.maxBounds - asset.boundingBox.minBounds
// per MDLObject: localScale = column norms of transform.matrix,
//                globalScale = column norms of MDLTransform.globalTransform(with:atTime: 0)
// per MDLMesh:   mesh.boundingBox (mesh-local) vs the stage bbox
// per MDLSkeleton: jointBindTransforms/jointRestTransforms column norms
```

Findings: CGTrader all-identity; Sketchfab F-22 `Meshes` node scale 5.7816 (+90° axis swap);
Sketchfab F-35 `Meshes` node scale 15.0306 with internal 3.5533 × 0.2814 cancelling chains;
all skeleton bind/rest scales 1.0.

## Appendix B — draw-space simulation used to validate the fix (§2.5 output)

Saved during the session at `scratchpad/verify_fix.swift`. It reimplements
`decomposeTRS` → `scaleStrippedTransform` → 8-corner union → `GetLengthAxisExtent` exactly as
proposed in §5, runs it on the three USDZs, and prints the §2.5 table (CGTrader 1.0000×,
F-22 ×5.7816 → 18.92 m, F-35 ×15.0306 → 15.67 m).
