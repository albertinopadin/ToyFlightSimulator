# Plan: Incremental DOD / ECS Refactor of ToyFlightSimulator

**Date:** 2026-05-13
**Companion research:** `investigations/claude/ecs_and_dod_research_2026-05-13.md`

## Goals

1. Sustain **120 FPS** on Apple Silicon by reshaping the per-frame hot loops into Struct-of-Arrays (SoA) form, where the CPU's prefetcher and L1 cache can do their job.
2. Make per-entity feature composition (physics, animation, weapons, AI, sensors, fuel, damage) **additive** rather than requiring a subclass — the current `Aircraft : GameObject : Node` chain is at its ergonomic limit.
3. Do it **incrementally**, with a measurement gate between every phase, so each phase can be merged independently and any phase can be the stopping point if the gains plateau.

## Non-Goals

- Not migrating to a third-party ECS library (GameplayKit, OctopusKit, or a Rust/C++ ECS bridged into Swift). The TFS object count is small enough that a bespoke 200-line component registry is cheaper than the abstraction tax of a library.
- Not changing the Metal pipeline shape. The renderer-side data (ring buffer of `ModelConstants`, snapshots, render-pass ordering) stays the same. The refactor is entirely *upstream* of `DrawManager.DrawOpaque()`.
- Not replacing the OOP `Node`/`GameObject`/`Aircraft` API at the call sites in scenes. The scenes that say `aircraft.setPosition(...)` keep working unchanged. We're refactoring the *storage*, not the *interface*.

## Phases at a glance

| Phase | What changes | Files touched | Risk |
|---|---|---|---|
| 0 | Add `os_signpost` intervals + capture baseline `.trace` | `Renderer.swift`, `SceneManager.swift`, `UpdateThread.swift` | None — pure instrumentation |
| 1 | Move `ModelConstants` storage off `GameObject` into per-Model SoA columns | `GameObject`, `SceneManager`, `DrawManager` | Low — bounded to the render path |
| 2 | Replace `Node`'s inline transform state with a `TransformStore` SoA + parent-index hierarchy | `Node`, `GameObject`, `SceneManager` | Medium — touches every node |
| 3 | Replace `[PhysicsEntity]` with per-shape concrete SoA stores | `PhysicsWorld`, `EulerSolver`, `VerletSolver`, `HeckerCollisionResponse`, `BroadPhaseCollisionDetector` | Medium — physics math has to stay identical |
| 4 | Introduce `World` + `EntityID` + sparse-set `ComponentStore<T>`; migrate animation channels and one new feature | `Animation/`, new `ECS/` folder, `Aircraft` | Medium — the new abstraction lives alongside the old |
| 5 | (Optional) Decide whether to keep migrating or stop | TBD | TBD |

The plan is structured so you can stop after Phase 1 if FPS is already in target. Each phase is independently shippable and independently revertable.

---

## Phase 0 — Baseline measurement

**Goal:** Have a `.trace` file and a small table of numbers that any future change can be diffed against.

### Work

1. Wrap the major frame phases in `os_signpost` intervals. The existing `GameStatsManager.sharedInstance.sceneUpdated()` is a convenient anchor, but we want explicit intervals.

```swift
// In a new file: ToyFlightSimulator Shared/Utils/PerfSignposts.swift
import os.signpost

enum PerfSignpost {
    static let log = OSLog(subsystem: "com.toyflightsimulator", category: .pointsOfInterest)

    static let updateScene  = OSSignpostID(log: log)
    static let updatePhys   = OSSignpostID(log: log)
    static let updateAnim   = OSSignpostID(log: log)
    static let writeSnap    = OSSignpostID(log: log)
    static let renderShadow = OSSignpostID(log: log)
    static let renderGBuf   = OSSignpostID(log: log)
    static let renderLight  = OSSignpostID(log: log)
}
```

Then in `SceneManager.Update` (around `SceneManager.swift:176`):

```swift
os_signpost(.begin, log: PerfSignpost.log, name: "update.scene", signpostID: PerfSignpost.updateScene)
CurrentScene?.updateCameras(deltaTime: deltaTime)
CurrentScene?.update()
os_signpost(.end, log: PerfSignpost.log, name: "update.scene", signpostID: PerfSignpost.updateScene)

os_signpost(.begin, log: PerfSignpost.log, name: "writeSnapshot", signpostID: PerfSignpost.writeSnap)
writeFrameSnapshot(frameIndex: nextFrameIndex)
os_signpost(.end, log: PerfSignpost.log, name: "writeSnapshot", signpostID: PerfSignpost.writeSnap)
```

(Similar pairs around shadow/gbuffer/lighting passes in each renderer.)

