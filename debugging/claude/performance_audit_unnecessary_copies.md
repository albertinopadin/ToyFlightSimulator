# Performance Audit: Unnecessary Copies & Hot-Path Inefficiencies

**Date:** 2026-06-12
**Scope:** Renderers (`Display/`), `DrawManager`, `SceneManager`, `Physics/`, `Math/`, plus the code those paths call every frame (Node/GameObject scene graph, `LightManager`, `Skeleton`, `GameStatsManager`, `ComputeManager`).
**Method:** Manual read-through of every file on the render and update hot paths, tracing per-frame work in the default configuration (`FlightboxWithPhysics`: ~102 physics entities, F-22 with skeletal animation, 100 random rigid-body objects).

Findings are ordered by estimated impact. Line numbers are as of commit `b4a1d6e`.

---

## TL;DR

| # | Finding | Area | Severity |
|---|---------|------|----------|
| P1 | Broad-phase runs every frame but its output is **discarded** under `.NaiveEuler` (the default scene's mode) | Physics | **High** |
| P2 | String-UUID identity (`RigidBody.id`) drives per-frame dictionary/Set hashing everywhere | Physics | **High** |
| P3 | Broad phase allocates ~8 collections per frame and recomputes `getAABB()` O(n log n)–O(n²) times | Physics | **High** |
| P4 | `EulerSolver.resolveCollisions` is O(n²) over both (i,j) and (j,i), with `pow()`+`sqrt()` per check | Physics | **High** |
| R1 | Transparent objects' `gameObjects` array is copied to `ContiguousArray` **every frame** | SceneManager | Medium |
| R2 | Animated-mesh draw path allocates + double-copies a `[ModelConstants]` per mesh **per pass** (×6 passes/frame) | DrawManager | Medium |
| N1 | `Node.modelMatrix` getter recomputes parent×local on every access; recomputed per child in `update()` and twice more in `GameObject.update()` | Scene graph | Medium |
| G1 | `GameStatsManager` dispatches 2 main-queue closures + fires `@Published` **every frame**; `removeFirst()` O(n) per frame | Stats | Medium |
| A1 | `Skeleton.evaluateWorldPoses()` computes `bindTransforms[i].inverse` (and `basisTransform.inverse`) per joint **per call** instead of caching | Animation | Medium |
| — | ~10 smaller items (label-string allocs per draw, per-frame snapshot dicts, `view.sampleCount` set per frame, scene-graph traversal for particles, etc.) | Various | Low |

Things that are **already in good shape** are listed at the end — several past optimizations (ring-buffer zero-copy, light scratch buffers, pre-bucketed lights, animation channel pre-mapping) are working as designed.

---

## Physics (`ToyFlightSimulator Shared/Physics/`)

This is where the real per-frame waste is. The default scene (`FlightboxWithPhysics`) runs `PhysicsWorld.update()` every update tick with ~102 entities.

### P1. Broad-phase output is computed and thrown away under `.NaiveEuler` — HIGH

`PhysicsWorld.update` (`World/PhysicsWorld.swift:46-73`) always runs the full broad phase when `useBroadPhase == true` (the default):

```swift
broadPhase.update(entities: entities)                       // sort, dict/Set churn (see P3)
let potentialPairs = broadPhase.getPotentialCollisionPairs() // O(n·k) pair build
switch self.updateType {
    case .NaiveEuler:
        naiveUpdate(deltaTime: deltaTime, collisionPairs: potentialPairs)
```

…but `naiveUpdate` (`PhysicsWorld.swift:76-79`) **ignores `collisionPairs` entirely** — the comment says "naive update doesn't handle collisions, but we pass pairs for future use" — and `EulerSolver.step` then runs its own O(n²) `resolveCollisions`. `FlightboxWithPhysics.swift:22` uses `.NaiveEuler`, so in the shipping default scene **all broad-phase work is pure overhead**: the entity filters, the sort, the position-tracking dictionary, the pairs array — every frame, discarded.

**Fix (either):**
1. Make `EulerSolver` consume the pairs (mirror `HeckerCollisionResponse.resolveCollisions(deltaTime:entities:collisionPairs:)`), or
2. Skip `broadPhase.update()` + pair generation when the update type doesn't use them.

Option 1 also collapses the O(n²) narrow phase (see P4) to O(pairs).

### P2. String UUID identity → per-frame String hashing everywhere — HIGH

`RigidBody.id` is `UUID().uuidString` (`World/RigidBody.swift:59`) — a 36-char heap String. It is the key for:

- `collidedWith: [String: Bool]` — read/written per pair check, per frame (`EulerSolver.swift:34,41-42`, `HeckerCollisionResponse.swift:27,31-32`)
- `entityIndexMap: [String: Int]` — **rebuilt from scratch every call** in `HeckerCollisionResponse.resolveCollisions` (`HeckerCollisionResponse.swift:15-18`)
- `lastFramePositions: [String: float3]` — **rebuilt every frame** in `BroadPhaseCollisionDetector.updateLastFramePositions` (`BroadPhaseCollisionDetector.swift:228-234`)
- `Set(dynamicEntities.map { $0.id })` ×2 — **built every frame** in `performInsertionSort` (`BroadPhaseCollisionDetector.swift:191-192`)

Hashing a 36-char string costs ~10× hashing an `Int`, and each of these structures re-hashes every entity every frame.

**Fix:** Give `PhysicsEntity` an `Int` identity (monotonic counter at init) or use `ObjectIdentifier(rigidBody)`. `collidedWith` can become a `Set<Int>` (the `Bool` value is never `false`). The `Node._id`/`GameObject.id` UUID strings have the same shape but are only hashed at registration time, so they matter much less.

### P3. Broad phase: per-frame allocations and repeated `getAABB()` — HIGH

`BroadPhaseCollisionDetector` (`BroadPhase/BroadPhaseCollisionDetector.swift`), per frame:

- `update()` line 40-41: `entities.filter { $0.isStatic }` + `entities.filter { $0.isDynamic }` — two fresh arrays.
- `performFullSort()` line 179-183: the comparator calls `entityA.getAABB()` / `entityB.getAABB()` **inside `sorted(by:)`** — O(n log n) AABB constructions, each behind a weak-ref dereference (see P5). Precompute `(minX, entity)` pairs once (O(n)) and sort those.
- `performInsertionSort()` line 186-225: copies the sorted array, builds two `Set<String>`s and a `filter`ed array, then the insertion loop calls `sorted[j].getAABB()` in the inner `while` — worst case O(n²) AABB recomputations. Cache `aabb.min.x` per entity in a parallel array.
- `getPotentialCollisionPairs()` line 83-94: `entityB.getAABB()` is recomputed in the inner loop for every `i` — O(n·k). Hoist all AABBs into a `[AABB]` built once per frame (O(n)), then sweep over indices.
- `pairs: [(PhysicsEntity, PhysicsEntity)]` — an array of existential tuples reallocated per frame, no `reserveCapacity`. Index pairs (`[(Int, Int)]`) into the entities array are far cheaper and would also fix P7.
- Statistics: `CFAbsoluteTimeGetCurrent()` ×4 and stat updates run unconditionally every frame (lines 37, 62-65, 72, 123-127). Cheap, but it's release-build overhead for a debugging feature — gate behind a flag or `#if DEBUG`.

### P4. `EulerSolver.resolveCollisions`: O(n²) both-orders loop, `pow`+`sqrt` per check — HIGH

`Solver/EulerSolver.swift:28-30` iterates `i in 0..<n`, `j in 0..<n`, `i != j` — 10,404 iterations for 102 entities, visiting each pair twice (the `collidedWith` dict short-circuits the second visit's narrow phase, but the loop body, existential dispatch, and dict lookup still run). Use `j in (i+1)..<n` for an immediate 2× cut, and consume broad-phase pairs (P1) for far more.

Per narrow-phase check, `PhysicsWorld.collided(sphereA:sphereB:)` → `getDistance` (`PhysicsWorld.swift:101-106`) computes:

```swift
sqrt((pow(dx, 2) + pow(dy, 2) + pow(dz, 2)))
```

Three `pow()` calls (not guaranteed to fold to multiplies) plus a `sqrt`, where comparing **squared** distance against `(rA + rB)²` needs neither:

```swift
simd_length_squared(posA - posB) <= (rA + rB) * (rA + rB)
```

Same idea in `collided(sphere:plane:)` is fine (no sqrt), and `float3.magnitude` (used in `HeckerCollisionResponse.swift:73,111-112` and `EulerSolver.swift:50`) is OK where the actual length is needed, but threshold comparisons (`relVeloMagnitude < 0.55`, `entityADeltaVelo.magnitude > 1.0`) can also use `length_squared` against squared constants.

### P5. Every `getPosition()`/`getAABB()` goes through a `weak` reference — MEDIUM

`RigidBody.gameObject` is `weak` (`World/RigidBody.swift:47`), so every `getPosition()`, `setPosition()`, `getAABB()` does an atomic `objc_loadWeakRetained`/release round-trip. The loops above call these tens of thousands of times per frame in aggregate.

**Fix:** the structural fix is P3/P4 (call them O(n) times instead of O(n²)); additionally, snapshot positions/AABBs into plain arrays at the top of `PhysicsWorld.update()` and have the broad phase + narrow phase read the snapshot. (Changing `weak` to `unowned` is possible but only saves part of the cost and adds lifetime risk.)

### P6. Existential storage: `[PhysicsEntity]` — MEDIUM

`entities` is `[any PhysicsEntity]` and every property access in the solvers (`entities[i].velocity`, `.isStatic`, `.force`, …) goes through protocol-witness dispatch. The only conformer is `RigidBody` (a class). Storing `[RigidBody]` (keeping the protocol for the API boundary if desired) makes element access direct class dispatch and lets the optimizer devirtualize. Combined with P2's `Int` ids, the whole solver loop becomes branch-predictable.

### P7. `HeckerCollisionResponse` rebuilds its index map per call — LOW (but free to fix)

`HeckerCollisionResponse.swift:15-18` builds `[String: Int]` over all entities every frame. If the broad phase returns index pairs (P3), this map disappears entirely.

### P8. `VerletSolver.zeroAcceleration` is a separate full pass — LOW

`Solver/VerletSolver.swift:10` does an extra O(n) loop (with existential writes) that the main loop at line 12 could absorb. Trivial, but it's a free win while in there.

---

## SceneManager / DrawManager

The ring-buffer snapshot design is fundamentally sound — the update thread writes `ModelConstants` straight into the GPU buffer and the render thread binds regions with zero copying. Two real copies remain, plus small per-frame churn:

### R1. Transparent objects: array copied every frame — MEDIUM

`SceneManager.writeFrameSnapshot` (`Managers/SceneManager.swift:220`):

```swift
// Transparent objects use ContiguousArray via a temporary:
let gameObjects = ContiguousArray(objData.gameObjects)
```

This converts `TransparentObjectData.gameObjects: [GameObject]` to `ContiguousArray` **per transparent model, per frame** — an O(n) allocation+copy whose only purpose is matching `DrawManager.writeModelConstants`'s parameter type.

**Fix:** declare `TransparentObjectData.gameObjects` as `ContiguousArray<GameObject>` (matching `ModelData`), or make `writeModelConstants` generic over `RandomAccessCollection`. One-line change, removes the per-frame copy entirely.

### R2. Animated-mesh draws: temp `[ModelConstants]` allocated and copied twice, per mesh per pass — MEDIUM

`DrawManager.DrawFromRingBuffer` (`Managers/DrawManager.swift:406-419`): when `mesh.transform?.currentTransform != .identity`, the code:

1. allocates a `[ModelConstants]` copied **out of** the ring buffer,
2. multiplies each element's `modelMatrix` by the mesh-local transform,
3. copies it **back into** a new ring-buffer region via `writeUniformsToRingBuffer` (`memcpy`).

For a USD model with animated mesh transforms (the F-22), this happens per affected mesh in **every pass that draws it** — 4 shadow cascades + GBuffer + transparency = up to 6 times per frame for the same data, each with a heap allocation.

**Fixes, in increasing order of ambition:**
1. *Drop the intermediate array:* reserve the destination region first, then do one read-modify-write loop from the source region directly into the destination (`dst[i] = src[i]; dst[i].modelMatrix *= localTransform`). Removes the allocation and one of the two copies. Same shape applies to the legacy `Draw` at line 446-451.
2. *Compute once per frame, not per pass:* cache the (animBuffer, animOffset) for a (mesh, frame) after the first pass computes it; shadow/GBuffer/transparency then re-bind the same region.
3. *Move it to the update thread:* apply `currentTransform` when the snapshot is written (`writeFrameSnapshot`), making the render path uniformly zero-copy. Requires per-mesh regions instead of per-model regions, so this is a refactor rather than a patch.

### R3. Per-frame snapshot dictionary allocations — LOW

`writeFrameSnapshot` (`SceneManager.swift:197-232`) builds fresh `[Model: RingBufferRegion]` dictionaries (opaque + transparent) each frame and assigns them into the snapshot slots. ~2 small dict allocations + rehash per frame. Reusable per-slot dictionaries (`removeAll(keepingCapacity: true)`) would eliminate it. Worth doing only opportunistically — entry counts are small.

(Verified: `RingBufferRegion.meshDatas` just retains the existing `[MeshData]` — CoW means no deep copy there.)

### R4. Debug-label string interpolation per draw call — LOW

`EncodeRender(using:label: "Rendering \(model.name)")` (`DrawManager.swift:400, 440`), plus `"Rendering \(particleObject.getName())"` (line 333) and `"Rendering \(tessellatable.getName())"` (line 356) allocate interpolated Strings per model **per pass per frame** — dozens of small heap allocations on the render thread that exist only to feed `pushDebugGroup`. Cache a `renderLabel: String` on `Model` at init, and/or gate debug groups behind a `Preferences` flag for release builds.

### R5. `LightData` arrays allocated per frame for counts/single lights — LOW

- `TiledDeferredRenderer.encodePointLightStage` (`Display/TiledDeferredRenderer.swift:95-96`) calls `LightManager.GetPointLightData()` — which locks and `map`s a fresh `[LightData]` (each `LightData` is ~0.5 KB with 4 cascade matrices) — just to check `isEmpty` and read `count`. Add a `LightManager.PointLightCount` accessor.
- `GetDirectionalLightData(viewMatrix:)` (`Managers/LightManager.swift:54-64`) allocates a small array per call and is called at least twice per frame (cascade VPs via `ShadowRendering.cascadeViewProjections`, plus `setDirectionalLightConstants`). With one directional light this is minor; an `inout`/scratch variant like the existing `SetDirectionalLightData` would zero it out.
- `ShadowRendering.cascadeViewProjections()` (`Display/Protocols/ShadowRendering.swift:64-76`) `map`s a fresh `[float4x4]` per frame. Tiny; could fill a fixed-size local instead.

---

## Scene graph (`Node` / `GameObject`) — feeds both hot paths

### N1. `modelMatrix` getter recomputes the world multiply on every access — MEDIUM

`Node.modelMatrix` (`GameObjects/Node.swift:35-43`) returns `matrix_multiply(parentModelMatrix, _modelMatrix)` — a full 4×4 multiply per access, never cached. Consequences:

- `Node.update()` line 115: `child.parentModelMatrix = self.modelMatrix` — recomputed **per child**. Hoist `let world = self.modelMatrix` above the loop (k multiplies → 1).
- `GameObject.update()` (`GameObjects/GameObject.swift:49-52`): when dirty, accesses `self.modelMatrix` twice (once for `modelConstants.modelMatrix`, once inside `Transform.normalMatrix(from:)`) — compute once into a local.
- `getFwdVector()/getUpVector()/getRightVector()/getWorldPosition()` each pay the multiply. `RigidBody.getState()` calls two of these plus `getRotationMatrix()` every frame for the aircraft.

**Fix:** cache the composed world matrix (`_worldMatrix`) when `update()` runs (the traversal already computes it top-down), and have the getter return the cache; recompute lazily if `_transformDirty`. This is the most systemic scene-graph win and also benefits physics' `getPosition()` consumers.

### N2. Eager `updateModelMatrix()` on every setter — MEDIUM (at physics scale)

Every `setPosition`/`rotate`/`setScale` immediately rebuilds `T·R·S` (2 matrix multiplies, `Node.swift:75-77, 212-217`). Under physics, an entity can get `setPosition` 1–3× per step (move + collision corrections), each rebuilding the matrix that `update()` will effectively recompute into `modelConstants` anyway. With ~100 dynamic entities that's hundreds of redundant multiplies per frame.

**Fix:** make the rebuild lazy — setters only set `_transformDirty`; `updateModelMatrix()` runs on first read (getter checks the flag) or in `update()`. Note the eager rebuild currently guarantees fresh reads mid-frame (e.g., `rotateX(getRightVector())` chains), so the lazy version must recompute on dirty *read*, not just in `update()`.

### N3. `Aircraft` dirties its subtree even with zero input — LOW

`applyPlayerSideMove` (`GameObjects/Aircraft.swift:218-220`) calls `moveAlongVector(getRightVector(), distance: deltaMove * MoveSide)` unconditionally — even when `MoveSide == 0` this runs `setPosition`, marks the aircraft + camera subtree dirty, and forces `modelConstants` recomputation every frame. Same for the rotate calls once `currentPitchRate/RollRate/YawRate` have decayed to ~0 (`applyPlayerAttitudeInput`, `decayAttitudeRates`). Guard with `if abs(delta) > .ulpOfOne`-style early-outs. (For the physics-driven jet this is mostly masked because physics moves it anyway; it matters for `shouldUpdateOnPlayerInput` aircraft without rigid bodies.)

### N4. `getRotationX/Y/Z` each run a full Euler decomposition — LOW

`Node.swift:283-285`: calling all three costs 3× `Transform.decomposeToEulers`. Add a `getRotationEulers() -> float3` for callers that need more than one axis. (Currently these don't appear on the per-frame path; noting for safety.)

---

## Math (`ToyFlightSimulator Shared/Math/`)

Good news: this layer is clean. `Transform` builds matrices column-wise with no hidden copies, the basis-transform constants are `static let`, `ValueCurve` uses binary search with reserved-capacity construction, and `MathUtils`/`simd_quatf.rotate` are allocation-free.

Remaining nits:

- **`X_AXIS`/`Y_AXIS`/`Z_AXIS`** (`Math/Math.swift:10-20`) are computed `var`s returning a new `float3` per access. Make them `let` constants (or `@inline(__always)`); the optimizer probably folds them, but there's no reason to rely on it.
- **`pow(x, 2)` pattern** — lives in `PhysicsWorld.getDistance` (covered in P4) and `F22SimpleFlightModel.calculateInducedDrag` (`pow(liftData.liftCoefficient, 2)`, once per frame — harmless there, but `x*x` is the cheaper idiom everywhere).
- **`GameScene.update()`** (`Scenes/GameScene.swift:167`) computes `camera.projectionMatrix.inverse` every frame. The projection only changes on FOV/aspect changes — cache `projectionMatrixInverse` on `Camera`, updated in `setAspectRatio` (where `projectionMatrix` is rebuilt). `Camera.viewMatrix` is already correctly cached in `updateModelMatrix()`.
- `AABB.==` (`Physics/BroadPhase/AABB.swift:104-109`) uses two `simd_distance` calls (2 sqrts) for an epsilon compare; `simd_distance_squared` against ε² avoids them. Not currently on a hot path.

---

## Renderers (`Display/`)

The renderer layer is in good shape: late drawable acquisition, memoryless GBuffers, descriptors built once and retextured only on resize, pipeline/depth-stencil states looked up from libraries. Specific items:

- **`TiledMSAATessellatedRenderer.draw` sets `view.sampleCount = 4` every frame** (`TiledMSAATessellatedRenderer.swift:139`). MTKView property setters aren't guaranteed to no-op on equal values (they can re-validate drawables); set it once in the `metalView` didSet alongside `depthStencilPixelFormat`. The `firstRun` flag in `draw` belongs there too.
- **`ComputeManager` walks the entire node hierarchy per frame** (`Managers/ComputeManager.swift:11-18` → `Node.computeParticles`/`computeTerrainTessellation`, `Node.swift:163-184`) doing an `as?` dynamic cast on every node, even though `SceneManager.particleObjects` and `SceneManager.tessellatables` registries already exist and are exactly what `DrawManager` iterates. Iterate the registries instead; the recursion + casts are pure waste (the code's own TODO agrees).
- **`Renderer.runDrawableCommands`** allocates one completed-handler closure per command buffer (3/frame) — inherent to the API, fine.
- `RenderState.Current/PreviousPipelineStateType` static tracking in `SetupAnimation` (`DrawManager.swift:184-208`) is cheap but fragile across encoders (state is global while encoders are per-pass); not a perf issue today, just flagging while in the area.

---

## Adjacent hot-path findings (outside the requested dirs, but called every frame)

### G1. `GameStatsManager`: per-frame main-queue dispatch + `@Published` churn — MEDIUM

`Managers/GameStatsManager.swift:26-54`:

- `recordRenderDeltaTime` does `lastXFrameDeltaTime.removeFirst()` — O(60) element shift every frame (the TODO already notes it; a fixed array + wrapping index fixes it).
- `frameRendered()` and `sceneUpdated()` each do `DispatchQueue.main.async { self.published += 1 }` **every frame** — at 120 fps that's 240 closure allocations + queue hops + `objectWillChange` fires per second, and every fire invalidates any observing SwiftUI view (`GameStats`). Coalesce: accumulate locally and publish at the same 60-frame cadence the FPS average already uses, or only when the stats overlay is visible.

### A1. `Skeleton.evaluateWorldPoses()`: per-joint matrix inverses recomputed every call — MEDIUM

`Animation/Skeleton.swift:143-173`, which runs whenever any animation channel is dirty (gear transitions; control-surface channels on the F-22 are procedural and effectively every frame in flight):

- `worldPose[index] *= bindTransforms[index].inverse` — a 4×4 inverse **per joint per call** for matrices that never change. Precompute `inverseBindTransforms` once in `init`.
- `basisTransform.inverse` — recomputed per call; also constant. Cache it (same fix applies to `TransformComponent.init`, which already does this at load time — `Skeleton` should match).
- `var worldPose = [float4x4]()` — fresh allocation per call; reuse a scratch array (`currentPose` itself can be written in place since it's overwritten wholesale).

### A2. `Skeleton.applyProceduralOverrides` does linear String search per joint per frame — LOW

`Skeleton.swift:134-139`: `jointPaths.firstIndex(of: jointPath)` is an O(joints) String-compare scan per override, every frame the channel is active. Build a `[String: Int]` path→index map once in `init` (or better: resolve indices once at channel-registration time in `AnimationLayerSystem`, which already pre-computes `ChannelMapping` — extend that to joint indices).

### A3. `AnimationClip.getPose` — String-keyed dict lookup per joint per frame — LOW

`Animation/AnimationClip.swift:122-131`. Acceptable today; the index-resolution approach in A2 would absorb this too.

---

## Verified clean (no action needed)

Explicitly checked for unnecessary copying and found in good shape:

- **`DrawManager.writeModelConstants`** — writes `ModelConstants` straight from GameObjects into the GPU ring buffer; the non-animated draw path binds regions with **zero copies** (`DrawManager.swift:421-422`). Buffer growth doubles and `memcpy`s only on grow.
- **`ModelData.gameObjects: ContiguousArray<GameObject>`** — passed by reference semantics (CoW, read-only) into `writeModelConstants`; no per-frame copy on the opaque path.
- **Snapshot reads** (`getOpaqueSnapshot` etc.) — dictionary returns are CoW retains, not copies.
- **`LightManager`** — pre-bucketed directional/point arrays; `SetDirectionalLightData`/`SetPointLightData` reuse scratch buffers and encode via `withUnsafeMutableBufferPointer` (no per-frame `[LightData]` allocation on those paths).
- **`DrawManager` point-light/icosahedron scratch** — submesh caches + reused uniform scratch arrays (`DrawManager.swift:257-309`).
- **`Renderer.render()` / `UpdateThread`** — semaphore handshake, no allocation.
- **`ValueCurve`/`SymmetricSigmoidCurve` evaluation, `Transform`, `MathUtils`** — allocation-free, sqrt-avoiding where it matters (`projectOnPlane` uses `dot(n,n)`).
- **`DebugLog`** — `@autoclosure` correctly defers interpolation cost when disabled.
- **`AnimationLayerSystem`** — ordered-array iteration, pre-computed channel mappings, dirty-flag gating; the design doc's claims hold.
- **`Skin.updatePalette`** — writes the palette buffer in place via bound pointer.
- **`Camera.viewMatrix`** — cached on transform change, not recomputed per read.

---

## Suggested order of attack

1. **P1 + P4** — make `.NaiveEuler` consume broad-phase pairs (or skip the broad phase), and switch narrow-phase checks to squared-distance compares. Biggest frame-time win in the default scene, small diff.
2. **P2 + P7** — `Int`/`ObjectIdentifier` identity; index-pair output from the broad phase. Mechanical, kills all per-frame String hashing in physics.
3. **P3 (+P5)** — hoist AABBs into per-frame arrays; sort cached keys; `reserveCapacity` on pairs.
4. **R1** — one-line `ContiguousArray` type change for transparent objects.
5. **N1** — cache the world matrix; hoist `self.modelMatrix` out of the child loop and the double access in `GameObject.update()`.
6. **R2** — single-pass ring-to-ring transform for animated meshes (option 1), then consider per-frame caching (option 2).
7. **G1, A1** — stats coalescing; precomputed inverse bind matrices.
8. Remaining LOW items opportunistically.

**Measurement:** before/after with Instruments — *Time Profiler* on `PhysicsWorld.update` and `SceneManager.writeFrameSnapshot`, *Allocations* (transient) filtered to the app while sitting in `FlightboxWithPhysics` for 30 s, and the in-app FPS overlay. `PhysicsStressTestScene` already ramps entity counts and prints timing tables — useful for validating the physics changes at n > 100.
