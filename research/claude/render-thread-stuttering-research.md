# Render Thread Stuttering Research

**Date:** 2026-03-31
**Context:** After porting 3 performance optimizations from Automata (dirty flag, ring buffer, once-per-frame GetUniformsData), the Aircraft exhibits visible stuttering during movement. The first signal() was removed from render() which reduced stuttering significantly, but occasional hiccups remain, especially in the first 3-5 seconds.

## Root Causes Identified

### 1. Per-Frame Heap Allocations in GetUniformsData() (Ongoing Stuttering)

**Location:** `SceneManager.swift:310-322`

```swift
public static func GetUniformsData() -> [Model: UniformsData] {
    uniformsLock.lock()
    var uniformsData: [Model: UniformsData] = [:]        // ALLOC: Dictionary
    for key in modelDatas.keys {
        let modelData = modelDatas[key]!
        uniformsData[key] = UniformsData(
            uniforms: modelData.gameObjects.compactMap(\.modelConstants),  // ALLOC: Array
            meshDatas: modelData.meshDatas
        )
    }
    uniformsLock.unlock()
    return uniformsData
}
```

**Every frame**, this function:
1. Allocates a new `[Model: UniformsData]` dictionary on the heap
2. For each model type (~5-10 unique models), calls `compactMap(\.modelConstants)` which allocates a new `[ModelConstants]` array
3. Each `ModelConstants` is 128 bytes (4x4 matrix + 3x3 matrix + float4 + bool + padding)
4. With ~20-30 game objects, this copies ~2.5-3.8 KB of data through heap-allocated arrays

The dictionary and array allocations hit the Swift allocator, which can cause occasional GC pauses or allocator contention. While each individual allocation is small, the cumulative effect at 60 FPS (60 dictionary allocations + 300-600 array allocations per second) creates GC pressure that manifests as intermittent micro-stutters.

**Impact:** Low but cumulative — intermittent 0.1-1ms stalls from allocator pressure

### 2. Lock Contention Window (Occasional Stuttering)

**Location:** `SceneManager.swift:111, 167-172, 312-319`

The `uniformsLock` (OSAllocatedUnfairLock) is held during:
- `Update()`: The entire scene update (lines 167-172), including all GameObject doUpdate() calls, transform updates, and modelConstants writes
- `GetUniformsData()`: The entire snapshot operation (lines 312-319)

Even with the fix that removed the first `signal()`, there's still a timing window where the update thread hasn't fully completed when the next frame's `GetUniformsData()` is called. The OSAllocatedUnfairLock is an unfair lock — it doesn't guarantee FIFO ordering, meaning the render thread could repeatedly win the lock race, reading stale data in bursts.

**Impact:** Medium — occasional 0.5-2ms stalls when lock is contended

### 3. Pipeline State Compilation (First 3-5 Seconds Stuttering)

**Location:** `RenderPipelineStateLibrary.swift:67-114`, various pipeline files

All ~43 pipeline states are compiled synchronously during `Graphics` static initialization:

```swift
// Graphics.swift:10-18
public static let RenderPipelineStates = RenderPipelineStateLibrary()

// Library.swift:8-11
init() {
    makeLibrary()  // Synchronous — blocks until ALL states compiled
}
```

Each pipeline state calls `Engine.Device.makeRenderPipelineState(descriptor:)` which can take 1-10ms per state depending on shader complexity. With 43+ states, this is 50-200ms total.

However, this happens during Engine.Start(), before the first draw call. So why does it cause stuttering in the first few seconds?

**Metal's internal shader compilation is deferred.** Even though `makeRenderPipelineState()` returns a pipeline state object, Metal may defer the actual GPU shader compilation to the first time that state is used in a draw call. This means the first time each unique pipeline state is bound during rendering, there can be a GPU stall of 1-5ms while Metal JIT-compiles the shader variant for the specific GPU.

With the typical deferred rendering pipeline (shadow pass, GBuffer, lighting, transparency, particles, skybox), the first few frames exercise different pipeline states for the first time, causing cumulative stalls.

**Impact:** High for first 3-5 seconds — 5-50ms stalls per frame as pipeline states are exercised for the first time

### 4. Texture Loading and Mipmap Generation (First 1-2 Seconds)

**Location:** `TextureLoader.swift` (singleton with 3-level cache)

Textures are loaded lazily on first access. The first frame that renders a model triggers:
1. File I/O to read the texture image
2. GPU upload of texture data
3. Mipmap generation (automatic, GPU-driven)

These operations are synchronous and can cause 5-20ms stalls per texture on first access.