2. Pick a fixed test scene. **`FlightboxWithPhysics`** is the right choice — it has player aircraft, AI aircraft, ground physics, and the renderer used in iOS production (`TiledMSAATessellated`). Make sure `Preferences.StartingSceneType = .FlightboxWithPhysics` for the profile build.

3. Profile in Release configuration with `Instruments → Game Performance` template for 10 seconds of representative play.

4. Open the trace and record these numbers into `investigations/claude/perf/baseline_2026-05-13.md`:

   - Average frame time (ms), 99th-percentile frame time (ms).
   - Average duration of each signpost interval (ms).
   - From a Counters profile: IPC, L1D miss rate, L2 miss rate, branch misprediction rate, sampled inside the hottest few signpost intervals.
   - From the Metal frame capture: GPU utilization, longest fragment shader, longest vertex shader.

This is the "do not regress" yardstick.

### Exit criterion

The baseline file exists, the numbers are written down, the .trace is saved.

---

## Phase 1 — Per-Model SoA `ModelConstants`

**Goal:** Replace the per-frame `for i in 0..<count { dst[i] = gameObjects[i].modelConstants }` loop with a pure linear stream from a SoA column to the ring buffer. Eliminate the class-pointer chase per game object.

### Before

`ToyFlightSimulator Shared/GameObjects/GameObject.swift:34`:

```swift
class GameObject: Node, PhysicsEntity, Renderable, Hashable {
    ...
    public let model: Model
    public var modelConstants = ModelConstants()
    var instanceBufferIndex: Int = -1
    ...
    override func update() {
        super.update()
        if worldMatrixDirty {
            modelConstants.modelMatrix  = self.modelMatrix
            modelConstants.normalMatrix = Transform.normalMatrix(from: self.modelMatrix)
        }
        model.update()
    }
}
```

`ToyFlightSimulator Shared/Managers/DrawManager.swift:80-88`:

```swift
let dst = ringBuffer.contents().advanced(by: alignedOffset)
    .assumingMemoryBound(to: ModelConstants.self)
for i in 0..<count {
    dst[i] = gameObjects[i].modelConstants    // <-- class pointer chase
}
```

`ToyFlightSimulator Shared/Managers/SceneManager.swift:43-54`:

```swift
struct ModelData {
    var gameObjects = ContiguousArray<GameObject>()
    var meshDatas: [MeshData] = []

    mutating func addGameObject(_ gameObject: GameObject) {
        self.gameObjects.append(gameObject)
    }
    ...
}
```

### After

Add a SoA column store next to the existing `gameObjects` array. Keep `GameObject.modelConstants` as a *compatibility shim* during the transition so call sites don't change.

```swift
// SceneManager.swift — augmented ModelData

struct ModelData {
    var gameObjects   = ContiguousArray<GameObject>()
    /// Parallel to `gameObjects` — modelConstants[i] belongs to gameObjects[i].
    /// Written by the update pass, read directly by the ring-buffer memcpy.
    var modelConstants = ContiguousArray<ModelConstants>()
    var meshDatas: [MeshData] = []

    mutating func addGameObject(_ gameObject: GameObject) {
        gameObject.modelConstantsIndex = gameObjects.count
        gameObject.owningModelData = self  // weak-ish handle; see note below
        gameObjects.append(gameObject)
        modelConstants.append(ModelConstants())
    }
}
```

`GameObject` becomes a *thin handle* that writes into the column:

```swift
// GameObject.swift — slimmed update path

class GameObject: Node, PhysicsEntity, Renderable, Hashable {
    public let model: Model
    /// Index into the owning ModelData.modelConstants column.
    /// -1 means "not registered with SceneManager yet."
    var modelConstantsIndex: Int = -1

    // The legacy `modelConstants` property is now a passthrough into the column.
    // Old call sites (e.g. setColor) keep working unchanged.
    public var modelConstants: ModelConstants {
        get {
            guard modelConstantsIndex >= 0,
                  let col = SceneManager.modelConstantsColumn(for: model)
            else { return ModelConstants() }
            return col[modelConstantsIndex]
        }
        set {
            guard modelConstantsIndex >= 0,
                  SceneManager.writeModelConstants(newValue, at: modelConstantsIndex, for: model)
            else { return }
        }
    }

    override func update() {
        super.update()
        if worldMatrixDirty {
            // Write directly into the column — no inline storage on self.
            SceneManager.updateModelConstants(at: modelConstantsIndex, for: model) { mc in
                mc.modelMatrix  = self.modelMatrix
                mc.normalMatrix = Transform.normalMatrix(from: self.modelMatrix)
            }
        }
        model.update()
    }
}
```

The ring-buffer write becomes a single `memcpy`:

