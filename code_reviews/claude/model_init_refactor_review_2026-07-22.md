# Code Review — Model initialization consolidation into the `Model` superclass

**Scope:** Unstaged working-tree changes to `Mesh.swift`, `Model.swift`, `ObjModel.swift`, `UsdModel.swift` (AssetPipeline)
**Date:** 2026-07-22
**Method:** Manual line-by-line review of the diff with caller/subclass tracing, followed by build + scoped-test verification (`build-for-testing` + `test-without-building`; unscoped local `xcodebuild test` hangs at app-host launch on this machine, so the full suite is left to CI). Post-review fixes (§5) were applied in the same session and re-verified.

---

## 1. What changed

The duplicated load sequence (bundle URL lookup → vertex descriptor → `MDLAsset` → `loadTextures()` → `childObjects` → `GetMeshes`) that lived in both `ObjModel.init` and `UsdModel.init` moved into a new `Model` designated init. `ObjModel` collapses to a one-line `super.init` call; `UsdModel` becomes an `override init` that adds skeleton/skin/animation loading on top. Supporting changes:

- `Model` gains stored `asset: MDLAsset` and `mdlMeshes: [MDLMesh]` (kept for CPU-side access to the imported geometry).
- `Mesh` gains `mdlMesh: MDLMesh?` (`nil` for hand-rolled procedural meshes via `init()`).
- `InspectMeshes` moves from `UsdModel` (private) to `Model` (internal) and now also runs for OBJ loads.
- `UsdModel(_:assetUrl:)` is deleted.

## 2. Correctness — verified ✓

