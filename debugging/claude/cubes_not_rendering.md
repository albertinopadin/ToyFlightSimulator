# Cubes Not Rendering — Investigation

Symptom: `Cube` GameObjects added to a scene (e.g. the `testCube` in `FlightboxScene.swift:169` and the random cubes spawned by `FlightboxWithPhysics.makeRandomDispersedObjects()` at `FlightboxWithPhysics.swift:46-51`) are never drawn. Sphere/Capsule/Quad spawned in the same loop render fine, so the issue is specific to cubes (and, as a corollary, to anything else going through the programmatic mesh path).

## Root cause — `CubeMesh` has 36 vertices but **zero submeshes**, and the modern draw path only walks submeshes

### The mesh

`AssetPipeline/Libraries/Meshes/ProgrammaticMeshes.swift:42-205` defines `CubeMesh` as:

```swift
class CubeMesh: Mesh {
    override func createMesh() {
        // 36 addVertex(...) calls — 6 faces × 6 verts/face, triangle list
        // ...
        // (commented out)
        // addSubmesh(Submesh(indices: [0,1,2, 0,2,3]))
        // ...
    }
}
```

`Mesh.init()` (`AssetPipeline/Mesh.swift:29-32`) just calls `createMesh()` then `createBuffer()`. `createMesh()` populates `_vertices` (and `createBuffer` builds `vertexBuffer` from it), but `submeshes` stays empty for `CubeMesh` — nothing inside `createMesh()` calls `addSubmesh(...)`. Compare to `QuadMesh` at line 35-38 in the same file, which **does** append a submesh with indices `[0,1,2, 0,2,3]` after its 4 `addVertex` calls.

### The wiring

`ModelLibrary.swift:65` wires `ModelType.Cube` to that mesh:
```swift
_library.updateValue(Model(name: "Cube", mesh: CubeMesh()), forKey: .Cube)
```

`Cube.swift:8-12`:
```swift
class Cube: GameObject {
    init() {
        super.init(name: "Cube", modelType: .Cube)
    }
}
```

So every `Cube()` shares the single `CubeMesh` instance, which has `submeshes == []`.

### Why that kills rendering today

1. **Registration drops the cube on the floor.** When a `Cube` is added to the scene, `SceneManager.RegisterObject` → `SceneManager.CreateModelData` (`Managers/SceneManager.swift:305-325`) does:
   ```swift
   for mesh in gameObject.model.meshes {
       var meshData = MeshData(mesh: mesh)
       for submesh in mesh.submeshes {           // empty for CubeMesh — loop body never runs
           if gameObject.shouldRenderSubmesh(submesh) {
               if isTransparent(submesh: submesh) {
                   meshData.appendTransparent(submesh: submesh)
               } else {
                   meshData.appendOpaque(submesh: submesh)
               }
           }
       }
       modelData.addMeshData(meshData)
   }
   ```
   The resulting `MeshData` has `opaqueSubmeshes == []` and `transparentSubmeshes == []`.

2. **The draw path skips the cube entirely.** `DrawManager.DrawOpaque` (`Managers/DrawManager.swift:128-148`):
   ```swift
   for (model, region) in snapshot {
       for meshData in region.meshDatas {
           if !meshData.opaqueSubmeshes.isEmpty {   // false for cube → skipped
               ...
               DrawFromRingBuffer(... submeshes: meshData.opaqueSubmeshes ...)
           }
       }
   }
   ```
   And the inner `drawSubmeshes` (`Managers/DrawManager.swift:464-489`) is `for submesh in submeshes { ... drawIndexedPrimitives(...) }`. With zero submeshes there is **no `drawIndexedPrimitives` call**, and no fallback `drawPrimitives` non-indexed path. The cube's 36-vertex buffer is allocated, uploaded, and never bound — no fragments are produced.

The same logic applies to `DrawShadows` (line 210-226) and to the transparent path (`DrawTransparent` lines 150-182), so cubes also produce no shadows and would not render as transparent objects either.

### Why it didn't always break — the old fallback

In commit `6c8df18` ("Major refactoring; using proto-engine derived from 2etime's tutorials.", Sep 2022), `Mesh` owned its own draw method with an explicit fallback for the "no submeshes" case:

```swift
// historical Mesh.drawPrimitives, removed during the DrawManager refactor
if _submeshes.count > 0 {
    for submesh in _submeshes { drawIndexedPrimitives(...) }
} else {
    renderCommandEncoder.drawPrimitives(type: .triangle,
                                        vertexStart: 0,
                                        vertexCount: _vertices.count,
                                        instanceCount: _instanceCount)
}
```

That non-indexed fallback is what kept `CubeMesh` (and `TriangleMesh`) rendering despite having no submeshes. When the draw responsibility moved out of `Mesh` and into `DrawManager`, the fallback was not carried over — `DrawManager` only knows how to draw via the submesh/index path. The bug has been latent ever since the refactor; it only became noticeable because `FlightboxWithPhysics` now spawns hundreds of cubes that visibly don't appear.

### Same bug affects `TriangleMesh`

`TriangleMesh` (`ProgrammaticMeshes.swift:8-14`) has exactly the same shape: 3 `addVertex` calls, no `addSubmesh`. The `testTri` at `FlightboxScene.swift:180-183` also does not render today — it just hasn't been noticed because it's small and uncolored.