```swift
// DrawManager.swift — writeModelConstants

static func writeModelConstants(
    column: UnsafeBufferPointer<ModelConstants>,
    frameIndex: Int
) -> Int? {
    guard !column.isEmpty else { return nil }
    let size = ModelConstants.stride(column.count)
    let alignedOffset = (currentBufferOffset + 255) & ~255
    // ... ring buffer growth omitted ...
    let dst = uniformsRingBuffers[frameIndex].contents().advanced(by: alignedOffset)
    memcpy(dst, column.baseAddress!, size)   // ONE memcpy, no pointer chases
    currentBufferOffset = alignedOffset + size
    return alignedOffset
}
```

And `SceneManager.writeFrameSnapshot` becomes:

```swift
private static func writeFrameSnapshot(frameIndex: Int) {
    DrawManager.BeginFrameForUpdate(frameIndex: frameIndex)

    var opaque: [Model: RingBufferRegion] = [:]
    opaque.reserveCapacity(modelDatas.count)
    for (model, modelData) in modelDatas where !modelData.gameObjects.isEmpty {
        let offset = modelData.modelConstants.withUnsafeBufferPointer { col in
            DrawManager.writeModelConstants(column: col, frameIndex: frameIndex)
        }
        if let offset {
            opaque[model] = RingBufferRegion(
                offset: offset,
                count: modelData.modelConstants.count,
                meshDatas: modelData.meshDatas
            )
        }
    }
    opaqueSnapshots[frameIndex] = opaque
    // ... same for transparent + sky ...
    DrawManager.finishUpdateWrites(frameIndex: frameIndex)
}
```

### Why this is a real DOD change, not cosmetic

- **Before:** The hot inner loop visits N class-pointer locations in heap memory order (random) and copies ~128 B from each. ~N cache misses.
- **After:** The hot inner loop is `memcpy(dst, contiguous_source, N*128)`. The hardware prefetcher streams the column; one cache miss every 128 B regardless of N. The class instance is never touched.

### Risks and mitigations

- **Setter aliasing risk.** Old code does `aircraft.modelConstants.objectColor = ...` (a get-modify-set with the value-type intermediate). After this refactor, that still works because Swift implements the assignment via the property's get + set. Verify by grepping `modelConstants.` and reading each site.
- **`SceneManager.modelConstantsColumn(for:)`** needs to handle the transparent and sky paths the same way. Mirror it for `transparentObjectDatas` and `skyData`.
- **Aircraft animation `mesh.transform`** still requires a transient copy at draw time (see `DrawManager.DrawFromRingBuffer:406-418`). This phase doesn't change that path; the temp buffer keeps working.

### Measurement gate

- Profile the same `FlightboxWithPhysics` scene with the same duration.
- The signpost interval named `writeSnapshot` should drop noticeably (mostly because `for i in 0..<count { dst[i] = gameObjects[i].modelConstants }` was an N-cache-miss loop and is now a single memcpy).
- L1D miss rate inside `writeFrameSnapshot` should drop measurably.
- Frame time should be at-or-below baseline; if it regresses, revert.

---

## Phase 2 — Transform SoA + parent-index hierarchy

**Goal:** Apply Albrecht's GCAP 2009 scene-graph transform directly. Replace `Node.children: [Node]` recursive traversal with a linear pass over a flat array. This is the largest single performance lever in the codebase.

### Before

`Node.swift:16-33`:

```swift
class Node: ClickSelectable {
    private var _position: float3 = [0, 0, 0]
    private var _scale: float3 = [1, 1, 1]
    var parentModelMatrix = matrix_identity_float4x4
    private var _modelMatrix = matrix_identity_float4x4
    private var _rotationMatrix = matrix_identity_float4x4
    private var _transformDirty: Bool = true
    private(set) var worldMatrixDirty: Bool = true
    var parent: Node? = nil
    var children: [Node] = []
    ...
}
```

`Node.swift:98-120`:

```swift
func update() {
    doUpdate()
    let needsUpdate = _transformDirty
    if needsUpdate { _transformDirty = false }
    worldMatrixDirty = needsUpdate
    for child in children {
        if needsUpdate {
            child.parentModelMatrix = self.modelMatrix
            child._transformDirty = true
        }
        child.update()
    }
}
```

### After

Introduce a `TransformStore` that owns the per-node transform state as SoA columns:

