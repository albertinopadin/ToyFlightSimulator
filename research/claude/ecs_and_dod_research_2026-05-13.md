# ECS & Data-Oriented Design Research

**Date:** 2026-05-13
**Goal:** Evaluate Entity Component System (ECS) and Data-Oriented Design (DOD) as a refactor target for ToyFlightSimulator (TFS). The objective is sustained 120 FPS on Apple Silicon and easier feature composition (physics, animation, AI, etc.) on `GameObject`-like things, with the smallest viable disruption to the current Metal renderer.

This document is research only — the concrete refactor is in `plans/claude/ecs_and_dod_refactor_2026-05-13.md`.

---

## Executive Summary

1. **ECS is one specific instance of DOD.** DOD is the broader principle — "organize code around how the data is *transformed*, not how it is *modeled*." ECS is the most popular concrete shape DOD takes in game engines, but you can get most of DOD's wins without committing to a full ECS framework.

2. **TFS already has the DOD bones, half-built.** `SceneManager` already keeps `ContiguousArray<GameObject>` per `Model`. `DrawManager` already writes a contiguous `ModelConstants` column into a ring buffer. Triple-buffered snapshots already decouple update from render. The big wins from a refactor come from finishing what the rendering side started and pushing the same shape into physics, animation, transforms, and input.

3. **The pain points are concentrated, not spread.** Three structures account for most of the unnecessary indirection on the per-frame hot path: (a) `Node.children: [Node]` recursive traversal with virtual `update()`, (b) `PhysicsWorld.entities: [PhysicsEntity]` (a protocol existential array), (c) per-`Aircraft` `animator?` optional chains and `for case let channel as ProceduralAnimationChannel in layer.channels` casts.

4. **Apple Silicon strongly rewards SoA.** The M-series cache line is 128 bytes (twice typical x86 64-byte lines), the L1D on P-cores is enormous (128 KB), and the hardware prefetcher handles linear strides well. Sequential SoA scans benefit disproportionately on this hardware.

5. **The recommended path is hybrid and incremental.** Keep `GameObject` as an identity handle. Lift hot-loop state (transforms, physics, animation channel values) into SoA column stores indexed by a stable `EntityID`. Add a small archetype-style component registry where new composability features will live (weapons systems, AI, sensors). Don't migrate everything — only the things that show up in Instruments.

The rest of this doc supports those five claims with primary-source research and concrete file-level evidence from the codebase.

---

## Part 1 — Entity Component System

### 1.1 Canonical definition

