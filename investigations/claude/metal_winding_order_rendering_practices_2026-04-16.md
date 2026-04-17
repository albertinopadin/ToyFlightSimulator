# Metal Triangle Winding Order: Rendering Practices and the F22 Mystery

**Date:** 2026-04-16
**Scope:** Where to set `setFrontFacing` / `setCullMode` in a Metal renderer that loads mixed-format third-party assets, and a focused investigation into the Sketchfab F-22 culling regression in this codebase.
**Engine:** ToyFlightSimulator (macOS / iOS / tvOS, six render paths, deferred + tiled deferred)

---

## TL;DR

1. **`MTLWinding` is encoder state, not pipeline state.** It is cheap to change relative to `setRenderPipelineState`, but not free. The lowest-overhead architecture is to **normalize at load time** so a single global `setFrontFacing(.clockwise)` covers every draw. Per-draw winding flips are a valid backup if normalization is impractical.
2. **There is no single `MDLAsset` "winding" property** (the prior codex investigation already established this). The two practical sources of truth are: (a) the geometric normal-vs-stored-normal test on a few triangles per submesh at load time, and (b) the determinant of the cumulative model transform at draw time.
3. **For the F-22 specifically** the most likely cause is that the new `transformYMinusZXToXYZ` basis transform (commit `7eef4b4`, determinant ≈ −1) was assumed to convert a right-handed CCW asset into a left-handed CW asset, but the asset's actual authored winding/handedness in `MDLMesh` after Model I/O import is not what the comment in the commit message claims. Either the source is already LH (so the flip over-corrects), or per-submesh winding is mixed. The empirical evidence the user reports (`.clockwise + .back` shows interior, `.counterClockwise + .back` is mostly black, `.none` looks correct) is a textbook **inverted-winding** fingerprint, not a missing-vertex or shader bug.
4. **Recommendation for this engine:** add a per-`Mesh` (and optionally per-`Submesh`) `frontFacingWinding: MTLWinding` field that is computed at load time from a normal-vs-cross-product test, then passed to `renderEncoder.setFrontFacing(_:)` at draw time. Keep `cullMode = .back`. This is small, surgical, and matches how production engines that don't fully reindex on import handle the problem.

The rest of the document explains why, with code, citations, and the specific evidence in this codebase.

---

## Part 1 — F-22 Investigation (this codebase)

### Loading chain for `Sketchfab_F22`

1. `ToyFlightSimulator Shared/GameObjects/F22.swift:22` — passes `modelType: .Sketchfab_F22` to the `Aircraft` superclass.
2. `ToyFlightSimulator Shared/AssetPipeline/Libraries/Models/ModelLibrary.swift:86-87` — registers the model as
   ```swift
   _library.updateValue(UsdModel("F-22_Raptor",
                                 basisTransform: Transform.transformYMinusZXToXYZ),
                        forKey: .Sketchfab_F22)
   ```
3. `ToyFlightSimulator Shared/Math/Transform.swift:156-161` — `transformYMinusZXToXYZ`:
   ```swift
   static let transformYMinusZXToXYZ = float4x4(
       float4(0, 1, 0, 0),
       float4(0, 0, -1, 0),
       float4(1, 0, 0, 0),
       float4(0, 0, 0, 1)
   )
   ```
   The upper-left 3×3 determinant is **−1** (axis permutation with one negation), so it is an *orientation-reversing* transform. The user's recent commit message for `7eef4b4` explicitly says this was intentional: "det=-1 correctly converts RH model to LH engine, flipping CCW winding to CW matching Metal default."
4. `ToyFlightSimulator Shared/AssetPipeline/Mesh.swift:62-64` then `:125-135` — applies the transform by mutating vertex positions, normals, tangents, bitangents in place. **It does not touch the index buffer.** So winding in object space (the order indices reference vertices in) is unchanged; what changes is where those vertices land in space, which transforms the screen-space winding of every triangle.

### Comparison with sibling assets