```swift
// New file: ToyFlightSimulator Shared/Core/ECS/TransformStore.swift

/// Stable identifier into TransformStore's columns. Generational so freed
/// indices can be reused without dangling references.
struct NodeID: Equatable, Hashable {
    let index: UInt32
    let generation: UInt32
    static let invalid = NodeID(index: .max, generation: .max)
}

final class TransformStore {
    /// Hierarchy depth in BFS order. After a "rebuild order" pass, transforms
    /// at depth d come strictly after all transforms at depth d-1.
    private(set) var depths:        ContiguousArray<UInt8>   = []
    private(set) var parents:       ContiguousArray<Int32>   = [] // -1 == root
    /// Local components — what the user sets.
    var positions:      ContiguousArray<float3>      = []
    var scales:         ContiguousArray<float3>      = []
    var rotationMatrices: ContiguousArray<float4x4>  = []
    /// Derived columns — recomputed each frame by the system.
    var localMatrices:  ContiguousArray<float4x4>    = []
    var worldMatrices:  ContiguousArray<float4x4>    = []
    /// One bit per node. Walked once per frame as a packed sweep.
    var localDirty:     ContiguousArray<Bool>        = []
    var worldDirty:     ContiguousArray<Bool>        = []
    /// Generation counter so freed slots can be reused without aliasing.
    private var generations: ContiguousArray<UInt32> = []
    private var freeList: [UInt32] = []

    func create(parent: NodeID? = nil) -> NodeID { ... }
    func destroy(_ id: NodeID) { ... }
    @inline(__always) func indexOf(_ id: NodeID) -> Int? { ... }

    /// One linear pass — Albrecht's transform.
    func runFrame() {
        // (a) Recompute local matrices for any dirty locals.
        for i in 0..<positions.count where localDirty[i] {
            localMatrices[i] = Transform.translationMatrix(positions[i])
                             * rotationMatrices[i]
                             * Transform.scaleMatrix(scales[i])
            localDirty[i] = false
            worldDirty[i] = true
        }
        // (b) Sweep top-down. Because the array is ordered by depth, parent
        //     world matrices are already computed by the time we reach a child.
        for i in 0..<worldMatrices.count {
            let p = parents[i]
            if p < 0 {
                if worldDirty[i] { worldMatrices[i] = localMatrices[i] }
            } else {
                let pIdx = Int(p)
                if worldDirty[pIdx] || worldDirty[i] {
                    worldMatrices[i] = worldMatrices[pIdx] * localMatrices[i]
                    worldDirty[i] = true   // propagate to my children
                }
            }
        }
        // (c) Clear dirty flags now that everyone has consumed them.
        //     (GameObject.update reads worldDirty BEFORE this clear.)
        worldDirty.withUnsafeMutableBufferPointer { buf in
            // memset is fastest; vDSP_vfill won't help on Bool.
            for i in 0..<buf.count { buf[i] = false }
        }
    }
}
```

`Node` becomes a thin handle. The public API is unchanged for callers; only the storage moved:

```swift
class Node: ClickSelectable {
    let nodeID: NodeID
    weak var store: TransformStore?
    var parent: Node? = nil
    var children: [Node] = []     // still needed for scene-graph semantics

    init(name: String, store: TransformStore, parent: Node? = nil) {
        self.store = store
        self.nodeID = store.create(parent: parent?.nodeID)
        // ...
    }

    func setPosition(_ p: float3) {
        guard let store, let i = store.indexOf(nodeID) else { return }
        store.positions[i] = p
        store.localDirty[i] = true
        afterTranslation()
    }
    func getPosition() -> float3 {
        guard let store, let i = store.indexOf(nodeID) else { return .zero }
        return store.positions[i]
    }
    // ... same shape for rotation, scale, etc.

    var modelMatrix: float4x4 {
        guard let store, let i = store.indexOf(nodeID) else { return .identity }
        return store.worldMatrices[i]
    }

    var worldMatrixDirty: Bool {
        guard let store, let i = store.indexOf(nodeID) else { return false }
        return store.worldDirty[i]
    }
}
```

`SceneManager.Update` runs the transform pass once at the top:

```swift
public static func Update(deltaTime: Double) {
    if !Paused {
        GameTime.UpdateTime(deltaTime)
        CurrentScene?.updateCameras(deltaTime: deltaTime)
        // (1) Per-frame logic — sets dirty bits in TransformStore.
        CurrentScene?.update()
        // (2) Topological transform pass — Albrecht's linear sweep.
        transformStore.runFrame()
        // (3) Snapshot writes that depend on world matrices.
        writeFrameSnapshot(frameIndex: nextFrameIndex)
    }
}
```

### Why this works on Apple Silicon

- The transform sweep is `for i in 0..<N`. On a P-core with a 128 KB L1D, N up to ~1000 transforms (`localMatrices` + `worldMatrices` = 128 B × 2 × 1000 = 256 KB — still fits L2 trivially) runs with virtually zero L1 misses.
- The hardware prefetcher will fully cover the linear stride.
- `simd_float4x4 *= simd_float4x4` is a 64-cycle SIMD-heavy operation; doing 1000 of them is ~20 µs uncontested.
- Compared to the current recursive traversal — even with only ~50 nodes — this saves the per-node pointer chase, virtual dispatch, and `markTransformDirty` subtree walk.