The canonical decomposition (Wikipedia, UML Board, Austin Morlan, Sander Mertens' ECS FAQ) is the same three nouns everywhere:

- **Entity** — a stable unique identifier (typically a 32- or 64-bit integer). It carries *no behavior and no data of its own*. It is a name for "the thing this row of components belongs to."
- **Component** — pure data. A POD struct. No methods that mutate game state, no virtual dispatch. A component characterizes *one aspect* of an entity (e.g., `Transform`, `Velocity`, `Health`).
- **System** — a free function (or function-shaped object) that iterates over all entities that own a particular *set* of components, and transforms that data. Systems hold no per-entity state.

What ECS rejects: the Unity/`GameObject`–`MonoBehaviour` shape where a "component" is a class with its own `Update()` method and an `Awake()` lifecycle. The Wikipedia article calls that pattern "component object" specifically to distinguish it from ECS, which it labels a "true ECS." Apple's GameplayKit is in the same camp as Unity's old `MonoBehaviour` — `GKComponent` is a class with a virtual `update(deltaTime:)`, and `GKComponentSystem<ComponentType>` exists exactly to recover the iteration-by-component-type benefit that pure ECS gives you for free.

### 1.2 Storage strategies

This is where the architectural decisions live, and where every ECS library differs. Three families dominate:

#### 1.2.1 Array-per-component-type (the "Austin Morlan" model)

Each component type owns one `[Component; MAX_ENTITIES]` dense array and an entity→index map. Systems iterate by walking the densest of the required components and checking membership in the others.

- **Used by:** EnTT (sparse-set variant), Shipyard, the tutorial implementations.
- **Pros:** O(1) component add/remove; tight per-component-type cache locality; very simple to implement; no migration cost when adding/removing components.
- **Cons:** Cross-component iteration is slower (more pointer chasing) because each entity may live at a different dense index in each component's array. False sharing risk under multi-threading.

#### 1.2.2 Archetype tables (the "Bevy/DOTS/flecs/Hecs" model)

Entities are grouped by their *exact* component set. All entities with `{Transform, Velocity}` live in one "archetype table"; entities with `{Transform, Velocity, Damage}` live in a *different* table. Inside each table, each component is a contiguous SoA column.

- **Used by:** Unity DOTS, Bevy ECS, flecs, Hecs (Rust), Legion (Rust), Unreal Mass.
- **Pros:** Once you locate the archetype, iteration is pure linear stream — fastest possible iteration, easy SIMD/auto-vectorization, parallelism is straightforward (each table is independent).
- **Cons:** Adding/removing a component on a live entity forces a **migration** (copy all of its component values into a new archetype). "Archetype explosion" can happen with many independent flags. Hierarchies (parent/child) become awkward because moving between archetypes invalidates references.

#### 1.2.3 Hybrid (Bevy v4 / flecs v4)

Most mature ECS libraries are now hybrids: archetype storage by default, sparse-set storage for "flag-like" components that toggle often (so the entity doesn't have to migrate every time the flag changes). flecs v4.1 calls this a `DontFragment` trait on a component; Bevy has a similar opt-in.

#### 1.2.4 Concrete trade-off numbers (from the ecs-faq author, Sander Mertens)

Quoted from ECS-FAQ research:

| Operation | Archetype | Sparse-Set |
|---|---|---|
| Iterate 1000 entities, 2 components | ~3–5× faster | branch-mispredict per entity |
| Add component to existing entity | ~100 µs (1k-entity table copy) | ~0.1 µs |
| Memory overhead | Per-table metadata, page-aligned | One sparse-id array per component |
| Multi-thread per-archetype split | Trivially parallel | Needs cache-line padding |

The right answer for TFS is: **archetype-style storage for things that don't change shape (a `Transform/PhysicsBody/Renderable` triple is the same for an aircraft's whole lifetime), sparse-set storage for things that toggle (an `IsBurning`, `HasFocus`, `GearDown` flag).** TFS doesn't currently have the latter category as proper components — those flags live as `Bool` fields on `GameObject`. The refactor can introduce them properly.

### 1.3 ECS in practice: filtering and dispatch

Every ECS implementation has the same shape for systems:

```
fn physics_system(query: Query<(&mut Transform, &Velocity, Without<Frozen>)>) {
    for (transform, velocity) in query { ... }
}
```

The query is a *compile-time-resolved* signature (a bitmask over component types). The framework's job is to (a) find every archetype/storage that matches the signature, and (b) hand the system a tight iterator over just those rows. The system body has no `if entity.has(...)`, no `as!` casts, no virtual dispatch. This is the single biggest correctness win of ECS — you cannot accidentally touch state you didn't declare, and the type system guarantees no two parallel systems write the same column.

### 1.4 What TFS doesn't need from a full ECS

A flight-sim with on the order of 10²–10³ active game objects (not 10⁵ as in big open-world games) doesn't need:

- A full archetype migration engine.
- A scheduler that auto-parallelizes systems based on read/write sets.
- Persistent serialization of components.
- Hot reloading / scripting integration.

What it *does* need, and what the rest of this document and the refactor plan focus on:

- SoA storage for the things that are iterated every frame.
- A stable `EntityID` so external storage (Metal buffers, debug overlays, save state) can refer to "that aircraft" without holding a strong reference.
- A way to *compose* features (physics + animation + control surfaces) without forcing them into the `Aircraft` class hierarchy.

---

## Part 2 — Data-Oriented Design

### 2.1 The premise

The seminal DOD references — Tony Albrecht's "Pitfalls of Object-Oriented Programming" (GCAP 2009), Mike Acton's "Data-Oriented Design and C++" (CppCon 2014), and the Wikipedia summary — all start from the same hardware observation:

> *Between ~1980 and ~2010, CPU speed scaled ~1000×, RAM latency scaled less than 10×.* Albrecht cites 1-cycle RAM in 1980 vs 400+ cycle RAM in 2009. The figure is *worse* in 2026 on Apple Silicon if you measure in absolute cycles, because the cores are faster — main-memory latency on M-series is ~95 ns, which at 3.5 GHz is ~330 cycles.

The consequence: **a function that misses cache is paying 100s of cycles to do *nothing*.** The actual arithmetic is essentially free in comparison. The whole point of DOD is to organize data so that the cache works *for* you, not against you.

### 2.2 Tony Albrecht's "Pitfalls" — the load-bearing numbers

This is Albrecht's running scene-graph example, which is directly analogous to TFS's `Node` tree:

- Baseline: 11,111 nodes, 5 levels deep, recursive `Node::update()` with virtual dispatch.
- Traversal-only time: **22 ms**.
- Per-object cost breakdown: **3 L2 cache misses average**, each ~400 cycles. 50,421 branch mispredictions across the run, 23 cycles each.
- The *dirty-flag check itself* was slower than recomputing the value, because the branch was unpredictable: 23–24 cycles to check vs 12 cycles to do the work.

Albrecht's transformations:

1. **Contiguous allocation per hierarchy level.** Move the storage so all nodes at depth 0 are adjacent in memory, all nodes at depth 1 are adjacent, etc. Result: 19.6 → 12.9 ms (~35% improvement) with zero algorithmic change.
2. **Replace recursive virtual-dispatch traversal with two linear array passes.** Top-down pass computes world transforms level-by-level; bottom-up pass accumulates bounding spheres. Result: 12.9 → 4.8 ms — **~4× total speedup** versus the baseline OOP shape.

The takeaways Albrecht packages for the audience:

- **Homogeneous sequential data is the entire point.** A hardware prefetcher cannot help you if your next byte is in a random location. It *can* help you if your next byte is the next byte.
- **Hot/cold split.** Inside a class, separate the fields touched every frame from the fields touched occasionally. The hot fields should be a tight struct, the cold fields should live elsewhere. (A `Node` with 12 hot fields and 30 cold fields wastes 70% of every cache line it loads.)
- **Sort by frequency of use.** Inside a loop, the fields read first should be near the start of the struct.
- **Eliminate branches in inner loops where possible.** Mispredicted branches cost more than the work they were trying to avoid.

### 2.3 Mike Acton's "DOD and C++" — the principles

Acton's 2014 CppCon talk is the canonical hour-long argument for DOD as a discipline. Two core claims:

1. **Code's only purpose is to transform data.** Therefore design around the transformation, not the type hierarchy.
2. **The "single" case is the wrong one to design for.** Design for the *plural* case — "how do I update 10,000 of these?" — because that's the case the hardware is built to do quickly.

Acton's commonly-cited corollaries:

- "If you have one, you'll have more than one. You probably already do." (One Player implies one PlayerArray.)
- "Different data is different. Don't lie about it." (Don't hide a flag in a base class — make it explicit so the layout is honest.)
- The "10× speedup" claim: he demonstrates, in the talk, that restructuring a typical `Animal` class into SoA gives a ~10× speedup *with no algorithmic improvement*, just from cache-line utilization changing from ~10% to ~95%.

### 2.4 AoS vs SoA, with TFS's `ModelConstants` as the worked example

TFS's `ModelConstants` (`TFSCommon.h:26-31`):

```c
typedef struct {
    matrix_float4x4 modelMatrix;   // 64 B
    matrix_float3x3 normalMatrix;  // 48 B (3 × packed float3, with padding)
    simd_float4 objectColor;       // 16 B
    bool useObjectColor;           // 1 B
} ModelConstants;                  // stride aligns to ~128 B
```

This is an **Array-of-Structures (AoS)** layout: TFS stores `ModelConstants[N]`. For a shader binding that consumes one `ModelConstants` per draw-instance, AoS is correct — that's what the GPU vertex stage wants.

But on the **CPU side**, during the per-frame update, the code does this (`DrawManager.swift:83-85`):

```swift
let dst = ringBuffer.contents().advanced(by: alignedOffset)
    .assumingMemoryBound(to: ModelConstants.self)
for i in 0..<count {
    dst[i] = gameObjects[i].modelConstants
}
```

This loop walks `gameObjects[i]`, fetches `modelConstants` (~128 B) from each class instance's heap location, and writes the whole struct to the ring buffer. Each `gameObjects[i]` is a `GameObject` *class* — Swift loads a pointer, follows it to a heap object, walks past the ARC retain count, then reads `modelConstants`. Each iteration is at least one pointer chase + one cache miss per instance for the modelConstants. With ~30 game objects, that's ~30 cache misses (~10 µs at 330 cyc/miss / 3.5 GHz).

The "SoA-on-CPU, AoS-at-the-GPU-boundary" structure is a textbook DOD shape:

```swift
// SoA: arrays per field, cache-friendly to update.
var modelMatrices:  ContiguousArray<float4x4>
var normalMatrices: ContiguousArray<float3x3>
var objectColors:   ContiguousArray<float4>
var useObjectColor: ContiguousArray<Bool>

// Once per frame: pack into AoS ModelConstants ring buffer in one tight loop.
for i in 0..<n {
    dst[i] = ModelConstants(modelMatrices[i], normalMatrices[i],
                            objectColors[i], useObjectColor[i])
}
```

This is the **only-transformation-is-AoS-at-the-end** pattern. Most "DOD wins" you see on benchmarks come from exactly this shape.

### 2.5 What DOD doesn't help

- Code paths that are already cold (initialization, scene load, asset import).
- Code that's GPU-bound, not CPU-bound. If the M-series GPU is the bottleneck, restructuring CPU data won't move FPS.
- Code with low instance count. Restructuring 5 `Camera` instances into SoA won't change anything measurable.

This is why the plan starts with measurement.

---

## Part 3 — Apple Silicon Specifics

Most DOD literature is written for x86 (and 2009-era consoles). Apple Silicon's microarchitecture changes some of the numbers and a few of the conclusions. The relevant facts (M1; M2/M3/M4 numbers are similar with monotonic improvements):

| Property | P-core (Firestorm/Avalanche/...) | E-core (Icestorm/...) |
|---|---|---|
| L1 instruction cache | 192 KB | 128 KB |
| L1 data cache | **128 KB** | 64 KB |
| L2 (shared per cluster of 4) | 12 MB | 4 MB |
| System-Level Cache (SLC) | 8–24 MB depending on SKU | shared |
| L1 latency | 3–4 cycles | similar |
| L2 latency | ~18 cycles | similar |
| Memory latency | ~91 ns (~320 cyc @ 3.5 GHz) | similar |
| HW prefetcher | Yes — handles streaming patterns | Yes |
| Cache line size | **128 bytes** (L2/L3); L1 documented as 64 B but the prefetcher operates on 128 B lines | same |

Source: 7-cpu.com M1 page, Anandtech M1 deep-dive, Wikipedia Apple M1.

What this means for TFS:

1. **The L1D on a P-core is 128 KB.** That is *enormous* by historical standards. A SoA array of 1000 `float4x4` matrices is 64 KB — half the L1D. A whole frame's worth of transform updates fits in L1 if the data is laid out densely. This is a strong argument for committing to SoA.
2. **The cache line is effectively 128 B for streaming.** When you stream sequentially, the prefetcher pulls 128 B at a time. A `float4x4` is exactly 64 B. Two matrices per line. Per-field SoA (just `simd_float3` positions, say) packs 8 positions per line.
3. **The hardware prefetcher is aggressive on linear strides.** If you walk `positions[0], positions[1], positions[2], ...` it will prefetch ahead by ~400 cycles, masking memory latency entirely. If you walk `gameObjects[0].position, gameObjects[1].position, ...` where `gameObjects[i]` is a class reference, the prefetcher can't help — it sees pointer dereferences with no pattern.
4. **NEON SIMD is 128 bits wide.** Swift's `simd_float4` is a single NEON register. There's no AVX-512-style 512-bit SIMD on Apple Silicon, so the SIMD win from SoA isn't as dramatic as on x86 with AVX, but `float4` operations are still free and `simd_float4x4 *= simd_float4x4` is heavily optimized.
5. **P-cores vs E-cores.** TFS's hot threads (render thread, update thread) should both run on P-cores. macOS scheduler will usually do this automatically for high-QoS work, but `DispatchQueue.global(qos: .userInteractive)` (or `Thread` with appropriate QoS) ensures it. The E-cores are a poor place to put the per-frame update.
6. **Unified memory model.** CPU and GPU share physical memory. Metal `storageModeShared` buffers are CPU-writable and GPU-readable with no copy. TFS's ring buffer already uses this. That means a SoA layout on the CPU that gets packed into AoS for the GPU pays *zero* upload cost — it's just a memcpy within the same address space.

The most concrete Apple-Silicon-specific recommendation: **target 128 B alignment for hot SoA arrays, not 64 B.** Use `ContiguousArray` (which guarantees contiguous storage even with class element types) and where possible use value-type elements so the array's storage *is* the data, not pointers to data.

---

## Part 4 — Current TFS Analysis

This section maps the research to specific files and lines so the refactor plan can be precise.

### 4.1 The `Node` recursion

**Files:** `ToyFlightSimulator Shared/GameObjects/Node.swift` (whole file), `GameObject.swift`.

`Node` is a class. `Node.children: [Node]` is an Array of class references. `Node.update()` recurses through `for child in children { child.update() }`. Each step is:

1. Fetch `children[i]` (Array's storage is contiguous, so the pointer load is cheap).
2. Dereference the class pointer to reach the heap object. **Random-access pointer chase. ~1 cache miss per node** if the heap allocator didn't happen to put siblings together.
3. Virtual `update()` dispatch through Swift's witness table for class methods.
4. Read `_transformDirty`, `_position`, `_rotationMatrix`, `_scale`, `parentModelMatrix`, `_modelMatrix` — at least three cache lines on the heap object.
5. Compute child's `parentModelMatrix = self.modelMatrix` — but `modelMatrix` is a computed property that calls `matrix_multiply` on every get (`Node.swift:35-42`), even when nothing changed.

This is Albrecht's GCAP 2009 scene-graph example transplanted into Swift. The order-of-magnitude wins he documented apply here directly.

There is also a real bug to flag: `markTransformDirty()` short-circuits via `guard !_transformDirty else { return }` (`Node.swift:81`). If a parent is *already* dirty and then a child below it gets dirtied first via a different code path, the child's `markTransformDirty` walk stops at the dirty parent. The propagation depends on visit order. This is a side effect of the OOP shape — in a SoA design, "dirty" is just a column you sweep once per frame.

### 4.2 `GameObject` — fat base class

**File:** `ToyFlightSimulator Shared/GameObjects/GameObject.swift` (82 lines).

`GameObject` extends `Node` and adds, in one class:

- Physics state: `collidedWith: [String: Bool]`, `collisionShape`, `isStatic`, `shouldApplyGravity`, `mass`, `velocity`, `acceleration`, `restitution` — ~80 B
- Rendering: `model: Model` (a class reference), `modelConstants: ModelConstants` (~128 B inline), `instanceBufferIndex`
- Identity: `id: String`, `hasFocus: Bool`

Every `GameObject` instance carries ~300+ B of inline data. Many of those fields are touched zero times for many game objects (e.g., `collidedWith` for a static decorative cube). This is exactly the hot/cold-split antipattern Albrecht flags.

Worse, every protocol that `GameObject` adopts (`PhysicsEntity`, `Renderable`, `Hashable`, `ClickSelectable`) brings witness-table overhead the moment the object is stored in an existential container — which `[PhysicsEntity]` does (next section).

### 4.3 `PhysicsWorld.entities: [PhysicsEntity]` — the existential array

**File:** `ToyFlightSimulator Shared/Physics/World/PhysicsWorld.swift:22`, `PhysicsEntity.swift`.

```swift
private var entities: [PhysicsEntity]
```

`PhysicsEntity` is a `protocol`, not a concrete type. In Swift, `[PhysicsEntity]` is an array of **protocol existentials**. Each element is a 5-word existential box: typically 3 words of inline storage + a pointer to the value (boxed if larger) + a pointer to the protocol witness table. Every method call through a protocol existential is a witness-table dispatch — at least one extra indirection beyond a virtual call on a class.

The collision dispatch then does this (`PhysicsWorld.swift:108-133`):

```swift
case (.Sphere, .Sphere):
    let penetrationDepth = Self.getPenetrationDepth(
        ballA: entityA as! SpherePhysicsEntity,
        ballB: entityB as! SpherePhysicsEntity, ...)
```

`as!` is a forced cast through the existential's type metadata — it's not a free operation, and it runs *per pair per frame*. With N entities, broad-phase produces up to N pairs, each pair does 2 casts, each cast is ~50 ns on a cold path. For 100 entities and 50 pairs, that's ~10 µs of casting alone before any physics math happens.

A DOD version stores spheres and planes in *concrete-typed* SoA arrays:

```swift
struct SpherePhysicsStore {
    var positions:  ContiguousArray<float3>
    var velocities: ContiguousArray<float3>
    var radii:      ContiguousArray<Float>
    var restitutions: ContiguousArray<Float>
    var entityIDs:  ContiguousArray<EntityID>
}
```

Sphere-sphere collision now iterates `(spheres.positions[i], spheres.radii[i])` against `(spheres.positions[j], spheres.radii[j])` with no protocol dispatch, no boxing, and full SIMD opportunity.

### 4.4 `SceneManager` — already half-DOD

**File:** `ToyFlightSimulator Shared/Managers/SceneManager.swift`.

This is the file with the most existing DOD shape, and the one the refactor will lean on:

- `modelDatas: [Model: ModelData]` — dictionary, **per-Model** batching (line 93).
- Inside each `ModelData`: `gameObjects = ContiguousArray<GameObject>()` (line 44) — already a contiguous array.
- `writeFrameSnapshot()` (lines 193-253) — writes directly into the per-frame ring buffer.
- Triple-buffered `opaqueSnapshots`, `transparentSnapshots`, `skySnapshots` (lines 104-106).

What's already correct here: the *batching* is per Model (instanced rendering), and each batch is iterated as a contiguous array. The render thread reads from a triple-buffered snapshot, eliminating locks.

What's still inefficient here:

- `modelDatas` is a dictionary keyed by class reference. Per-frame iteration is `for (model, modelData) in modelDatas`. Dictionary iteration order is non-deterministic and the keys are class pointers (so no cache locality between successive iterations).
- Inside the inner loop `for i in 0..<count { dst[i] = gameObjects[i].modelConstants }`, each `gameObjects[i]` is a class reference → pointer chase.

The fix is described in the plan, but conceptually: move `ModelConstants` storage off the `GameObject` instance into a parallel `ContiguousArray<ModelConstants>` per Model. Then the inner loop is `dst[i] = constants[i]` — pure linear stream.

### 4.5 Aircraft + Animator — protocol-of-protocol indirection

**Files:** `Aircraft.swift`, `AircraftAnimator.swift`, `Animation/Layers/`.

Each `Aircraft` carries an optional `animator: AircraftAnimator?`. Each animator holds an `AnimationLayerSystem?`. Each layer holds `channels: [AnimationChannel]` where `AnimationChannel` is a protocol. Each `update(deltaTime:)` walks:

```
aircraft.doUpdate
  → animator?.update(deltaTime:)            // optional chain
    → layerSystem?.update(deltaTime:)       // optional chain
      → for layer in layers { layer.update() }    // class iteration
        → for channel in layer.channels { channel.update() }    // protocol existential iteration
```

For F-22-style aircraft with multiple control surfaces (left/right ailerons, flaperons, two stabilators, rudder = ~6 channels per layer × 5 layers ≈ 30 channels), this is 30 protocol existential dispatches per aircraft per frame. With 4 aircraft, 120 dispatches/frame ≈ 7200/s. Each is ~2-3 cache misses through the protocol metadata.

The control-surface channel storage is also notable. `AircraftAnimator.rollAilerons(value:)` does (`AircraftAnimator.swift:220`):

```swift
for case let channel as ProceduralAnimationChannel in layer.channels {
    channel.setValue(value)
}
```

That's a `for case let ... as ...` filter — a runtime type check per element. For control surfaces this is fine (they get checked a handful of times per frame), but it indicates the data model: heterogeneous channels in a single array, identified by runtime type. SoA would split this into concrete homogeneous arrays.

### 4.6 Input — dictionary lookups

**File:** `Managers/InputManager.swift`.

`InputManager.ContinuousCommand(.Roll)` is a static function that does dictionary lookups under the hood (`keysPressed[keyCode]`, `controllerDiscreteState[...]`, etc.). Each `Aircraft.doUpdate` calls this **five times** per frame (`Aircraft.swift:56-61`: Roll, Pitch, Yaw, MoveFwd, MoveSide). With 4 aircraft, that's 20 dictionary lookups per frame. Each `Dictionary<Keycodes, Bool>` lookup is ~30 ns — total ~600 ns/frame. Not a hotspot, but a simple SoA fix exists: `commandValues: ContiguousArray<Float>` indexed by `ContinuousCommand.rawValue`.

### 4.7 Summary: where the wins are

Ranked by likely Instruments-visible benefit:

| Area | Win source | Estimated ms/frame saved on a typical scene |
|---|---|---|
| `Node` recursive update (transform hierarchy) | Linear SoA passes per depth level (Albrecht's transform) | 0.5–2.0 |
| `[PhysicsEntity]` existential array | Concrete SoA per shape | 0.1–0.5 |
| `gameObjects[i].modelConstants` per-frame copy | SoA columns of modelConstants | 0.1–0.3 |
| Animation channel protocol dispatch | Concrete-typed channel SoA per layer | 0.05–0.2 |
| Input dictionary lookups | Array-indexed command cache | 0.001–0.01 |

These numbers are speculative until measured; they're sized from Albrecht's documented gains scaled down for TFS's much smaller object count. The plan calls for measurement before *and* after each phase.

---

## Part 5 — Measurement Strategy

A DOD refactor that isn't measured is a stylistic preference, not an engineering decision. Here is what to measure and how.

### 5.1 Frame-time baselines

Before any work:

1. Set Xcode's scheme to **Release** configuration with `-O` optimization (Swift compile flags) and `-Os` for objc/C code.
2. Lock target framerate to `120 fps` via `MTKView.preferredFramesPerSecond = 120`.
3. Add `os_signpost` intervals around the major frame phases. The existing `GameStatsManager` can be extended; the categories that matter are:
   - `update.scene` (input poll → scene graph update → snapshot write)
   - `update.physics` (PhysicsWorld.update if active)
   - `update.animation` (animator updates)
   - `render.shadows`, `render.gbuffer`, `render.lighting`, `render.transparency`, `render.composite`
4. Profile with **Instruments → Game Performance template**. This gives you CPU, GPU, signpost, and Metal-pipeline views simultaneously.

### 5.2 CPU counters — the DOD-specific measurements

Open Instruments → File → Recording Options → add a **Counters** instrument. On Apple Silicon, configure these counters (names vary slightly by chip generation):

- `FIXED_INSTRUCTIONS` / `FIXED_CYCLES` → **IPC** (instructions per cycle). Target ≥ 2.5 on hot inner loops. SoA inner loops on M-series can reach 4+.
- `L1D_CACHE_MISS` / `L1D_CACHE` → L1 D miss rate. Target < 5% on tight loops.
- `L2_CACHE_MISS` / `L2_CACHE` → L2 miss rate. Target < 1% on streaming loops; the prefetcher should keep nearly everything in L1.
- `INST_BRANCH` / `BRANCH_MISP` → branch misprediction rate. Target < 2%. The dirty-flag-vs-recompute decision Albrecht flagged shows up here.

Per Apple's WWDC2025 "Optimize CPU performance with Instruments" guidance, also record **Time Profiler** alongside Counters so you can correlate hot stacks with hot misses.

### 5.3 Metal GPU counters

Capture a frame with Xcode's Metal frame debugger and open **GPU Counters**. The numbers to track:

- **GPU utilization** (target > 80% if the goal is "GPU-bound at 120 fps") or **< 50%** (if the goal is "CPU is the bottleneck, leave GPU headroom").
- **ALU occupancy** in compute encoders (particles, broad-phase if it ever moves to GPU).
- **Vertex shader cycles / Fragment shader cycles** per pipeline state, to verify a refactor doesn't accidentally change pipeline switching behavior.
- **Tile memory bandwidth** for the tiled deferred renderers — should stay constant; the DOD refactor is CPU-side and shouldn't change render-pass shape.

A pre-refactor frame capture is the baseline. After every refactor phase, capture again and diff.

### 5.4 Allocations

Run **Instruments → Allocations** (or "Swift Allocations" in newer Xcodes) with the "VM Tracker" instrument and watch for:

- Steady-state allocation rate per frame. The render-stuttering investigation in `investigations/claude/render-thread-stuttering-research.md` already established that 60 dict + ~300 array allocations per second from `GetUniformsData` caused stutter. The DOD refactor should not regress this.
- Any new `[PhysicsEntity]` boxed-storage allocations (these will show up as small Heap allocations every frame).

### 5.5 Comparing iterations — the discipline

For each phase of the refactor:

1. Record a 10-second profile on a fixed scene (`FlightboxWithPhysics` is a good test scene — it has aircraft, ground, and active physics).
2. Save the `.trace` to `investigations/claude/perf/` with the phase name and date.
3. Diff the metrics that should change (the ones targeted by the phase) and verify the metrics that should *not* change are flat.
4. Only proceed to the next phase if the current phase's win is measurable and no regression appeared.

---

## Part 6 — Recommended Direction (preview of the plan)

The plan in `plans/claude/ecs_and_dod_refactor_2026-05-13.md` is structured as 5 phases. The summary here is just enough to anchor the research:

- **Phase 0 — Measurement baseline.** Add the signposts, capture a baseline trace, write down the numbers.
- **Phase 1 — Hot-path SoA for ModelConstants.** Move modelConstants storage out of `GameObject` into per-Model SoA columns. The smallest, lowest-risk change that exercises the whole DOD discipline.
- **Phase 2 — Transform SoA.** Replace the inline `_position`/`_rotationMatrix`/`_scale` on `Node` with column stores indexed by `EntityID`. Provide a transparent `Node` API on top, so the rest of the codebase doesn't move at first.
- **Phase 3 — Physics SoA.** Replace `PhysicsWorld.entities: [PhysicsEntity]` with concrete per-shape stores. Eliminate the `as!` casts.
- **Phase 4 — Component registry.** Introduce a lightweight `World` / `EntityID` / `ComponentStore<T>` skeleton. Migrate animation channels into it. New features (radar, fuel, damage) live here from birth.
- **Phase 5 — Optional full ECS.** If phases 1-4 expose enough composability win, decide whether to migrate the rest of `GameObject` or stop where you are. Both are valid endpoints.

Each phase has its own measurement gate.

---

## References

Primary sources visited during this research:

- [Entity component system — Wikipedia](https://en.wikipedia.org/wiki/Entity_component_system)
- [Data-oriented design — Wikipedia](https://en.wikipedia.org/wiki/Data-oriented_design)
- [Austin Morlan, "A Simple Entity Component System (ECS) [C++]"](https://austinmorlan.com/posts/entity_component_system/)
- [UML Board, "Entity-Component-System"](https://www.umlboard.com/design-patterns/entity-component-system.html)
- [Sander Mertens, "ECS FAQ" (GitHub)](https://github.com/SanderMertens/ecs-faq)
- [flecs FAQ](https://www.flecs.dev/flecs/md_docs_2FAQ.html)
- [Tainted Coders, "Bevy ECS"](http://taintedcoders.com/bevy/ecs)
- [Tony Albrecht, "Pitfalls of Object-Oriented Programming," GCAP 2009 (SlideShare)](https://www.slideshare.net/slideshow/pitfalls-of-object-oriented-programminggcap09/30045164)
- [Mike Acton, "Data-Oriented Design and C++," CppCon 2014 — CppCon GitHub repo (slides)](https://github.com/CppCon/CppCon2014/blob/master/Presentations/Data-Oriented%20Design%20and%20C++/Data-Oriented%20Design%20and%20C++%20-%20Mike%20Acton%20-%20CppCon%202014.pptx)
- [Mike Acton, "Data-Oriented Design and C++," CppCon 2014 — YouTube](https://www.youtube.com/watch?v=rX0ItVEVjHc)
- [isocpp.org, "CppCon 2014 Data-Oriented Design and C++ – Mike Acton"](https://isocpp.org/blog/2015/01/cppcon-2014-data-oriented-design-and-c-mike-acton)
- [Apple M1 — 7-cpu.com](https://www.7-cpu.com/cpu/Apple_M1.html)
- [Apple M1 — Wikipedia](https://en.wikipedia.org/wiki/Apple_M1)
- [Anandtech, "Apple Announces The Apple Silicon M1: Ditching x86 — What to Expect"](https://www.anandtech.com/show/16226/apple-silicon-m1-a14-deep-dive/2)
- [GameplayKit Programming Guide: Entities and Components — Apple](https://developer.apple.com/library/archive/documentation/General/Conceptual/GameplayKit_Guide/EntityComponent.html)
- [InvadingOctopus / octopuskit — a Swift ECS for SpriteKit](https://github.com/InvadingOctopus/octopuskit)
- [LearnCocos2D, "Overview of ECS variations with pseudo-code"](https://gist.github.com/LearnCocos2D/77f0ced228292676689f)
- [Apple Developer, "Optimize CPU performance with Instruments" — WWDC25 Session 308](https://developer.apple.com/videos/play/wwdc2025/308/)
- [Apple Developer, "Metal Debugger documentation"](https://developer.apple.com/documentation/xcode/metal-debugger)
- [Apple Developer, "Optimizing GPU performance"](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance)
- [Apple Developer, "Discover new Metal profiling tools for M3 and A17 Pro" — Tech Talks](https://developer.apple.com/videos/play/tech-talks/111374/)
- [Apple Developer, "Optimize Metal apps and games with GPU counters" — WWDC20](https://developer.apple.com/videos/play/wwdc2020/10603/)
- [Apple Developer, "UnsafeMutableBufferPointer"](https://developer.apple.com/documentation/swift/unsafemutablebufferpointer)
- [advancedswift.com, "Xcode CPU Performance Profiling [Optimize Code Execution]"](https://www.advancedswift.com/counters-in-instruments/)
- [polpiella.dev, "How to profile your app's performance and Main Thread usage with Instruments and os_signposts"](https://www.polpiella.dev/time-profiler-instruments/)
- [Kodeco, "Metal by Tutorials, Chapter 23: Debugging & Profiling"](https://www.kodeco.com/books/metal-by-tutorials/v2.0/chapters/23-debugging-profiling)
- [Graphics Compendium, "Chapter 62: Data-Oriented Design"](https://graphicscompendium.com/software/09-data-oriented-design)
- [Alessandro Minali, "Data-Oriented Design: Canonical Example (C)"](https://alessandrominali.github.io/data_oriented_design_canonical_example.html)
- [Awesome ECS — curated list of ECS libraries](https://jslee02.github.io/awesome-entity-component-system/)