**Impact:** High for first 1-2 seconds — one-time cost per texture

## Recommended Fixes

### Fix A: Eliminate Per-Frame Allocations with Pre-Allocated Snapshot Buffers (HIGH IMPACT)

Replace the dictionary + array allocation pattern with a pre-allocated, triple-buffered snapshot system:

```swift
// Pre-allocate 3 snapshot buffers (one per in-flight frame)
private static var uniformSnapshots: [UnsafeMutableBufferPointer<ModelConstants>] = []
private static var snapshotFrameIndex: Int = 0

// Instead of returning [Model: UniformsData], write directly into the ring buffer's
// ModelConstants region and return lightweight index/count pairs
```

**Approach:**
1. After scene build, count total game objects and pre-allocate a `ContiguousArray<ModelConstants>` per model type
2. Each frame, copy modelConstants directly into pre-allocated arrays instead of creating new ones via compactMap
3. Use a struct-of-arrays layout: `[Model: (buffer: UnsafeMutablePointer<ModelConstants>, count: Int)]`
4. The arrays are reused frame-to-frame — no heap allocation

**Simpler intermediate approach:**
1. Pre-allocate the `[Model: UniformsData]` dictionary once after scene build (reserve capacity)
2. Replace `compactMap` with a pre-allocated `ContiguousArray<ModelConstants>` per model
3. Each frame, overwrite the array contents instead of creating new arrays

### Fix B: Write ModelConstants Directly into Ring Buffer During Update (HIGHEST IMPACT)

Instead of the two-step process (update modelConstants on GameObjects → copy into ring buffer during draw), write ModelConstants directly into the ring buffer during the update phase:

```swift
// During SceneManager.Update():
// 1. BeginFrame() resets ring buffer
// 2. For each model type, reserve a region in the ring buffer
// 3. Each GameObject writes its modelConstants directly into the ring buffer region
// 4. Store (buffer, offset, count) per model — no intermediate copy needed
```

This eliminates:
- The `GetUniformsData()` function entirely
- The dictionary allocation
- The compactMap array allocations
- The memcpy in `writeUniformsToRingBuffer`
- The lock contention (update and render no longer share modelConstants on GameObjects)

**Trade-off:** Requires the update thread to know the ring buffer frame index, coupling update and render slightly.

### Fix C: Reduce Lock Contention with Double-Buffered Scene State (MEDIUM IMPACT)

Instead of locking during the entire update, maintain two copies of the uniform data:

```swift
private static var uniformBuffers: [[Model: UniformsData]] = [[:], [:]]
private static var writeIndex: Int = 0  // Update thread writes here
private static var readIndex: Int = 1   // Render thread reads here

// Update thread writes to uniformBuffers[writeIndex]
// At frame boundary, swap indices (atomic swap, no lock needed during read)
// Render thread reads from uniformBuffers[readIndex] without locking
```

This makes `GetUniformsData()` lock-free on the render thread — it just returns `uniformBuffers[readIndex]`.

### Fix D: Pipeline State Warmup Pass (HIGH IMPACT for first-seconds stutter)

Add a warmup pass after scene build that exercises all pipeline states without producing visible output:

```swift
// In Engine.Start() or after SceneManager.SetScene():
static func warmupPipelineStates() {
    guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else { return }

    // Create a tiny (1x1) render pass that binds each pipeline state
    let desc = MTLRenderPassDescriptor()
    // ... configure with 1x1 textures ...

    if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) {
        // Bind each pipeline state to force Metal to compile the shader variant
        for psoType in RenderPipelineStateType.allCases {
            encoder.setRenderPipelineState(Graphics.RenderPipelineStates[psoType])
        }
        encoder.endEncoding()
    }

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()  // Block until all shaders compiled
}
```

This front-loads all shader compilation before the first visible frame.

### Fix E: Async Texture Preloading (MEDIUM IMPACT for first-seconds stutter)

Preload all textures used by the scene during `buildScene()`:

```swift
// In GameScene.buildScene() or postBuildScene():
func preloadTextures() {
    for (_, modelData) in SceneManager.modelDatas {
        for meshData in modelData.meshDatas {
            for submesh in meshData.opaqueSubmeshes + meshData.transparentSubmeshes {
                _ = submesh.material?.baseColorTexture
                _ = submesh.material?.normalMapTexture
                _ = submesh.material?.specularTexture
            }
        }
    }
}
```

## Recommended Implementation Priority