### Risks and mitigations

- **Depth ordering invariant.** `parents[]` must point only at lower indices than the current entry. This is preserved when nodes are created in parent-before-child order; if a node is reparented, the store must `rebuildOrder()` (cheap — single allocation, BFS rewrite).
- **`worldMatrixDirty` semantics.** Today `worldMatrixDirty` is read by `GameObject.update()` *before* `update()` propagates dirty bits to children. In the new design, `runFrame()` does the propagation in one pass, so we have to set the read order: `CurrentScene.update()` runs first (sets local dirties), then `runFrame()` (computes worlds + sets world dirties), then `GameObject.update()` reads `worldMatrixDirty`. The cleanest fix is to *flip the order in `GameObject.update`* — write modelConstants from a post-sweep pass instead of inside `update()`. This composes naturally with Phase 1's column writes.
- **`mark transform dirty` short-circuit bug.** The current `markTransformDirty` early-return (`Node.swift:81`) is now irrelevant because dirty propagation is a single linear sweep. The bug goes away.

### Measurement gate

- `update.scene` signpost interval should drop substantially. Albrecht's documented gain on 11,111 nodes was 4× — at TFS's ~50-node count the absolute time is smaller but the relative drop should be in the same ballpark.
- L2 miss rate inside `Node.update` should drop measurably. The Time Profiler hot stacks should no longer feature `swift_release` / `swift_retain` for `Node` (because the recursion no longer walks class refs).

---

## Phase 3 — Physics SoA

**Goal:** Replace `[PhysicsEntity]` with concrete-typed SoA stores, one per shape. Eliminate every `as!` cast in the collision dispatch.

### Before

`PhysicsWorld.swift:22`:

```swift
private var entities: [PhysicsEntity]   // protocol existential array
```

`PhysicsWorld.swift:108-133`:

```swift
static func getCollisionData(_ entityA: PhysicsEntity, _ entityB: PhysicsEntity) -> CollisionData {
    switch (entityA.collisionShape, entityB.collisionShape) {
        case (.Sphere, .Sphere):
            let unormCV = Self.getUnnormalizedCollisionVector(entityA.getPosition(), entityB.getPosition())
            let penetrationDepth = Self.getPenetrationDepth(
                ballA: entityA as! SpherePhysicsEntity,
                ballB: entityB as! SpherePhysicsEntity, ...)
            ...
```

### After

```swift
// New file: ToyFlightSimulator Shared/Physics/World/PhysicsStores.swift

struct SphereStore {
    var entityIDs:    ContiguousArray<EntityID> = []   // bridge back to Node/GameObject
    var positions:    ContiguousArray<float3>   = []
    var velocities:   ContiguousArray<float3>   = []
    var accelerations: ContiguousArray<float3>  = []
    var masses:       ContiguousArray<Float>    = []
    var radii:        ContiguousArray<Float>    = []
    var restitutions: ContiguousArray<Float>    = []
    var flags:        ContiguousArray<PhysicsFlags> = []   // isStatic | shouldApplyGravity packed

    @inline(__always) var count: Int { positions.count }
}

struct PlaneStore {
    var entityIDs:    ContiguousArray<EntityID> = []
    var positions:    ContiguousArray<float3>   = []
    var normals:      ContiguousArray<float3>   = []
    var restitutions: ContiguousArray<Float>    = []
    // Planes are typically static, no velocity column.
}

final class PhysicsWorld {
    var spheres = SphereStore()
    var planes  = PlaneStore()

    func update(deltaTime: Float) {
        // Solver runs over concrete arrays — no protocol dispatch.
        EulerSolver.step(&spheres.positions, &spheres.velocities,
                         accelerations: spheres.accelerations,
                         masses: spheres.masses,
                         flags: spheres.flags,
                         gravity: PhysicsWorld.gravity,
                         dt: deltaTime)
        // Broad-phase over a single concrete shape is cleanly SIMD-vectorizable.
        let pairs = broadPhase.sweep(positions: spheres.positions, radii: spheres.radii)
        HeckerCollisionResponse.resolveSphereSphere(
            &spheres.positions, &spheres.velocities,
            radii: spheres.radii, restitutions: spheres.restitutions,
            masses: spheres.masses, flags: spheres.flags,
            pairs: pairs, dt: deltaTime)
        HeckerCollisionResponse.resolveSpherePlane(
            &spheres.positions, &spheres.velocities,
            radii: spheres.radii, restitutions: spheres.restitutions,
            flags: spheres.flags,
            planePositions: planes.positions, planeNormals: planes.normals,
            planeRestitutions: planes.restitutions,
            dt: deltaTime)
    }
}
```