- **Removed `UsdModel(_:assetUrl:)` has zero callers** in the codebase or tests; every `ObjModel`/`UsdModel` call site in `ModelLibrary.makeLibrary()` uses signatures that still exist.
- **Dropping `preserveTopology: false, error: nil` from the OBJ path is equivalent**: Apple documents the 3-arg `MDLAsset(url:vertexDescriptor:bufferAllocator:)` as triangulating exactly as the 5-arg form does with `preserveTopology: false`, and `error:` was `nil` anyway.
- **The `UsdModel` override is valid.** As originally diffed it relied on a contravariant override (`float4x4?` over non-optional `float4x4`), which the compiler accepts; after the §5 fix the signatures match exactly and the question is moot.
- **Init phase ordering is legal Swift**: reads of already-initialized `let`s, static calls, and `asset.loadTextures()` (a method on the property's object, not `self`) are all fine pre-completion; `meshes.forEach { $0.parentModel = self }` runs only after all stored properties are set, and `Model` has no superclass.
- **Every `Mesh` subclass funnels into the two designated inits** (`init()` and `init(mdlMesh:mtkMesh:...)`), both of which set the new `mdlMesh` property — checked `BasicMeshes`, `ProgrammaticMeshes`, `SingleSubmeshMesh`.
- `scripts/measure_models.swift` is not a target member (0 pbxproj references) — unaffected.

## 3. Issue — permanent MDL retention (main risk; documented, deferred)

`Model` previously let the `MDLAsset` and `[MDLMesh]` die at the end of init; now they are stored properties on an object `ModelLibrary` caches for the process lifetime, and `loadTextures()` runs first — so **each model's full ModelIO representation, including source texel data, stays resident forever**. Concrete consequences:

- **It partially defeats `SingleSubmeshMesh.clearCachedSourceModels()`.** That teardown hook exists precisely to release parsed parent assets, but every extracted submesh (cached forever in `SingleSubmeshMeshLibrary`) now pins its source `MDLMesh` via `Mesh.mdlMesh` — and with it the full shared parent vertex/index buffers, submeshes, and materials of e.g. the F-18 source model. The copy-vertex-buffer isolation in `SingleSubmeshMesh.init` was built so the parent could be let go; this quietly undoes the "let go" half.
- iOS is already memory-tight (SinglePassDeferred is broken there today), and this grows the steady-state footprint of every loaded aircraft.

**Resolution (this session):** `asset` was made optional (`MDLAsset?`, `nil` for procedural models — this also removed the dummy `MDLAsset()` sentinel flagged with "This stinks"). Making it optional is an API-honesty fix, not a release path: file-loaded models still retain their asset for the process lifetime, so the retention risk stands. A `NOTE:` doc comment on `Model.asset`/`mdlMeshes` now calls this out for a future refactor (release after consumers extract what they need, or store only the extracted data).

## 4. Issue — identity basis transform always ran (fixed)

The old code passed `basisTransform` through as an optional, and `Mesh.init` skips `transformMeshBasis` entirely when it is `nil`. The consolidated designated init took non-optional `basisTransform: float4x4 = .identity`, so `GetMeshes` always received a value — every model registered *without* a basis (sphere, quad, skysphere, Temple, F-35) got a full CPU pass multiplying every position/normal/tangent/bitangent by identity, and `TransformComponent` stored identity instead of `nil` (per-sample conjugation instead of a skip on animated USD meshes). Output was bit-identical (identity multiply is exact; det = 1 → no winding reversal), so this was load-time/per-frame waste rather than a rendering bug.

**Resolution (this session):** the designated init now takes `basisTransform: float4x4? = nil` and passes the optional straight through to `GetMeshes`; only the stored `Model.basisTransform` defaults to `.identity` (as before). `ObjModel`/`UsdModel` dropped their `?? .identity`, restoring the exact pre-refactor semantics: `nil` ⇒ no per-vertex pass, no per-sample conjugation.

## 5. Post-review fixes applied

1. **`Model.asset` is now `MDLAsset?`** — `nil` for procedural models (`init(name:meshes:)`); the file-loading init builds a local non-optional `asset` and assigns it once. `UsdModel.init` unwraps it with a `guard let` + `fatalError` (it is guaranteed non-nil after the file-loading super.init).
2. **Retention `NOTE:` comment added** on `Model.asset`/`mdlMeshes` (see §3) marking the future refactor.
3. **Optional `basisTransform` pass-through** restored end-to-end (see §4), with a doc comment on the designated init explaining why it stays optional.
4. Fixed a missing `[` in the renamed `[Model InspectMeshes]` print prefix (author applied the prefix rename and the direct `self.meshes` assignment mid-review).
5. **`InspectMeshes` routed through `DebugLog`**, gated by a new `DEBUG_MESH_INSPECTION` flag in Preferences (off by default) — OBJ loads (Temple especially) would otherwise have emitted per-mesh/per-submesh console output they didn't before.

## 6. Remaining follow-ups (minor, not blocking)

- The future retention refactor documented on `Model.asset` (§3): release or slim `asset`/`mdlMeshes`/`Mesh.mdlMesh` once their consumer (e.g. collision-shape generation) lands, and revisit the `SingleSubmeshMesh` parent-pinning interaction with `clearCachedSourceModels()`.

## 7. Test verification

Two full verification rounds (before and after the §5 fixes), both green:

- `xcodebuild build-for-testing` (app + test bundle): **succeeded** both rounds.
- Scoped `test-without-building` run: **37 Swift Testing tests in 6 suites + XCTest `NodeTests`, all passed** — `RigidBodyTests`, `SingleMeshVertexMetadataTests`, `MaterialTextureTransformTests`, `MDLMaterialSemanticTests`, `TextureLoaderOptionsTests`, `AircraftEntitySwapTests`, `NodeTests`.
- Coverage of this refactor is better than the suite names suggest: `RigidBodyTests` constructs a real `F22`, loading the Sketchfab F-22 USDZ (det < 0 basis → winding-reversal path) through the new consolidated init; and the test host app itself boots `FlightboxWithPhysics`, which loads the CGTrader F-22 (USD path, explicit basis) plus the `Quad` warm-up (OBJ path, now `nil` basis) — a `fatalError` or misload in the new init would have failed the entire run.
- Remaining suites (Math, Utils, Shadows, Cameras, Managers, Scenes, physics solvers) don't touch model loading; `AircraftThumbnailRenderTests` imports files via SceneKit, not this class. No test references the removed `assetUrl:` initializer. Full suite left to CI; expected green.
