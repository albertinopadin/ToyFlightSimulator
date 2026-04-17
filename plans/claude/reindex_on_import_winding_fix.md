# Plan — Option A: Reindex On Import (Eager Winding Normalization)

**Date:** 2026-04-16
**Companion docs:**
- `investigations/claude/metal_winding_order_rendering_practices_2026-04-16.md` (full architectural analysis)
- `investigations/codex/metal_modelio_triangle_winding_research_2026-04-16.md` (Model I/O introspection background)
- `scripts/inspect_winding.swift` (the probe used to gather the evidence below)

**Status:** DRAFT — awaiting user review before any code change.

---

## 1. Goal

Make every loaded mesh present a single, uniform triangle winding to the GPU so that `DrawManager` can keep the existing global `setFrontFacing(.clockwise)` + `setCullMode(.back)` and have it render every model correctly. We will do this by **detecting at load time whether the basis transform inverts winding, and, if so, reversing the per-triangle index order** in place after `transformMeshBasis` runs.

This is the "Option A" alternative described in the research doc: normalize on import, single global render state, zero per-frame winding overhead.

---

## 2. Empirical evidence (from `scripts/inspect_winding.swift`)

Ran the probe against the engine's four currently-rendered aircraft. Format: `aligned` = triangles whose `cross(p1-p0, p2-p0)` points the same way as the averaged stored vertex normal; `opposed` = points the opposite way.

### Sketchfab F-22 (the failing model)

Basis applied: `transformYMinusZXToXYZ`, 3×3 determinant **= −1**. Every mesh:

| State | Verdict |
|---|---|
| RAW (asset as authored) | `agreesWithNormals` for **all 8 meshes** |
| POST-XFRM (after engine basis applied) | `opposesNormals` for **all 8 meshes** |

The asset is authored cleanly. The engine's basis transform mirrors positions and normals together, which leaves the agreement test in a flipped state — and, more importantly, leaves screen-space winding inverted relative to what Metal's `.clockwise` setting expects. **This is the smoking gun for the F-22 rendering bug.**

### Sketchfab F-35 (works in current build)

Basis applied: none (det = +1). Mixed picture:

- 14 of 19 meshes: `agreesWithNormals`
- 5 of 19 meshes (`Object_18`, `Object_10`, `Object_12`, `Object_13`, `Object_14`): `opposesNormals` in the raw asset

Despite the mixed agreement, the F-35 renders correctly today under `.clockwise + .back`. This proves an important point: **the agreement test is a quality probe of asset authoring, not a direct predictor of "what `setFrontFacing` value Metal needs."** The "opposes" submeshes are most likely interior geometry (cockpit, intakes, gear bays) authored with intentionally-inverted normals. They render correctly because Metal's culling decision is based on screen-space signed area, not on stored normals.

The implication is critical for designing this fix: **we must not blindly reindex submeshes based on an agreement-test verdict** — that would break F-35-style intentionally-inverted surfaces. The decision rule has to come from somewhere else.

### F-18 (works in current build)

Basis applied: 180° rotation about Y (det = +1). Every one of 94 submeshes: `agreesWithNormals` both raw and post-transform. The det=+1 transform doesn't change agreement, as expected.

### F-16 (works in current build)

Basis applied: none. Both submeshes `agreesWithNormals`.

### What this tells us

| Asset | Basis det | Raw verdict | Post-xfrm verdict | Renders OK? |
|---|---|---|---|---|
| F-22 (Sketchfab) | **−1** | agrees | **opposes** | **NO** |
| F-35 (Sketchfab) | +1 | mixed (mostly agrees) | mixed (mostly agrees) | yes |
| F-18 | +1 | agrees | agrees | yes |
| F-16 | +1 | agrees | agrees | yes |

The single common factor among working assets is **basis determinant ≥ 0**. The single failing asset has **basis determinant < 0**. This gives us a clean, mechanical decision rule that does not require per-submesh inspection.

---

## 3. Decision rule

> **After `transformMeshBasis` runs, compute `simd_determinant(basis3x3)`. If it is negative, reverse every triangle's index order in every submesh of that mesh. Otherwise do nothing.**

Why this works:

- A det=−1 basis mirrors positions (and, in the engine's current code, normals/tangents/bitangents the same way). Mirroring a triangle's vertex positions is what flips its screen-space winding.
- Reversing index order `(i0, i1, i2) → (i0, i2, i1)` flips screen-space winding back. The two mirrors compose into a rotation: net visual orientation is preserved, but the engine's `.clockwise` expectation is now satisfied.
- The rule does not touch det=+1 assets, so F-35's intentionally-inverted interior submeshes remain intentionally inverted.
- The rule is mechanical and decoupled from asset authoring quality. No agreement-vote heuristics, no per-submesh detection needed.

What the rule explicitly does **not** try to fix:

- Assets with no basis transform that are nonetheless authored "wrong winding for this engine" (we have no such asset today; if one shows up, it would need its own basis transform or a per-mesh override).
- Per-submesh winding inconsistencies within a single mesh (none observed — every aircraft tested is uniform within a mesh).
- Tangent/bitangent handedness consequences — see §6.

---

## 4. Code changes

All changes are in `ToyFlightSimulator Shared/AssetPipeline/Mesh.swift`. No other file is modified by this plan.

### 4a. Modify `transformMeshBasis` to also reindex when basis is orientation-reversing

#### BEFORE — `Mesh.swift:62-64` (caller) and `Mesh.swift:125-135` (the function)

```swift
//   Mesh.swift:62-64  — inside the designated initializer, after vertex buffer is set
        if let basisTransform {
            transformMeshBasis(basisTransform)
        }
```

```swift
//   Mesh.swift:125-135  — the existing function definition
    private func transformMeshBasis(_ basisTransform: float4x4) {
        let count = vertexBuffer.length / Vertex.stride
        var pointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: count)
        for _ in 0..<count {
            pointer.pointee.position = simd_mul(float4(pointer.pointee.position, 1), basisTransform).xyz
            pointer.pointee.normal = simd_mul(float4(pointer.pointee.normal, 1), basisTransform).xyz
            pointer.pointee.tangent = simd_mul(float4(pointer.pointee.tangent, 1), basisTransform).xyz
            pointer.pointee.bitangent = simd_mul(float4(pointer.pointee.bitangent, 1), basisTransform).xyz
            pointer = pointer.advanced(by: 1)
        }
    }
```

#### AFTER — caller unchanged, function gains a determinant check + post-call reindex hop

The caller (`Mesh.swift:62-64`) is unchanged. The function body changes, and one new private helper `reverseTriangleWindingIfNeeded` is added below it. The submeshes haven't been built yet at the call site (lines 67-73 in the existing file build them *after* `transformMeshBasis`), so the reindex has to run *after* submesh construction. We move the orientation handling into a small helper that is called from a new spot at the very end of the initializer, right after `addSubmesh` calls.

**Step 1.** Annotate the existing function so it returns whether the basis flipped orientation, so callers don't have to recompute the determinant:

```swift
    /// Apply `basisTransform` to every vertex's position, normal, tangent, bitangent.
    /// Returns `true` if the basis is orientation-reversing (3x3 determinant < 0), in
    /// which case callers should also reverse triangle index order via
    /// `reverseTriangleWinding()` *after* submeshes have been constructed.
    @discardableResult
    private func transformMeshBasis(_ basisTransform: float4x4) -> Bool {
        let count = vertexBuffer.length / Vertex.stride
        var pointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: count)
        for _ in 0..<count {
            pointer.pointee.position  = simd_mul(float4(pointer.pointee.position,  1), basisTransform).xyz
            pointer.pointee.normal    = simd_mul(float4(pointer.pointee.normal,    1), basisTransform).xyz
            pointer.pointee.tangent   = simd_mul(float4(pointer.pointee.tangent,   1), basisTransform).xyz
            pointer.pointee.bitangent = simd_mul(float4(pointer.pointee.bitangent, 1), basisTransform).xyz
            pointer = pointer.advanced(by: 1)
        }

        let m = basisTransform
        let det = simd_determinant(simd_float3x3(
            SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        ))
        return det < 0
    }
```

**Step 2.** Add the new index-reversal helper:

```swift
    /// Reverse the per-triangle index order in every submesh so that screen-space
    /// winding flips. Called after `transformMeshBasis` when the basis matrix has
    /// a negative determinant — that mirror flips screen-space winding, and this
    /// reversal puts it back in agreement with the engine's global
    /// `setFrontFacing(.clockwise)`.
    private func reverseTriangleWinding() {
        for submesh in submeshes {
            guard submesh.primitiveType == .triangle else {
                print("[Mesh reverseTriangleWinding] Skipping submesh '\(submesh.name)' "
                    + "with non-triangle primitiveType=\(submesh.primitiveType.rawValue) "
                    + "in mesh '\(name)'. Triangle strips/fans not handled here.")
                continue
            }

            let buffer = submesh.indexBuffer
            let offset = submesh.indexBufferOffset
            let count  = submesh.indexCount
            let triangleCount = count / 3
            guard triangleCount > 0 else { continue }

            switch submesh.indexType {
            case .uint16:
                let p = (buffer.contents() + offset).bindMemory(to: UInt16.self, capacity: count)
                for t in 0..<triangleCount {
                    let base = t * 3
                    let tmp = p[base + 1]
                    p[base + 1] = p[base + 2]
                    p[base + 2] = tmp
                }

            case .uint32:
                let p = (buffer.contents() + offset).bindMemory(to: UInt32.self, capacity: count)
                for t in 0..<triangleCount {
                    let base = t * 3
                    let tmp = p[base + 1]
                    p[base + 1] = p[base + 2]
                    p[base + 2] = tmp
                }

            @unknown default:
                print("[Mesh reverseTriangleWinding] Unknown indexType=\(submesh.indexType.rawValue) "
                    + "in submesh '\(submesh.name)'; cannot reverse winding.")
                continue
            }

            #if os(macOS)
            // MTKMeshBufferAllocator returns shared-storage buffers on iOS/Apple Silicon Macs,
            // but managed buffers can show up on Intel discrete GPUs. didModifyRange is a
            // no-op on shared buffers and required on managed ones.
            if buffer.storageMode == .managed {
                buffer.didModifyRange(offset..<(offset + count * stride(forIndexType: submesh.indexType)))
            }
            #endif
        }
    }

    /// Bytes per index for didModifyRange computations.
    private func stride(forIndexType type: MTLIndexType) -> Int {
        switch type {
        case .uint16: return 2
        case .uint32: return 4
        @unknown default: return 4
        }
    }
```

**Step 3.** Wire the two together at the end of the designated initializer. Replace the existing block at `Mesh.swift:62-73`:

##### BEFORE

```swift
        self.vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        if let basisTransform {
            transformMeshBasis(basisTransform)
        }

        self._vertexCount = mtkMesh.vertexCount
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            let submesh = Submesh(mtkSubmesh: mtkSubmesh,
                                  mdlSubmesh: mdlSubmesh)
            addSubmesh(submesh)
        }
```

##### AFTER

```swift
        self.vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        let basisFlipsOrientation: Bool = {
            if let basisTransform {
                return transformMeshBasis(basisTransform)
            }
            return false
        }()

        self._vertexCount = mtkMesh.vertexCount
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            let submesh = Submesh(mtkSubmesh: mtkSubmesh,
                                  mdlSubmesh: mdlSubmesh)
            addSubmesh(submesh)
        }

        if basisFlipsOrientation {
            print("[Mesh init] basis transform has det<0 for mesh '\(mdlMesh.name)'; "
                + "reversing triangle winding in \(mtkMesh.submeshes.count) submeshes "
                + "to compensate.")
            reverseTriangleWinding()
        }
```

That is the entire functional change. `DrawManager.swift:405-406` keeps its existing `setFrontFacing(.clockwise)` + `setCullMode(.back)` calls unchanged.

### 4b. (Optional) Tighten the `w` component when transforming direction vectors

While we're in `transformMeshBasis`, the existing code passes `w=1` when transforming `normal`, `tangent`, `bitangent`. This is mathematically wrong for direction vectors (they should pass `w=0` so translation doesn't apply). For all current basis transforms in `Transform.swift` the translation column is `(0,0,0,1)` so the bug is dormant — but it is a footgun the moment anyone introduces a translated basis.