The solver becomes a free function over arrays:

```swift
enum EulerSolver {
    static func step(_ positions: inout ContiguousArray<float3>,
                     _ velocities: inout ContiguousArray<float3>,
                     accelerations: ContiguousArray<float3>,
                     masses: ContiguousArray<Float>,
                     flags: ContiguousArray<PhysicsFlags>,
                     gravity: float3,
                     dt: Float)
    {
        let n = positions.count
        positions.withUnsafeMutableBufferPointer { p in
        velocities.withUnsafeMutableBufferPointer { v in
        accelerations.withUnsafeBufferPointer     { a in
        flags.withUnsafeBufferPointer             { f in
            for i in 0..<n where !f[i].contains(.isStatic) {
                let totalAccel = a[i] + (f[i].contains(.shouldApplyGravity) ? gravity : .zero)
                v[i] += totalAccel * dt
                p[i] += v[i] * dt
            }
        }}}}
    }
}
```

After `PhysicsWorld.update`, a syncback step copies the new positions onto the entity transforms:

```swift
// Inside SceneManager.Update, after physics runs
for i in 0..<world.spheres.count {
    transformStore.positions[transformStore.indexOf(world.spheres.entityIDs[i])!]
        = world.spheres.positions[i]
    transformStore.localDirty[…] = true
}
```

### Why this matters

- The existing `for var entity in entities { entity.reset() }` loop (`PhysicsWorld.swift:47`) is doing a *value copy* of an existential every iteration because of `for var` and the protocol type. That's a hidden allocation per entity per frame.
- The `as!` casts inside the collision data path are ~50 ns each; for 100 collision-pair candidates that's 10 µs per frame purely wasted.
- The broad-phase sweep already wants to be on arrays — see `BroadPhaseCollisionDetector.update(entities:)`. After this refactor, it's natively on concrete arrays.

### Risks and mitigations

- **The `CollidableF22 : F22, SpherePhysicsEntity` hierarchy currently encodes physics-state-on-GameObject.** During this phase, keep `Aircraft` and `CollidableF22` as the public API for spawning, but their initializer registers in the `SphereStore` and stores its `entityID`. The `mass`, `velocity`, etc. properties on `Aircraft` become passthroughs into `SphereStore`.
- **Static vs dynamic skip.** The current code has `isStatic`/`shouldApplyGravity` as separate `Bool` fields. Pack them into `PhysicsFlags: OptionSet`. A `where !f[i].contains(.isStatic)` branch is a hot branch, but with `OptionSet` the check compiles to a single `and; bne` — predictor handles it well as long as most entities are dynamic (the typical case in TFS).
- **Plane-plane collisions** (currently no-op) stay no-op.

### Measurement gate

- `update.physics` signpost should drop.
- The Allocations instrument should show no allocations inside `PhysicsWorld.update`.
- Counters: branch misprediction inside `EulerSolver.step` should be < 2% (was higher because of the existential dispatch).

---

## Phase 4 — Lightweight Component Registry

**Goal:** Introduce a real ECS skeleton — `EntityID`, `World`, `ComponentStore<T>` — without forcing everything to migrate. New features land in components. Animation channels move first because they expose the most visible pain (the `for case let channel as ProceduralAnimationChannel in layer.channels` pattern).

### Before

`AircraftAnimator.swift:39` and `:220`:

```swift
class AircraftAnimator: AnimationController {
    internal var layerSystem: AnimationLayerSystem?
    ...
    func rollAilerons(value: Float) {
        guard let layer = aileronLayer else { ... }
        for case let channel as ProceduralAnimationChannel in layer.channels {
            channel.setValue(value)
        }
    }
}
```

Each `Aircraft` has its own animator, layer system, and array of channels. There's no way to add a new control surface without subclassing `AircraftAnimator` and adding a new channel.

### After