| Asset | Source | Basis transform | Determinant | Status |
|---|---|---|---|---|
| `F16` (`f16r.obj`) | OBJ | none | +1 | works |
| `F18` (`FA-18F.obj`) | OBJ | 180° rotation about Y | +1 | works |
| `Sketchfab_F35` (`F-35A_Lightning_II.usdz`) | USDZ | **none** | n/a | works |
| `CGTrader_F22` (`cgtrader_F22.usdz`) | USDZ | `transformXMinusZYToXYZ` | −1 | not actively rendered, but loaded |
| `Sketchfab_F22` (`F-22_Raptor.usdz`) | USDZ | `transformYMinusZXToXYZ` | **−1** | **broken** |

The two USDZ assets with det=−1 transforms are precisely the ones that would invert screen-space winding relative to their authored order. F35 (the closest comparable Sketchfab USDZ) loads without any basis transform and renders fine, which is consistent with "Sketchfab USDZ exports are not all the same handedness."

### What the symptoms mean

The user observes:

| Front facing | Cull mode | Result |
|---|---|---|
| `.clockwise` | `.back` | top panels invisible, can see inside |
| `.counterClockwise` | `.back` | mostly black |
| any | `.none` | correct |

This is the canonical "winding is inverted relative to what the encoder expects" fingerprint. With `.none`, both sides rasterize so winding is moot — that is *also* why `cull none` is not a real fix: it doubles overdraw and breaks anything that relies on backface lighting, ordering, or stencil tricks. "All black" with `.counterClockwise + .back` makes sense too: the *outer* surfaces become "front," but because the asset has interior detail in some submeshes (cockpit, wheel wells, nozzle interiors), and the engine path uses tiled-deferred lighting that dims unlit pixels to near-black, large regions go dark.

The reason this is not as simple as "flip the global front-facing for the whole engine" is the table above: at least three other models render correctly with `.clockwise + .back`. So the choice **must be per-mesh**, not global.

### Notes on adjacent code worth flagging (but not the cause of the visible bug)

`Mesh.swift:130-132` transforms the *direction* vectors (normal, tangent, bitangent) by constructing `float4(dir, 1)` rather than `float4(dir, 0)`:

```swift
pointer.pointee.normal    = simd_mul(float4(pointer.pointee.normal,    1), basisTransform).xyz
pointer.pointee.tangent   = simd_mul(float4(pointer.pointee.tangent,   1), basisTransform).xyz
pointer.pointee.bitangent = simd_mul(float4(pointer.pointee.bitangent, 1), basisTransform).xyz
```

For these particular basis matrices the translation column is `(0,0,0,1)` so the `w=1` does not corrupt the result, and *direction* vectors transformed by an orientation-reversing 3×3 still point the geometrically correct way for the mirrored mesh. So this isn't the visible bug. It would be an issue if a translation or projective component were ever introduced into a basis transform. Worth a follow-up cleanup but not the priority here.

Also note: Metal's culling is determined purely by **projected screen-space signed area**, not by vertex normals. So the normal-handling above doesn't affect culling — only lighting. The interior-visible symptom is a pure index-order-vs-screen-space-winding problem.

---

## Part 2 — How Metal winding actually works

### `setFrontFacing` is encoder state, not pipeline state