This is *not required* to fix the F-22, and it is not strictly part of Option A. I am calling it out only so you can decide whether to bundle it in or split it. Recommendation: split into a separate small commit so the F-22 fix has a clean blast radius.

#### BEFORE

```swift
            pointer.pointee.normal    = simd_mul(float4(pointer.pointee.normal,    1), basisTransform).xyz
            pointer.pointee.tangent   = simd_mul(float4(pointer.pointee.tangent,   1), basisTransform).xyz
            pointer.pointee.bitangent = simd_mul(float4(pointer.pointee.bitangent, 1), basisTransform).xyz
```

#### AFTER

```swift
            pointer.pointee.normal    = simd_mul(float4(pointer.pointee.normal,    0), basisTransform).xyz
            pointer.pointee.tangent   = simd_mul(float4(pointer.pointee.tangent,   0), basisTransform).xyz
            pointer.pointee.bitangent = simd_mul(float4(pointer.pointee.bitangent, 0), basisTransform).xyz
```

### 4c. No changes needed elsewhere

`DrawManager.swift`, `Submesh.swift`, `ModelLibrary.swift`, `UsdModel.swift`, `ObjModel.swift`, `Material.swift`, the renderers, and the shaders all stay identical. This is the architectural payoff of normalizing at load time: no per-frame plumbing.