```swift
// New file: ToyFlightSimulator Shared/Core/ECS/World.swift

struct EntityID: Hashable {
    let index: UInt32
    let generation: UInt32
    static let invalid = EntityID(index: .max, generation: .max)
}

/// Sparse-set storage: O(1) lookup, O(1) add/remove. Good for "may or may not have"
/// components like ProceduralChannel, RadarTrack, Fuel.
final class ComponentStore<T> {
    private(set) var dense:  ContiguousArray<T> = []
    private(set) var owners: ContiguousArray<EntityID> = []
    private var sparse: [UInt32: Int] = [:]   // entity.index -> dense idx

    @inline(__always) func get(_ e: EntityID) -> T? {
        guard let i = sparse[e.index], owners[i] == e else { return nil }
        return dense[i]
    }
    func set(_ e: EntityID, _ value: T) {
        if let i = sparse[e.index], owners[i] == e {
            dense[i] = value
        } else {
            sparse[e.index] = dense.count
            dense.append(value)
            owners.append(e)
        }
    }
    func remove(_ e: EntityID) { ... } // swap-and-pop
}

final class World {
    var transforms = TransformStore()
    var spheres    = SphereStore()
    var planes     = PlaneStore()
    var proceduralChannels = ComponentStore<ProceduralChannelData>()
    var binaryChannels     = ComponentStore<BinaryChannelData>()
    // New features go here:
    // var radarTracks = ComponentStore<RadarTrackData>()
    // var fuelTanks   = ComponentStore<FuelTankData>()
}
```

Channels become pure data:

```swift
struct ProceduralChannelData {
    var jointIndex:    Int32
    var axis:          float3
    var deflectionMin: Float
    var deflectionMax: Float
    var currentValue:  Float      // -1...1 input, mapped via min/max
    var ownerEntity:   EntityID
    var groupID:       UInt16     // for "all left-aileron channels", etc.
    var mirrored:      Bool
}

enum ProceduralChannelSystem {
    static func setGroup(_ world: World, group: UInt16, value: Float) {
        // Walk the dense column once — no protocol dispatch, no `for case let`.
        for i in 0..<world.proceduralChannels.dense.count {
            if world.proceduralChannels.dense[i].groupID == group {
                world.proceduralChannels.dense[i].currentValue = value
            }
        }
    }

    static func evaluate(_ world: World, into transforms: inout TransformStore) {
        for i in 0..<world.proceduralChannels.dense.count {
            let ch = world.proceduralChannels.dense[i]
            // ...write into the skeleton joint matrix palette for ch.ownerEntity...
        }
    }
}
```

`AircraftAnimator` becomes a thin facade — it owns a list of `EntityID`s for its channels and dispatches to systems:

```swift
class AircraftAnimator: AnimationController {
    let ownerEntity: EntityID
    var aileronGroup: UInt16
    var flaperonGroup: UInt16
    // ...

    func rollAilerons(value: Float) {
        ProceduralChannelSystem.setGroup(world, group: aileronGroup, value: value)
    }
}
```

### Why this is a real ECS step, not just refactoring

- Adding a new control surface is now `world.proceduralChannels.set(newEntity, ProceduralChannelData(...))`. No subclass, no `AircraftAnimator` change.
- Adding a brand-new feature (radar, fuel, damage) is the same shape: a new `ComponentStore<X>` and a new system. Aircraft and other game objects opt in by registering.
- Systems compose: a `WeaponsSystem` can read `Fuel`, `Position`, and `RadarTrack` columns and act on entities that have all three, without any inheritance.

### Risks and mitigations

- **Mirroring bones (`flaperon-mirrored-bones.md`).** The current procedural channel code has a `mirrored` flag for the left-vs-right control surfaces. Keep that — it's a single bit in `ProceduralChannelData`. The mirrored axis flip happens inside `ProceduralChannelSystem.evaluate`.
- **Skeleton/skin coupling.** Channels write into `Skeleton.evaluateWorldPoses` for the owner entity. The bridge is `ownerEntity → EntityID → skeleton` lookup. Use a `ComponentStore<SkeletonHandle>` to hold that mapping.
- **Migration ergonomics.** During this phase, both the old per-Aircraft channel arrays *and* the new component store can coexist. F-22 / F-35 register channels into the world; older `Aircraft` subclasses keep their old `AircraftAnimator` storage until rewritten. The two paths are isolated.

### Measurement gate

- `update.animation` signpost should drop.
- The `swift_dynamicCast` / `_swift_class_getInstanceTypeID` lines should disappear from Time Profiler's hot stacks.

---

## Phase 5 — Decision point

After Phases 0-4, profile the same scene and the same benchmark.

If the frame time is below the 8.33 ms / 120 FPS target with comfortable margin, **stop**. The remainder of the codebase (camera management, particle emitters, light manager) is not on a critical-mass hot path, and continuing to migrate them is a stylistic preference, not a perf win.

If the frame time is still over budget, profile again and identify the next biggest signpost. Likely candidates in priority order:

1. **Particle emitter update.** Currently a per-emitter loop, already partially DOD via the compute shader. Could move CPU-side state to a SoA.
2. **Camera attached-follow path.** `AttachedCamera.update()` recomputes `viewMatrix = modelMatrix.inverse` every frame; could be a SoA system over all attached cameras.
3. **Light manager.** Already array-based but mixes directional + point in a single `[LightObject]`. Split into concrete arrays.
4. **InputManager dictionary lookups.** Replace with `ContiguousArray<Float>` indexed by `ContinuousCommand.rawValue`.