`MTLRenderPipelineDescriptor` does not have a `frontFacingWinding` property. Winding is set on the encoder via `MTLRenderCommandEncoder.setFrontFacing(_:)`, alongside `setCullMode(_:)`, `setViewport(_:)`, and `setDepthBias(...)`. (See [MTLRenderCommandEncoder.setFrontFacing(_:)](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setfrontfacing(_:)) and [MTLWinding](https://developer.apple.com/documentation/metal/mtlwinding).) That means:

- You **cannot** bake winding into a PSO the way you bake blending or vertex layout.
- Changing it does **not** trigger PSO swaps.
- It is cheap relative to PSO swaps but it still costs an encoder command and a small amount of CPU.

Apple's Metal Best Practices Guide explicitly groups `setFrontFacing` with the other "lightweight" encoder state changes: [Best Practices: Render Command Encoders](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/RenderCommandEncoders.html). The same guide treats PSO changes as the heavy state and suggests batching by PSO first.

### What "clockwise" and "counter-clockwise" actually mean

Metal's rasterizer determines front-facing by computing the signed area of the triangle *after* the vertex shader and after viewport transform. The sign is interpreted against `MTLWinding`:

- `.clockwise` → triangles whose post-projection vertices are CW on screen are front.
- `.counterClockwise` → CCW on screen is front.

So whether a triangle is "front" depends on **all** of: its index order, the model matrix, the view matrix, the projection matrix's handedness, and the viewport's Y origin. Metal viewport origin is upper-left ([MTLViewport](https://developer.apple.com/documentation/metal/mtlviewport)), which is the opposite of OpenGL's lower-left and is one common source of accidental winding flips when porting code.

This is why "is the asset CW or CCW?" is the wrong framing. The right framing is: **after my full transform chain, do my front faces project as CW or CCW on screen?** That is what the `screenSpaceWinding` helper in the codex investigation actually answers, and it is the only definitive test. The normal-vs-cross-product test answers a slightly weaker question — "is the asset's index order consistent with its stored normals?" — which is usually good enough.

### Determinant parity rule

Composing transforms multiplies determinants. If the cumulative transform from object space to clip space has a **negative determinant**, screen-space winding is the opposite of object-space winding. Mirror operations, an odd number of negative scales, or an axis-flip basis change all produce a negative determinant. This is the same rule [USD spells out for `orientation`](https://openusd.org/release/api/usd_geom_page_front.html): "An odd number of negative scales in the transform from local to world space implicitly flips the orientation."

In this codebase, the basis transform is baked into vertex positions at load time. So at draw time, the model matrix on its own typically has det > 0 (rotation + uniform scale + translation), and the determinant rule does not need to be re-applied per-frame as long as the load-time analysis already accounted for the basis flip. This simplifies things: **detect once at load, store on the mesh, set on the encoder per draw.**

---

## Part 3 — Where to put the state changes

### The four practical architectures

**A. Reindex on import (eager normalization).** Inspect every submesh at load time, and if its post-transform geometric normal disagrees with its stored vertex normals, flip the index order in groups of three. After import, every mesh shares one winding convention and rendering uses a single global `setFrontFacing`.

- Pro: zero per-draw cost, maximum batching.
- Pro: debugger-friendly — every mesh in memory matches what you expect.
- Con: requires writable index storage, recomputed per-vertex normals if you flip anything (otherwise lighting goes wrong on flipped submeshes), and is annoying with `MTKMesh` because index buffers come from MetalKit and you have to either rebuild via `MDLSubmesh` or memcpy in place.
- Con: irrelevant for animated meshes where the skeleton is the source of motion — still correct, but the reindex must happen before MetalKit conversion.

**B. Per-mesh stored winding + per-draw `setFrontFacing` (lazy normalization, my recommendation for this engine).** Detect winding once at load, store an `MTLWinding` on `Mesh` (or `Submesh` if mixed), and call `renderEncoder.setFrontFacing(mesh.frontFacingWinding)` per draw. Keep `cullMode = .back` everywhere except where you genuinely need both sides (sky, transparent foliage, etc.).

- Pro: small, surgical change. No index rewriting. No MetalKit fights.
- Pro: handles per-submesh inconsistencies if you push the field down to `Submesh`.
- Con: extra encoder command per draw — measurable in microbenchmarks, invisible in a flight-sim-scale frame.
- Con: batching by winding helps if you have hundreds of state-change-sensitive draws, but at this engine's scale (per-frame draw counts in the dozens to low hundreds) it doesn't matter.

**C. Per-instance determinant check.** Compute `simd_determinant(modelMatrix.upper3x3)` at draw time and flip winding on negative det. Useful when *instance* transforms can mirror geometry (rare in this engine — there's no negative-scale instancing today).

- Pro: handles mirrored instances cleanly.
- Con: doesn't help with the F-22 problem because that is a *load-time* basis decision, not a per-instance mirror.
- Recommendation: combine with B if you ever introduce mirrored instances.

**D. Render with `cullMode = .none` everywhere.** This is the user's current "it looks correct" workaround.

- Pro: trivial.
- Con: doubles fragment shader invocations on opaque geometry, breaks any backface-rejection assumption in your shaders, makes per-pixel lighting on closed meshes wrong (back faces light as if they were exterior), and is bad for early-Z. Not a real solution.

### Industry comparison

- **Unreal**: normalizes to CCW at FBX/glTF import time, single global front-face setting at the renderer.
- **Unity**: leaves geometry alone, exposes per-material `Cull` settings — effectively per-PSO winding handling. Feasible because Unity rebuilds material PSOs lazily.
- **RealityKit**: USDZ-native, honors USD `orientation`, normalizes internally.
- **Filament (Google)**: load-time normalization step in the asset pipeline, single global front-face.
- **bgfx**: per-draw "state" word that includes front-facing as one bit; cheap because state is hashed.

The pattern across production engines is "normalize at load, single global front-face." Architecture A. The reason to choose B for this codebase is purely pragmatic — you already have `Mesh` and `Submesh` types, no need for an index-rewrite pipeline, and the per-draw state-change cost is irrelevant at your scale.

---

## Part 4 — Recommended approach for ToyFlightSimulator

### Concrete plan (do *not* implement until the user reviews)

1. **Add a `frontFacingWinding: MTLWinding` field to `Submesh`.** Default it to `.clockwise` to match the existing global behavior so unmodified meshes do not change.
2. **At mesh load time, after `transformMeshBasis` runs and after `MTKMesh` submeshes are created, run a normal-vs-cross-product test on a sample of triangles from each submesh.** If the dominant result is "geometric normal opposes stored vertex normals," set the submesh's `frontFacingWinding` to `.counterClockwise`. If it agrees, keep `.clockwise`. If results are mixed (very rare; usually authoring bug), log a warning and pick the majority.
3. **In `DrawManager.DrawFromRingBuffer`, replace the hardcoded line 405 with `renderEncoder.setFrontFacing(submesh.frontFacingWinding)`.** Keep `setCullMode(.back)` as-is. Move both into the inner submesh loop (or hoist them once if every submesh of a mesh shares a winding — use the same field on `Mesh` as a fast-path).
4. **For shadow draws and other passes that already share the path, the same per-submesh winding applies.** Verify by checking that shadow culling stays consistent (a triangle should be back-facing or front-facing from any camera).
5. **Leave the basis transform in `ModelLibrary` alone.** It exists to put the model into the engine's coordinate convention. Reverting it would create a different bug. The fix is to *track* the consequence of the determinant flip, not to undo the flip.

### Quick verification step before any of the above

Before you do any of this, run a one-off probe on the Sketchfab F-22 to confirm the diagnosis. There is already an `analyzeAuthoredWinding` function in the existing codex investigation file that does exactly this. Run it on `Assets.Models[.Sketchfab_F22]`'s underlying `MDLMesh` *after* the basis transform has been applied (or, equivalently, run the cross-product test on the post-transform `Vertex` data this engine already keeps). If the report comes back "opposesNormals" for the F-22's submeshes and "agreesWithNormals" for F-35 / F-18 / F-16, the diagnosis is confirmed and step 2 above will produce the right answer automatically.

### Code sketch for step 2

This is illustrative, not finished — the user asked for no code changes yet:

```swift
import Metal
import simd

extension Submesh {
    /// Sample up to N triangles, compare geometric face normal to averaged stored vertex normals.
    /// Returns `.counterClockwise` if the mesh's index order produces normals that consistently
    /// oppose the stored normals — meaning Metal will treat its "front" faces as back-facing
    /// under the engine's default `.clockwise` setting.
    static func detectFrontFacingWinding(
        vertices: UnsafePointer<Vertex>,
        indices: UnsafePointer<UInt32>,
        triangleCount: Int,
        sampleLimit: Int = 32
    ) -> MTLWinding {
        var aligned = 0
        var opposed = 0
        let sampled = min(triangleCount, sampleLimit)

        for t in 0..<sampled {
            let i0 = Int(indices[t * 3 + 0])
            let i1 = Int(indices[t * 3 + 1])
            let i2 = Int(indices[t * 3 + 2])

            let p0 = vertices[i0].position
            let p1 = vertices[i1].position
            let p2 = vertices[i2].position
            let geo = simd_cross(p1 - p0, p2 - p0)
            if simd_length(geo) < 1e-7 { continue }

            let avgNormal = vertices[i0].normal + vertices[i1].normal + vertices[i2].normal
            if simd_length(avgNormal) < 1e-7 { continue }

            let d = simd_dot(simd_normalize(geo), simd_normalize(avgNormal))
            if d > 0.1 { aligned += 1 }
            else if d < -0.1 { opposed += 1 }
        }

        // If we transformed positions with a det<0 basis but kept the same index order,
        // the geometric normal (cross product) also flipped. The stored vertex normals
        // were *also* transformed by the same basis (Mesh.swift:130-132), so they
        // *also* flipped. The two flips cancel — which means the agree/oppose vote here
        // tells us about the *original asset's* winding-vs-normals consistency, not
        // about the post-transform screen-space winding. To recover the latter, also
        // factor in the basis determinant if positions and normals were transformed
        // by the same matrix (current behavior in this engine).
        let assetAligned = aligned >= opposed
        let basisFlipped = false  // pass in: simd_determinant(basis3x3) < 0
        let needsCounterCW = assetAligned == basisFlipped
        return needsCounterCW ? .counterClockwise : .clockwise
    }
}
```

The comment in the middle of that sketch is the subtle part that the second of my two research agents and I both want to flag for the user: **because this engine's `transformMeshBasis` applies the same matrix to both positions and normals, the cross-product-vs-stored-normal test alone may not detect the basis flip.** The cross product flips with positions; the stored normals also flip; the dot product is sign-preserved. So the right detection at load time is either:

- Run the test on the *raw* `MDLMesh` data **before** `transformMeshBasis` is applied, and combine with `simd_determinant(basis3x3) < 0`, **or**
- Run the screen-space test from the codex investigation under a known camera, which always tells the truth.

This is the kind of subtle thing that is easy to get wrong on the first try, which is why I want the user to look at it before we touch code.

### Why not pure normalize-on-load (option A)?

For this engine specifically:

- You use `MTKMesh` for vertex buffers, which gives you Metal-side index buffers tied to vertex layouts via the MetalKit conversion. Reindexing in place is doable but more code than option B.
- You have animated meshes (F35) where the skeleton drives matrices. Reindexing has to happen before joint-influenced rendering, which complicates the load order.
- You're at draw counts where one extra `setFrontFacing` per submesh costs nothing measurable.
- Option B keeps the existing pipeline shape — same PSOs, same batching, same `DrawFromRingBuffer` structure.

If the engine grows to thousands of meshes per frame later, revisit option A.

### What about `setCullMode`?

Don't change it per draw for the F-22 problem; the issue is winding, not culling. Keep `.back` for opaque geometry. Use `.none` only for genuinely two-sided geometry (sky, foliage if you ever add it, transparent panels), which is already the right policy in any renderer.

---

## Part 5 — Open questions worth answering empirically

1. **Is the F-22's submesh winding consistent or mixed?** Run the load-time probe on each submesh independently. If mixed, push the field down to `Submesh`; if uniform, `Mesh` is enough.
2. **Does `MTKMesh(mesh: mdlMesh, device:)` reorder indices for hardware-friendly cache locality, and does that reordering preserve triangle winding?** It *should* — the documented behavior is per-triangle reordering for vertex cache, not per-vertex-within-triangle reordering. But verify by running the probe both pre- and post-MetalKit conversion if results disagree.
3. **Does the new commit `7eef4b4` MVP/projection have a flip the codebase isn't accounting for?** The commit title is "Switch rendering pipeline to left-handed Metal-native coordinate conventions" — if the projection matrix is now LH but the basis transforms were calibrated against an old RH projection, the assumption "det=−1 basis flips CCW asset to CW for Metal default" may be wrong by a global sign. Worth checking the projection matrix construction in the same commit.
4. **Does the `Mesh.swift:130-132` direction-vector `w=1` issue ever bite?** Not for current basis transforms, but write a unit test that catches it before someone introduces a translated basis.

These are all probes, not code changes. The user explicitly asked for no code modifications until they've reviewed the recommendation.

---

## Sources

### Apple — Metal

- [MTLRenderCommandEncoder.setFrontFacing(_:)](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setfrontfacing(_:))
- [MTLRenderCommandEncoder.setCullMode(_:)](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setcullmode(_:))
- [MTLWinding](https://developer.apple.com/documentation/metal/mtlwinding)
- [MTLCullMode](https://developer.apple.com/documentation/metal/mtlcullmode)
- [MTLViewport](https://developer.apple.com/documentation/metal/mtlviewport)
- [MTLRenderPipelineDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor)
- [Metal Best Practices Guide — Render Command Encoders](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/RenderCommandEncoders.html)
- [Metal Best Practices Guide — Pipelines](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Pipelines.html)
- [Metal Programming Guide — Render Command Encoder](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Render-Ctx/Render-Ctx.html)
- WWDC 2023 — [Optimize GPU renderers with Metal](https://developer.apple.com/videos/play/wwdc2023/10127/)
- WWDC 2020 — [Optimize Metal performance for Apple silicon Macs](https://developer.apple.com/videos/play/wwdc2020/10632/)
- WWDC 2019 — [Modern Rendering with Metal](https://developer.apple.com/videos/play/wwdc2019/601/)
- WWDC 2016 — [Advanced Metal Shader Optimization](https://developer.apple.com/videos/play/wwdc2016/606/)

### Apple — Model I/O

- [Model I/O](https://developer.apple.com/documentation/modelio)
- [MDLMesh](https://developer.apple.com/documentation/modelio/mdlmesh)
- [MDLSubmesh](https://developer.apple.com/documentation/modelio/mdlsubmesh)
- [MDLGeometryType](https://developer.apple.com/documentation/modelio/mdlgeometrytype)
- [MTKMesh.init(mesh:device:)](https://developer.apple.com/documentation/metalkit/mtkmesh/init(mesh:device:))
- WWDC 2015 — [Managing 3D Assets with Model I/O](https://developer.apple.com/videos/play/wwdc2015/602/)

### Universal Scene Description

- [UsdGeom: Coordinate System, Winding Order, Orientation, and Surface Normals](https://openusd.org/release/api/usd_geom_page_front.html)
- [UsdGeomGprim Class Reference](https://openusd.org/docs/api/class_usd_geom_gprim.html)
- [USDZ File Format Specification](https://openusd.org/release/spec_usdz.html)

### Tutorials and community references

- Metal by Example — [Up and Running, Part 3: Lighting and Rendering in 3D](https://metalbyexample.com/up-and-running-3/)
- Kodeco — [Metal by Tutorials, Chapter 3: The Rendering Pipeline](https://www.kodeco.com/books/metal-by-tutorials/v2.0/chapters/3-the-rendering-pipeline)
- Kodeco Forums — [Winding order for clarity](https://forums.kodeco.com/t/winding-order-for-clarity/164492)
- The Hacks of Life — [Keeping the Blue Side Up: Coordinate Conventions for OpenGL, Metal and Vulkan](http://hacksoflife.blogspot.com/2019/04/keeping-blue-side-up-coordinate.html)
- Real-Time Rendering — [Left-Handed vs. Right-Handed Viewing](https://www.realtimerendering.com/blog/left-handed-vs-right-handed-viewing/)
- LearnOpenGL — [Face Culling](https://learnopengl.com/Advanced-OpenGL/Face-Culling)
- Scratchapixel — [Coordinate Systems](https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/coordinate-systems.html)
- cmichel.io — [Understanding front faces — winding order and normals](https://cmichel.io/understanding-front-faces-winding-order-and-normals)
- crimild — [Praise the Metal, Part 4: Render Encoders and the Draw Call](https://crimild.wordpress.com/2016/05/30/praise-the-metal-part-4-render-encoders-and-the-draw-call/)

### Other engines and formats

- glTF 2.0 — [Khronos Specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
- Khronos glTF Issue #2252 — [Is front-facing positive or negative determinant?](https://github.com/KhronosGroup/glTF/issues/2252)
- glTF Blender IO Issue #551 — [Winding order is inverted](https://github.com/KhronosGroup/glTF-Blender-IO/issues/551)
- Microsoft DirectXMesh — [Wiki](https://github.com/microsoft/DirectXMesh/wiki/DirectXMesh)
- Unreal Forums — [Getting the vertex winding order per bone of a skeletal mesh](https://forums.unrealengine.com/t/getting-vertex-winding-order-per-bone-of-a-skeletal-mesh/1341488)
- Sketchfab Forum — [Model orbit / rotation problems](https://forum.sketchfab.com/t/model-orbit-rotation-problems/4721)

### In-repo prior work

- `investigations/codex/metal_modelio_triangle_winding_research_2026-04-16.md` — prior Model I/O introspection research and the `analyzeAuthoredWinding` / `screenSpaceWinding` helpers reused above.
