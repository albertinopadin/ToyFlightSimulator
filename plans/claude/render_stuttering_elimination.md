# Plan: Eliminate Render-Thread Stuttering (Fixes B, D, E)

## Context

After porting 3 performance optimizations from Automata (dirty flag, ring buffer, once-per-frame GetUniformsData), the Aircraft exhibited intermittent stuttering during movement. Two root causes were identified:

1. **Update/render thread race condition**: The double `signal()` pattern in `render()` created non-deterministic timing — sometimes the render thread read stale data, sometimes fresh, causing position jitter.
2. **Per-frame heap allocations**: `GetUniformsData()` allocated a new `[Model: UniformsData]` dictionary and `[ModelConstants]` arrays via `compactMap` every frame (~10 heap allocations at 60 FPS = 600/sec), causing allocator pressure and intermittent micro-stutters.
3. **First 3-5 seconds stutter**: Metal defers GPU shader variant compilation to first use of each pipeline state.

## Fixes Implemented

### Fix B: Write ModelConstants Directly into Ring Buffer During Update (HIGHEST IMPACT)

**Goal**: Eliminate `GetUniformsData()` entirely. Write ModelConstants directly into the per-frame ring buffer during the update phase. Render thread reads from the ring buffer without any locking or copying.

**Previous flow**:
```
Update Thread:                          Render Thread:
  SceneManager.Update()                   GetUniformsData()     <- ALLOC dict + arrays
    uniformsLock.lock()                     uniformsLock.lock()  <- CONTENTION
    scene.update()                          copy modelConstants
      GameObject.update()                   uniformsLock.unlock()
        modelConstants = ...              DrawOpaque(uniforms)
    uniformsLock.unlock()                   Draw()
                                              writeUniformsToRingBuffer() <- COPY #2
                                              bind buffer to GPU
```

**New flow**:
```
Update Thread:                          Render Thread:
  SceneManager.Update()                   DrawOpaque()
    scene.update()                          bind pre-written ring buffer regions to GPU
      GameObject.update()                   (no lock, no allocation, no copy)
        modelConstants = ...
    writeFrameSnapshot()
      for each model:
        write modelConstants directly
        record (offset, count) per model
```

**Key design decisions**:
- Triple-buffered snapshots (`opaqueSnapshots`, `transparentSnapshots`, `skySnapshots`) store lightweight `RingBufferRegion` structs (offset + count + meshDatas reference)
- `uniformsLock` removed — `inFlightSemaphore` already prevents buffer slot reuse
- Frame index passed from render thread to update thread via `SceneManager.nextFrameIndex`
- `updateEndOffsets` array ensures render thread's ad-hoc draws start from where update thread left off
- Animated meshes (with `mesh.transform`) still require a temporary copy at draw time; static meshes are zero-copy

**What was eliminated per frame**:
- 1 `[Model: UniformsData]` dictionary allocation
- 5-10 `[ModelConstants]` array allocations (via `compactMap`)
- ~3-4 KB of struct copying through intermediate arrays
- All lock contention between update and render threads

### Earlier Fixes (from prior session)

- **Double-signal race fix**: Removed first `updateSemaphore.signal()` from `render()`, keeping only the one at the end
- **Frame counter race fix**: Replaced async `GameStatsManager.frameCounter` with local `renderFrameCounter` on Renderer
- **Missing dirty flag assignment**: Added `worldMatrixDirty = needsUpdate` in `Node.update()`
- **Redundant matrix recomputation**: Removed duplicate `updateModelMatrix()` call in `Node.update()` (already called by setters)

### Fix D: Pipeline State Warmup (NOT IMPLEMENTED)

Pipeline states are already compiled synchronously during `Graphics` static init (via `RenderPipelineStateLibrary.makeLibrary()`). A warmup render pass would require matching each PSO's render pass descriptor format, adding complexity for uncertain benefit. Deferred if first-seconds stutter persists.

### Fix E: Texture Preloading (NOT NEEDED)

Textures are loaded eagerly during model initialization in `Material.init()`, which runs during `buildScene()`. No lazy loading to preempt.

## Files Modified

| File | Changes |
|------|---------|
| `SceneManager.swift` | Added `RingBufferRegion`, `frameSnapshots`, `nextFrameIndex`, `writeFrameSnapshot()`, `getOpaqueSnapshot()`, `getTransparentSnapshot()`, `getSkySnapshot()`. Removed `uniformsLock`, `GetUniformsData()`, `GetTransparentUniformsData()`, `GetSkyUniformsData()`. Modified `Update()` to call `writeFrameSnapshot()`. |
| `DrawManager.swift` | Added `writeModelConstants()`, `BeginFrameForUpdate()`, `finishUpdateWrites()`, `updateEndOffsets`, `DrawFromRingBuffer()`. Modified `BeginFrame()` to use update end offset. Changed `DrawOpaque`, `DrawTransparent`, `DrawShadows`, `DrawSky` to read from snapshots. Kept legacy `Draw()` for ad-hoc objects (point lights, icosahedrons). |
| `Renderer.swift` | Added `renderFrameCounter`. Sets `SceneManager.nextFrameIndex` before signaling update thread. Removed first `signal()`. |
| `Node.swift` | Added `_transformDirty`, `worldMatrixDirty`, `markTransformDirty()`, `updateModelMatrixAndMarkTransformDirty()`. |
| `GameObject.swift` | Added `instanceBufferIndex`. Gated `modelConstants` update on `worldMatrixDirty`. |
| `ShadowRendering.swift` | Removed `uniforms` parameter from all shadow pass methods. |
| `SinglePassDeferredLightingRenderer.swift` | Removed `uniforms` parameter from stage methods. Removed `GetUniformsData()` call. |
| `TiledDeferredRenderer.swift` | Same pattern. |
| `TiledMultisampleRenderer.swift` | Same pattern. |
| `TiledMSAATessellatedRenderer.swift` | Same pattern. |
| `OITRenderer.swift` | Same pattern. |
| `GameStatsManager.swift` | Renamed `framesRendered` to `frameCounter`. |
| `GameStats.swift` | Updated to use `frameCounter`. |
| `Engine.swift` | Added `DrawManager.InitializeRingBuffers()` call. |

## Verification

1. Build: `xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" ...`
2. Run the app and fly the aircraft — verify smooth movement with no stuttering
3. Switch renderers via menu — verify each renderer works correctly
4. Check animation: verify animated models (F-22 control surfaces, landing gear) still animate correctly
5. GPU frame capture: use Xcode's GPU Frame Capture to verify ring buffer is bound correctly