Each candidate gets its own micro-plan with the same shape: before/after, measurement gate.

---

## Cross-cutting concerns

### Threading

The current update/render thread handshake uses `inFlightSemaphore` + `updateSemaphore` + `updateDoneSemaphore`. The SoA stores must respect the same invariants:

- The update thread *owns writes* to `TransformStore`, `SphereStore`, `PlaneStore`, and `ComponentStore`s.
- The render thread *only reads* from the per-frame ring buffer snapshots written by `writeFrameSnapshot`.
- The render thread *never reads `world.transforms.worldMatrices`* directly — only the ring-buffer column in `RingBufferRegion`.

This keeps the existing thread model intact. The SoA stores live on the update thread side of the boundary; the GPU side stays exactly the same.

### Hot/cold split

Several `GameObject` fields are touched zero or once per frame. After Phase 2's transform extraction, the remaining hot fields on `GameObject` are: `modelConstantsIndex` (Phase 1), `worldMatrixDirty` (a computed forward to the store). Everything else (`collidedWith`, `restitution`, `mass`, `model`, `id`) is touched far less often and is fine to keep on the class.

This matches Albrecht's hot/cold-split recommendation without forcing a separate "GameObjectHot" struct.

### Class vs struct

- `Node`, `GameObject`, `Aircraft` remain *classes*. They are identity-bearing handles — they need reference semantics for `==` on `id`, for the `parent: Node?` weak relationship in scene graphs, and for the `hasFocus` mutable state.
- `TransformStore`, `SphereStore`, `PlaneStore`, `ComponentStore<T>` are *classes* (single owner per `World`).
- The *element types* in those stores — `float3`, `float4x4`, `ProceduralChannelData`, `ModelConstants` — are *structs* with no inheritance. SoA is only a real DOD win when the element type is a struct, because Swift's COW + ARC overhead on class arrays defeats the purpose.

### Backward compatibility

All five phases preserve the public API of `Node`, `GameObject`, and `Aircraft`. Scenes don't need to change. The `aircraft.setPosition(x, y, z)` style of construction in `FlightboxScene.buildScene` continues to work.

This is intentional. The refactor is structural, not API-breaking. If a phase forces a public API change, that's a signal to stop and re-think the phase boundary.

### File and folder layout

New files introduced by this plan:

```
ToyFlightSimulator Shared/
  Core/
    ECS/
      EntityID.swift
      World.swift
      ComponentStore.swift
      TransformStore.swift
  Physics/
    World/
      PhysicsStores.swift      // SphereStore, PlaneStore
  Utils/
    PerfSignposts.swift
investigations/claude/perf/
  baseline_2026-05-13.md
  phase1_<date>.md
  ...                          // one file per measurement gate
```

No existing folder structure changes.

---

## Risk summary

| Risk | Likelihood | Mitigation |
|---|---|---|
| Phase 2 transform ordering invariant violated by re-parenting | Medium | `rebuildOrder()` whenever a node is reparented; assert depth monotonicity in DEBUG |
| Phase 3 plane-sphere collision math differs subtly after extraction | Medium | Side-by-side test scene (`PhysicsStressTestScene`) — diff sphere trajectories vs baseline |
| Phase 4 channel evaluation timing changes break F-22 / F-35 animations | Medium | Visual comparison frame-by-frame; the existing animation tests still pass |
| Hidden allocations from `ContiguousArray.append` triggering re-allocs | Low | `reserveCapacity` aggressively at scene construction |
| Counter availability changes per chip generation | Low | Document M1/M2/M3/M4 counter names in the perf doc; fall back to Time Profiler if Counters unavailable |
| Refactor stalls partway | Medium | Each phase is independently shippable; stopping after any phase leaves a strict improvement |

## What stays the same

- The Metal render pipeline. Every renderer (`SinglePassDeferredLighting`, `TiledDeferred`, `TiledMSAA*`, `OrderIndependentTransparency`) is untouched.
- The ring-buffer + triple-buffered snapshot model from the previous render-stuttering work.
- The `Engine.Start` / `Engine.MetalView` boot sequence.
- All shaders (`.metal` files).
- All asset loading (`ModelLibrary`, `MeshLibrary`, `TextureLibrary`, `Material`).
- Scene construction APIs (`addChild`, `addCamera`, `addLight`, `addGround`).
- The XCTest and Swift Testing suites (math, utils, asset pipeline). They keep passing without modification.

The DOD refactor lives entirely in the *update-side data layout*. The renderer side already had the right shape; this plan teaches the rest of the engine to match it.