---

## 5. Why we do not also need to reindex per submesh based on the agreement test

This was my first instinct after the probe results, but the F-35 evidence killed it. The F-35 has 5 submeshes that report `opposesNormals` in raw form, *and renders correctly today*. Any per-submesh "if `opposesNormals` then reindex" rule would silently break those submeshes (they'd become invisible under `.clockwise + .back`).

The agreement test is the right tool for diagnosing authoring quality, but the wrong tool for driving an automatic reindex. The basis-determinant rule is mechanical, decoupled from authoring quality, and matches the empirical evidence — every working aircraft has det ≥ 0; the failing one has det < 0.

---

## 6. Edge cases and explicit non-goals

### 6a. Triangle strips and fans

The new helper logs and skips any submesh whose `primitiveType` is not `.triangle`. Looking at the probe output, every submesh in every aircraft has `geometryType` = `triangles` (raw value 2). So this is not a problem today. Should a strip-based asset arrive later, the helper will warn loudly rather than silently corrupt indices.

### 6b. Index-buffer storage mode

`MTKMeshBufferAllocator` returns shared-storage buffers on iOS and Apple Silicon Macs (the engine's primary targets). On an Intel discrete GPU you can sometimes get managed buffers, in which case `didModifyRange` is required after a CPU write. The helper handles both. (We could just always call it on macOS — `didModifyRange` is a no-op on shared buffers.)

### 6c. Buffers shared across submeshes

A single `MTLBuffer` can hold the index ranges of multiple submeshes at different offsets (MetalKit packs them this way for some assets). The helper iterates submeshes and writes only the `[offset, offset + count*stride)` range belonging to each, so multiple submeshes with disjoint ranges in one buffer work correctly. The pathological case is two submeshes with *overlapping* ranges in one buffer — that would double-flip the overlap. Model I/O does not produce that today; the helper would need a "ranges seen" set to be paranoid about it. **Not added in this plan; we'll add it if we ever encounter such an asset.**

### 6d. Tangent-space handedness for normal mapping

Reversing index order changes the tangent-space handedness of triangles. For meshes that use normal maps (current code reads tangents and bitangents per vertex), this *can* introduce shading artifacts on the affected meshes. Two reasons we expect this to be a non-issue for the F-22 specifically:

1. The basis transform already mirrored T and B together with N. Re-flipping the triangle order doesn't undo that — it just changes which vertex of each triangle is "first" — and the per-vertex T/B/N are unchanged.
2. The visible bug we are fixing is the binary "outside vs inside is rendered" one. Subtle normal-map artifacts, if they exist, are a second-order concern that we should evaluate visually after the fix lands.

If we later see normal-map shading wrong on the F-22 only, the fix is to negate `bitangent` per vertex on flipped meshes (or equivalently, recompute tangents from the post-reindex positions/normals/UVs). I'd rather measure first than preemptively complicate the change.

### 6e. Skinned meshes

The F-35 uses a skin (`Mesh.skin`, `Skeleton`, `Skin.updatePalette`). Skinning operates on vertices, not on indices, so the reindex helper is independent of skinning. The F-35 has det=+1 basis, so `reverseTriangleWinding()` will not even be called for it. This stays out of skinning's way.

### 6f. Animated transforms

`mesh.transform?.currentTransform` is applied per-frame in the vertex shader (not at load). Reindexing is a one-shot CPU operation that does not interact with the per-frame animation pipeline.

### 6g. Shadow rendering

`DrawManager.DrawShadows` uses the same submesh index buffers as the main pass. Since the reindex happens once at load and is reflected in the GPU buffer for both passes, shadows automatically inherit the fix.

### 6h. `Submesh` field visibility

The helper reaches `submesh.indexBuffer`, `submesh.indexBufferOffset`, `submesh.indexCount`, `submesh.indexType`, `submesh.primitiveType`, `submesh.name` — all already exposed via `public` getters in `Submesh.swift`. No visibility changes are required there.

---

## 7. Verification plan

Before merging:

1. **Build & smoke test on macOS.** Launch the default scene with the F-22, confirm visually that the top panels are now visible and the model looks like an F-22 from outside. Compare against the existing `debugging/screenshots/CullNone.png` reference.
2. **Verify F-35 still renders correctly.** This is the regression-risk asset, since it has mixed-agreement submeshes that we intentionally chose *not* to touch. Look for unchanged appearance vs. current build.
3. **Verify F-18 still renders correctly.** Sanity check on the OBJ + det=+1 path.
4. **Run the probe again on the post-fix data path.** This requires either re-running the in-app load or a follow-up probe variant that calls the new code. If we want a stricter check, we can add a debug print right after `reverseTriangleWinding` runs that re-asserts agreement for the F-22 and warns otherwise.
5. **Take a new screenshot of the F-22** with `.clockwise + .back` (the engine's default) and save under `debugging/screenshots/F22_AfterReindex.png` for posterity.
6. **GPU frame capture spot-check** in Xcode for the F-22 frame: confirm that triangle counts are unchanged (no triangles dropped) and that the depth buffer shows the outer skin in front of interior detail.

Failure modes to watch for:

- F-35 turns "inside out" → I would have been wrong about the determinant rule being safe; revert and switch to per-mesh override.
- F-22 normal-mapped shading looks subtly wrong (lighting darker on one side of panels) → 6d kicks in; add bitangent negation pass.
- iOS / iPad build fails because `didModifyRange` was called on a non-managed buffer → wrap in `#if os(macOS)` (already done above) or in `if buffer.storageMode == .managed`.

---

## 8. Rollback

The change is contained to a single file (`Mesh.swift`) and is functionally a no-op for any mesh whose basis transform has det ≥ 0. Reverting is a single commit. There is no migration, no persistent state, no asset format change, no API shift visible to game code.

---

## 9. Out of scope (deliberately)

- Any change to `DrawManager.swift`. The hardcoded `setFrontFacing(.clockwise)` + `setCullMode(.back)` are correct under this fix; they stay.
- Any change to `Submesh.swift` (no new fields).
- Any per-submesh override mechanism. The empirical evidence does not justify one yet.
- Tangent-handedness rebuild. Defer until visible normal-map artifacts appear.
- The `w=1` direction-vector bug in `transformMeshBasis` (4b above) — split into a separate commit if you want to tackle it.
- The `w=1` issue in `Skeleton`/`Skin` if it exists there — entirely separate concern.
- A more aggressive "detect winding empirically by screen-space projection at load time" approach. The determinant rule is simpler and matches all observed evidence; revisit only if a future asset breaks it.

---

## 10. Open questions for the user before implementing

1. Bundle the optional `w=1 → w=0` fix from §4b in this same PR, or split it?
2. Are you OK with the helper logging on every load (per-mesh `print` for det<0 cases), or do you want it gated behind a debug flag?
3. Any preference for where to put the helper if you don't want it on `Mesh` (e.g., a free function in a `WindingNormalization.swift`)? I have it on `Mesh` because it needs private access to `submeshes`, but a free function taking `[Submesh]` would also work.

---

## 11. Summary of the change

- **One file modified:** `ToyFlightSimulator Shared/AssetPipeline/Mesh.swift`
- **One method modified:** `transformMeshBasis` (now returns `Bool`)
- **One method added:** `reverseTriangleWinding`
- **One private helper added:** `stride(forIndexType:)`
- **One call site changed:** the designated initializer of `Mesh`, after submeshes are constructed
- **Net effect:** F-22 renders correctly under the existing global `setFrontFacing(.clockwise) + setCullMode(.back)`; every other model is untouched; per-frame rendering cost is unchanged.