`QuadMesh` (lines 16-40) is the lone holdout: it has 4 verts plus `addSubmesh(Submesh(indices: [0,1,2, 0,2,3]))`, so it survives the modern draw path. That's also why scenes that test programmatic geometry render quads but not cubes.

(All MDLMesh-derived meshes — `PlaneMesh`, `SphereMesh`, `CapsuleMesh`, `IcosahedronMesh`, `SkyboxMesh` — are unaffected, because `Mesh.init(mdlMesh:mtkMesh:)` at `Mesh.swift:51-58` enumerates `mtkMesh.submeshes` and calls `addSubmesh` for each. `Sphere` → `ObjModel("sphere")`, `CapsuleObject` → `CapsuleMesh()`, `Quad` GameObject → `ModelType.Plane` → `PlaneMesh()` all go through that constructor.)

### Quick verification ideas (no code changes)

- Drop a breakpoint in `DrawManager.drawSubmeshes` and confirm it's never entered with `mesh.name == "Mesh"` / parentModel `"Cube"` — only sphere/capsule/etc.
- In `SceneManager.CreateModelData`, log `mesh.submeshes.count` per registered GameObject. Expect 0 for every cube.
- Capture a frame in Xcode's GPU debugger and search for any draw call whose vertex buffer matches the cube's `vertexBuffer.label`. None should appear.
- Check `SceneManager.SubmeshCount` printed in `FlightboxScene.buildScene` / `FlightboxWithPhysics.buildScene` against expected total. A scene with N cubes contributes 0 to that number.

---

# Suggested fixes (ranked by impact, in spirit of "smallest change that closes the bug")

> *No code changes have been made yet; these are proposed.*

### Recommended — add a submesh to `CubeMesh` (and `TriangleMesh`)

Easiest, lowest-risk, and keeps the modern draw path as the only path. After the existing 36 `addVertex(...)` calls in `CubeMesh.createMesh()`, append:

```swift
addSubmesh(Submesh(indices: Array(UInt32(0)..<UInt32(36))))
```

`Submesh(indices:)` already builds an index buffer from a `[UInt32]` (`AssetPipeline/Submesh.swift:32-37`). 36 indices, primitive type `.triangle` (the default at `Submesh.swift:23`), draws all 6 faces. No vertex data changes; existing winding (`setFrontFacing(.clockwise)` + `setCullMode(.back)`) keeps working because the verts are already in triangle-list order with outward normals.

Do the same one-line fix for `TriangleMesh` (`indices: [0, 1, 2]`).

Pros:
- One line per mesh.
- No changes to `DrawManager`, `SceneManager`, or any draw path.
- Triangle/Cube get materials, shadows, transparency-classification, etc. for free, like every other GameObject.

Cons:
- Adds an index buffer for what could be a non-indexed draw — but it's 144 bytes total for the cube. Irrelevant.

### Alternative — replace with `MDLMesh.newBox(...)`

Rewrite `CubeMesh` along the same lines as `SphereMesh` / `CapsuleMesh` (`BasicMeshes.swift:38-110`):

```swift
class CubeMesh: Mesh {
    override init() {
        let mdl = MDLMesh(boxWithExtent: float3(2, 2, 2),
                          segments: [1, 1, 1],
                          inwardNormals: false,
                          geometryType: .triangles,
                          allocator: Self.mtkMeshBufferAllocator)
        mdl.vertexDescriptor = Graphics.MDLVertexDescriptors[.Base]
        mdl.addTangentBasis(...)   // mirror SphereMesh
        let mtk = try! MTKMesh(mesh: mdl, device: Engine.Device)
        super.init(mdlMesh: mdl, mtkMesh: mtk)
    }
}
```

Pros:
- Gets proper tangent/bitangent for normal maps for free.
- Same code path as Sphere/Capsule (consistency).

Cons:
- Loses the per-vertex rainbow colors currently baked into `CubeMesh` (probably no one cares — `Cube` calls `setColor(...)` to override anyway).
- Bigger diff than the one-liner above.

### Defense-in-depth (do this in addition to one of the above, not alone)

**Resurrect the historical fallback inside `DrawManager.drawSubmeshes`.** After the `for submesh in submeshes` loop, if `submeshes` is empty but `mesh.vertexBuffer != nil`, fall back to:

```swift
renderEncoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
renderEncoder.drawPrimitives(type: .triangle,
                             vertexStart: 0,
                             vertexCount: mesh._vertexCount,   // would need to expose
                             instanceCount: instanceCount)
```

Pros:
- Restores the implicit invariant the old `Mesh.drawPrimitives` enforced — any future programmatic mesh that forgets `addSubmesh` still renders.
- Cheap.

Cons:
- Two code paths in the draw inner loop.
- Materials still wouldn't apply on this path unless `applyMaterials` block is moved out of the submesh loop.
- Easy to mask future bugs ("why isn't my material/shadow showing on this object" — because it silently took the fallback path).

I'd rather make the fix at the mesh layer (option 1 or 2) than at the draw layer. If we add the defense-in-depth, log a one-time warning ("mesh X drawn via non-indexed fallback — missing addSubmesh?") so future regressions are visible.

### Recommended minimum

Just option 1: add the `addSubmesh(Submesh(indices: 0..<36))` to `CubeMesh.createMesh()`, and the analogous one to `TriangleMesh`. Single-line fixes, no risk, no architectural changes. The `FlightboxWithPhysics` ~333 expected cubes will appear immediately.