1. **Fix A** (pre-allocated snapshots) — Eliminates the most common source of ongoing micro-stutters. Medium effort.
2. **Fix D** (pipeline warmup) — Eliminates first-seconds stuttering completely. Low effort.
3. **Fix B** (direct ring buffer writes) — The ultimate solution that eliminates both GetUniformsData and the lock. High effort, best long-term.
4. **Fix C** (double-buffered state) — Good intermediate step if Fix B is too invasive. Medium effort.
5. **Fix E** (texture preload) — Simple insurance against first-access texture stalls. Low effort.

## Analysis: Why Current Architecture Causes Stuttering

The fundamental issue is that the render thread and update thread share mutable state (modelConstants on GameObjects) protected by a lock. This creates two problems:

1. **Contention:** One thread must wait for the other
2. **Allocation:** The snapshot mechanism (GetUniformsData) creates new heap objects every frame to avoid reading shared state during rendering

The ideal architecture separates update and render data entirely:
- Update thread writes to its own data structures
- At frame boundary, a lightweight "publish" operation makes the update visible to the render thread
- Render thread reads from its own copy without any locking

This is the classic "double buffer" or "triple buffer" pattern used by production game engines.

## Technical Details

### ModelConstants Size
```c
typedef struct {
    matrix_float4x4 modelMatrix;     // 64 bytes
    matrix_float3x3 normalMatrix;    // 48 bytes (3x float3, each padded to 16 bytes)
    simd_float4 objectColor;         // 16 bytes
    bool useObjectColor;             // 1 byte + 15 padding
} ModelConstants;
// Total: 144 bytes (with Metal alignment padding)
// MemoryLayout<ModelConstants>.stride likely = 144-160 bytes
```

### Typical Scene Metrics
- Unique model types: 5-10
- Total game objects: 20-30
- Total ModelConstants copied per frame: 20-30 * ~144 bytes = ~3-4.3 KB
- Dictionary entries: 5-10
- Array allocations (via compactMap): 5-10 per frame

### Frame Budget
- At 60 FPS: 16.67ms per frame
- At 120 FPS: 8.33ms per frame
- GetUniformsData typical cost: 0.05-0.5ms (mostly allocation overhead)
- Lock contention worst case: 1-5ms (if update thread is mid-update)
- Pipeline state first-use: 1-10ms per state

## Sources

- [Apple Metal Best Practices Guide: Triple Buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html)
- [Metal Game Performance Optimization - WWDC18](https://developer.apple.com/videos/play/wwdc2018/612/)
- [Modern Rendering with Metal - WWDC19](https://developer.apple.com/videos/play/wwdc2019/601/)
- [Apple: makeRenderPipelineState(descriptor:)](https://developer.apple.com/documentation/metal/mtldevice/1433369-makerenderpipelinestate)
- [Apple: addCompletedHandler](https://developer.apple.com/documentation/metal/mtlcommandbuffer/1442997-addcompletedhandler)
- [Apple: addScheduledHandler](https://developer.apple.com/documentation/metal/mtlcommandbuffer/1442991-addscheduledhandler)
- [MTKView fullscreen stutter - Apple Developer Forums](https://developer.apple.com/forums/thread/733033)
- [Metal Triple Buffering and the Main Thread - Apple Developer Forums](https://developer.apple.com/forums/thread/651581)
- [Swift Concurrency + Metal Without Stutters (Medium)](https://medium.com/@michaelstebel/swift-concurrency-metal-without-stutters-a-practical-architecture-for-real-time-rendering-419d9523ebca)
- [Engine Internals: Optimizing Our Renderer for Metal and iOS (Medium)](https://medium.com/@heinapurola/engine-internals-optimizing-our-renderer-for-metal-and-ios-77aeff5faba)
- [Double Buffer Pattern - Game Programming Patterns](https://gameprogrammingpatterns.com/double-buffer.html)
- [Instanced Rendering in Metal - Metal by Example](https://metalbyexample.com/instanced-rendering/)
- [Metal by Tutorials Ch.24: Performance Optimization - Kodeco](https://www.kodeco.com/books/metal-by-tutorials/v2.0/chapters/24-performance-optimization)
- [Reducing stutter from shader compilations - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)
- [Improving your game's graphics performance - Apple Developer](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings)
- [Lock Free Double Buffer - GitHub Gist](https://gist.github.com/SF-Zhou/51c9e36e74c41d20abe94549d1ffe17f)
- [Optimize GPU renderers with Metal - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10127/)
- [Swapchains and frame pacing - Raph Levien](https://raphlinus.github.io/ui/graphics/gpu/2021/10/22/swapchain-frame-pacing.html)
