# Retire the `RenderState` global: pass per-pass pipeline context into DrawManager

Status: **proposed — awaiting review** (2026-07-11). No code changed yet.

## Context

`RenderState` (`Display/RenderState.swift`) is a pair of process-global statics (`CurrentPipelineStateType` / `PreviousPipelineStateType`) that exists solely so `DrawManager.SetupAnimation` can (a) know which pass PSO is bound when it swaps a skinned mesh to an animated pipeline, and (b) restore that pass PSO for the next non-skinned mesh. Commit `645e307` made the mechanism *correct* — every per-pass bind now goes through the tracked `setRenderPipelineState(_:state:)` helper, the animated PSO is derived per family via `animatedVariant`, and `TeardownScene` resets the globals — but the design is still a global-state workaround, flagged as such in AGENTS.md and in the debugging doc's follow-ups (`debugging/claude/renderer_switch_pso_sample_count_mismatch.md`). This plan replaces it with explicit per-pass context: the three `DrawManager` entry points that handle skinned meshes take the pass pipeline as a parameter, and the swap/restore becomes a local two-state machine inside each draw loop.

## Why retire it (the reasoning)

1. **Convention → compiler.** The current invariant — *"every per-pass PSO bind must go through the tracked helper"* — is enforced only by review and documentation. History shows conventions rot: the tracker landed in January with only the default renderer converted, and the resulting crash class survived undetected for six months until runtime renderer switching started working. With a `passPipeline` parameter, a renderer *cannot* call `DrawOpaque`/`DrawTransparent`/`DrawShadows` without stating which pass it is in; forgetting is a compile error, not a latent GPU assert.

2. **Global mutable state off the hot path.** Both statics are `nonisolated(unsafe)`. They are safe today only because all encoding happens on one thread. Any future parallelism — `MTLParallelRenderCommandEncoder`, encoding shadow and GBuffer command buffers on different threads, async command buffer preparation — would race the tracker invisibly (wrong PSO restored, no crash, subtly corrupt frames). A `var animatedBound` local to each draw loop cannot race anything.

3. **Hidden cross-pass and cross-lifecycle coupling.** Today the shadow pass writes state the GBuffer pass's draw loop consumes; a renderer switch leaks state unless `TeardownScene` remembers to reset it; the "restore" is a two-deep implicit stack (`Previous`) that only works because `SetupAnimation` is the single nester and passes are strictly sequential. All three couplings disappear when the state lives inside the loop that uses it.

4. **It kills the tracked-vs-raw distinction.** After this change the helper is pure sugar; no bind style can be "wrong" anymore. The special-case knowledge in AGENTS.md/CLAUDE.md ("mandatory tracked helper") gets deleted rather than maintained.

5. **It fixes two latent trailing-state bugs by construction** (both present today, verified in `DrawManager.swift`):
   - `DrawOpaque` ends with `DrawLines(with:)` (line 174), which binds no PSO of its own. If the *last* opaque mesh was skinned, lines draw through the leftover **animated** pipeline with a stale joint palette bound.
   - `DrawTransparent`'s second loop (fully-transparent objects, lines 201-212) never calls `SetupAnimation`. If the last mesh of loop 1 was skinned, loop 2 inherits the animated PSO the same way.
   The refactor adds an explicit end-of-loop restore, so every draw loop leaves the encoder holding the pass pipeline it was given.

**Cost:** one extra parameter on three `DrawManager` entry points and ~10 call sites; each renderer stage names its pipeline twice (bind + draw call) — mitigated with a local constant per stage so the two uses cannot drift.

**Alternatives considered and rejected:**
- *A `RenderPassContext` struct* (pipeline + depth-stencil + future fields): nothing today needs a second field; introduce a struct when one does. A bare enum parameter keeps the diff and the call sites minimal.
- *Encoder-associated state* (a side table keyed by `ObjectIdentifier(encoder)`): still hidden state, adds lookup cost, and solves nothing the parameter doesn't.

## Design

- `DrawOpaque` / `DrawTransparent` / `DrawShadows` gain `passPipeline: RenderPipelineStateType`.
- `SetupAnimation` becomes `private`, takes `passPipeline` plus `animatedBound: inout Bool` (a local owned by the calling loop), and derives the animated PSO from `passPipeline.animatedVariant` — the mapping introduced in `645e307` stays the single source of pass→animated pairing (and picks up the OIT/SinglePass entries if `oit_singlepass_animated_pipeline_variants` lands first).
- A private `RestorePassPipelineIfAnimated` re-binds the pass PSO (and clears the joint buffer slot) at loop boundaries.
- `RenderState.swift` is deleted; the `RenderPassEncoding` helper drops its global writes (kept as one-line sugar — 30+ call sites read well as-is); `TeardownScene` loses the `RenderState.Reset()` block; `isAnimatedVariant` is deleted (its only consumer was the global restore check).
- `ShadowRendering.encodeCascadePasses` currently takes a `draw` closure — all three callers pass the identical `{ DrawManager.DrawShadows(with: $0) }` body. Fold the call into `encodeCascadePasses` itself (it already has the `pipeline` parameter to forward), deleting the closure parameter and three duplicate bodies.

Behavior parity: for every existing skinned/non-skinned interleaving the bound-PSO sequence is identical to today's, except the two trailing-state fixes above (lines and fully-transparent objects now draw with the pass PSO — the intended behavior).

## Diffs

### 1. `ToyFlightSimulator Shared/Managers/DrawManager.swift`

`SetupAnimation` → local state machine (replaces the whole current body, lines 215-241):

```swift
    /// Skinned meshes swap to the pass's animated PSO (joint palette bound);
    /// the next non-skinned mesh restores the pass PSO. `animatedBound` is a
    /// local owned by the calling draw loop — no global pipeline tracking.
    private static func SetupAnimation(_ renderEncoder: MTLRenderCommandEncoder,
                                       mesh: Mesh,
                                       passPipeline: RenderPipelineStateType,
                                       animatedBound: inout Bool) {
        if let paletteBuffer = mesh.skin?.jointMatrixPaletteBuffer {
            renderEncoder.setVertexBuffer(paletteBuffer,
                                          offset: 0,
                                          index: TFSBufferIndexJointBuffer.index)

            // nil variant: the renderer family has no animated pipelines —
            // the mesh draws in bind pose with the pass PSO.
            guard !animatedBound, let animated = passPipeline.animatedVariant else { return }
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[animated])
            animatedBound = true
        } else if animatedBound {
            renderEncoder.setVertexBuffer(nil,
                                          offset: 0,
                                          index: TFSBufferIndexJointBuffer.index)
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[passPipeline])
            animatedBound = false
        }
    }

    /// Loop-boundary restore: whatever follows (lines, fully-transparent
    /// objects, the next stage) must see the pass pipeline, not a leftover
    /// animated PSO from a trailing skinned mesh.
    private static func RestorePassPipelineIfAnimated(_ renderEncoder: MTLRenderCommandEncoder,
                                                      passPipeline: RenderPipelineStateType,
                                                      animatedBound: inout Bool) {
        guard animatedBound else { return }
        renderEncoder.setVertexBuffer(nil, offset: 0, index: TFSBufferIndexJointBuffer.index)
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[passPipeline])
        animatedBound = false
    }
```

`DrawOpaque` (lines 151-175):

```diff
-    static func DrawOpaque(with renderEncoder: MTLRenderCommandEncoder, applyMaterials: Bool = true) {
+    static func DrawOpaque(with renderEncoder: MTLRenderCommandEncoder,
+                           passPipeline: RenderPipelineStateType,
+                           applyMaterials: Bool = true) {
         renderEncoder.setFrontFacing(.clockwise)
         renderEncoder.setCullMode(.back)
 
         if applyMaterials {
             bindLinearSampler(renderEncoder)
         }
 
+        var animatedBound = false
         let snapshot = SceneManager.getOpaqueSnapshot(frameIndex: currentFrameIndex)
         for (model, region) in snapshot {
             for meshData in region.meshDatas {
                 if !meshData.opaqueSubmeshes.isEmpty {
-                    SetupAnimation(renderEncoder, mesh: meshData.mesh)
+                    SetupAnimation(renderEncoder,
+                                   mesh: meshData.mesh,
+                                   passPipeline: passPipeline,
+                                   animatedBound: &animatedBound)
                     DrawFromRingBuffer(renderEncoder,
                                        model: model,
                                        region: region,
                                        mesh: meshData.mesh,
                                        submeshes: meshData.opaqueSubmeshes,
                                        applyMaterials: applyMaterials)
                 }
             }
         }
 
+        RestorePassPipelineIfAnimated(renderEncoder, passPipeline: passPipeline, animatedBound: &animatedBound)
         DrawLines(with: renderEncoder)
     }
```

`DrawTransparent` (lines 177-213) — same signature change; loop 1 threads `&animatedBound`; restore **between** the two loops:

```diff
-    static func DrawTransparent(with renderEncoder: MTLRenderCommandEncoder, applyMaterials: Bool = true) {
+    static func DrawTransparent(with renderEncoder: MTLRenderCommandEncoder,
+                                passPipeline: RenderPipelineStateType,
+                                applyMaterials: Bool = true) {
         ...
+        var animatedBound = false
         // Opaque models with transparent submeshes:
         let opaqueSnapshot = SceneManager.getOpaqueSnapshot(frameIndex: currentFrameIndex)
         for (model, region) in opaqueSnapshot {
             for meshData in region.meshDatas {
                 if !meshData.transparentSubmeshes.isEmpty {
-                    SetupAnimation(renderEncoder, mesh: meshData.mesh)
+                    SetupAnimation(renderEncoder,
+                                   mesh: meshData.mesh,
+                                   passPipeline: passPipeline,
+                                   animatedBound: &animatedBound)
                     DrawFromRingBuffer(...)
                 }
             }
         }
 
+        // Fully-transparent objects are never skinned — draw them with the
+        // pass PSO, not a leftover animated pipeline from the loop above:
+        RestorePassPipelineIfAnimated(renderEncoder, passPipeline: passPipeline, animatedBound: &animatedBound)
+
         // Fully transparent objects:
         let transparentSnapshot = SceneManager.getTransparentSnapshot(frameIndex: currentFrameIndex)
         ...
```

`DrawShadows` (lines 243-259):

```diff
-    static func DrawShadows(with renderEncoder: MTLRenderCommandEncoder) {
+    static func DrawShadows(with renderEncoder: MTLRenderCommandEncoder,
+                            passPipeline: RenderPipelineStateType) {
         renderEncoder.setFrontFacing(.clockwise)
         renderEncoder.setCullMode(.back)
         
+        var animatedBound = false
         let snapshot = SceneManager.getOpaqueSnapshot(frameIndex: currentFrameIndex)
         for (model, region) in snapshot {
             for meshData in region.meshDatas {
-                SetupAnimation(renderEncoder, mesh: meshData.mesh)
+                SetupAnimation(renderEncoder,
+                               mesh: meshData.mesh,
+                               passPipeline: passPipeline,
+                               animatedBound: &animatedBound)
                 DrawFromRingBuffer(...)
             }
         }
+        RestorePassPipelineIfAnimated(renderEncoder, passPipeline: passPipeline, animatedBound: &animatedBound)
     }
```

### 2. Renderer call sites — bind and draw share one local constant

Pattern (same shape in all five renderers; shown for `TiledMultisampleRenderer.encodeGBufferStage`, whose "Tracked bind" comment from `645e307` is also now obsolete):

```diff
     func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
         encodeRenderStage(using: renderEncoder, label: "Tiled GBuffer Stage") {
-            // Tracked bind: keeps RenderState truthful for SetupAnimation's
-            // PSO swap/restore during DrawOpaque (raw binds here restored the
-            // shadow PSO into this 4x pass — the renderer-switch assert).
-            setRenderPipelineState(renderEncoder, state: .TiledMSAAGBuffer)
+            let passPipeline: RenderPipelineStateType = .TiledMSAAGBuffer
+            setRenderPipelineState(renderEncoder, state: passPipeline)
             renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
             renderEncoder.setFragmentTexture(shadowMapArray, index: TFSTextureIndexShadow.index)
-            DrawManager.DrawOpaque(with: renderEncoder)
+            DrawManager.DrawOpaque(with: renderEncoder, passPipeline: passPipeline)
         }
     }
```

All sites (pass type per stage):

| File | Stage | passPipeline |
|---|---|---|
| `TiledMSAATessellatedRenderer.swift` | GBuffer / Transparency | `.TiledMSAAGBuffer` / `.TiledMSAATransparency` |
| `TiledMultisampleRenderer.swift` | GBuffer / Transparency | `.TiledMSAAGBuffer` / `.TiledMSAATransparency` |
| `TiledDeferredRenderer.swift` | GBuffer / Transparency | `.TiledDeferredGBuffer` / `.TiledDeferredTransparency` |
| `SinglePassDeferredLightingRenderer.swift` | GBuffer / Transparency | `.SinglePassDeferredGBufferMaterial` / `.SinglePassDeferredTransparency` |
| `OITRenderer.swift` | opaque / transparent | `.OpaqueMaterial` / `.OrderIndependentTransparent` |

(Also delete the analogous `645e307` "Tracked bind"/"keeps RenderState truthful" comments in `TiledDeferredRenderer`, `SinglePassDeferredLightingRenderer`, and `OITRenderer` — replace with nothing; the parameter now carries the intent.)

### 3. `ToyFlightSimulator Shared/Display/Protocols/ShadowRendering.swift` — fold the identical closures

```diff
     private func encodeCascadePasses(into commandBuffer: MTLCommandBuffer,
                                      pipeline: RenderPipelineStateType,
-                                     depthStencil: DepthStencilStateType,
-                                     draw: @escaping (MTLRenderCommandEncoder) -> Void) {
+                                     depthStencil: DepthStencilStateType) {
         var vps = cascadeViewProjections()
         guard !vps.isEmpty else { return }
 
         for i in 0..<min(vps.count, shadowRenderPassDescriptors.count) {
             encodeRenderPass(into: commandBuffer,
                              using: shadowRenderPassDescriptors[i],
                              label: "Shadow Map Pass [\(i)]") { renderEncoder in
                 encodeRenderStage(using: renderEncoder, label: "Shadow Generation Stage") {
                     setRenderPipelineState(renderEncoder, state: pipeline)
                     renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[depthStencil])
                     renderEncoder.setVertexBytes(&vps[i],
                                                  length: float4x4.stride,
                                                  index: TFSBufferIndexShadowCascadeVP.index)
-                    draw(renderEncoder)
+                    DrawManager.DrawShadows(with: renderEncoder, passPipeline: pipeline)
                 }
             }
         }
     }
 
     func encodeShadowMapPass(into commandBuffer: MTLCommandBuffer) {
-        encodeCascadePasses(into: commandBuffer,
-                            pipeline: .ShadowGeneration,
-                            depthStencil: .ShadowGeneration) { renderEncoder in
-            DrawManager.DrawShadows(with: renderEncoder)
-        }
+        encodeCascadePasses(into: commandBuffer, pipeline: .ShadowGeneration, depthStencil: .ShadowGeneration)
     }
 
     func encodeShadowPassTiledDeferred(into commandBuffer: MTLCommandBuffer) {
-        encodeCascadePasses(into: commandBuffer,
-                            pipeline: .TiledDeferredShadow,
-                            depthStencil: .TiledDeferredShadow) { renderEncoder in
-            DrawManager.DrawShadows(with: renderEncoder)
-        }
+        encodeCascadePasses(into: commandBuffer, pipeline: .TiledDeferredShadow, depthStencil: .TiledDeferredShadow)
     }
 
     func encodeMSAAShadowPass(into commandBuffer: MTLCommandBuffer) {
-        encodeCascadePasses(into: commandBuffer,
-                            pipeline: .TiledMSAAShadow,
-                            depthStencil: .TiledDeferredShadow) { renderEncoder in
-            DrawManager.DrawShadows(with: renderEncoder)
-        }
+        encodeCascadePasses(into: commandBuffer, pipeline: .TiledMSAAShadow, depthStencil: .TiledDeferredShadow)
     }
```

### 4. `ToyFlightSimulator Shared/Display/Protocols/RenderPassEncoding.swift` — helper becomes pure sugar

```diff
+    /// Convenience for binding a library pipeline by type. Pure sugar — the
+    /// skinned-mesh PSO swap gets its pass pipeline explicitly via the
+    /// DrawManager entry points' passPipeline parameter, so there is no
+    /// global tracking and no "wrong" way to bind a pipeline.
     func setRenderPipelineState(_ renderEncoder: MTLRenderCommandEncoder, state: RenderPipelineStateType) {
-        RenderState.PreviousPipelineStateType = RenderState.CurrentPipelineStateType
-        RenderState.CurrentPipelineStateType = state
         renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[state])
     }
```

### 5. Delete `RenderState` and its lifecycle hooks

- `git rm "ToyFlightSimulator Shared/Display/RenderState.swift"` — the `ToyFlightSimulator Shared` group is a `PBXFileSystemSynchronizedRootGroup` (project.pbxproj:167), so removal from disk removes it from all targets; no pbxproj edit. (If the build unexpectedly complains, the file appears in one of the group's exception sets — remove the reference in Xcode.)
- `Managers/SceneManager.swift` — delete the `RenderState.Reset()` call and its three-line comment from `TeardownScene`.
- `RenderPipelineStateLibrary.swift` — delete `isAnimatedVariant` (sole consumer was the global restore check). `animatedVariant` stays.

### 6. Test updates — `RenderPipelineStateTypeAnimatedVariantTests.swift`

Remove `isAnimatedVariantMembership` (the property is gone). The `animatedVariant` mapping tests are unchanged and still pin the pass→animated pairing `SetupAnimation` consumes. No new unit test: the swap/restore machine is six lines of local state exercised by every frame with a skinned mesh; the manual matrix below is the meaningful check.

### 7. Documentation

- **AGENTS.md** — rewrite the two `RenderState` bullets (Rendering Architecture + High-Risk Areas): the global tracker is gone; skinned-mesh pipeline swapping is driven by the `passPipeline` parameter on `DrawManager.DrawOpaque/DrawTransparent/DrawShadows` and the `animatedVariant` mapping; `setRenderPipelineState(_:state:)` is convenience only. Drop "runtime verification required after PSO changes" down to a normal note.
- **CLAUDE.md** — shader recipe step 5: replace the "tracked helper is mandatory" parenthetical with: pass the stage's pipeline type to the `DrawManager` entry points; the helper is optional sugar.
- The debugging doc is historical — no edit.

## Ordering vs. the OIT/SinglePass variants plan

Independent, but both touch `SetupAnimation`-adjacent code. Recommended order: land `oit_singlepass_animated_pipeline_variants` first (pure additions to the mapping/library), then this refactor (consumes the mapping unchanged; its test edit then removes the *extended* `isAnimatedVariant` test). Reverse order also works with trivial diff adjustments.

## Verification

1. Builds: macOS Debug + iOS Simulator.
2. Scoped tests: `-only-testing:"ToyFlightSimulatorTests/RenderPipelineStateTypeAnimatedVariantTests"` `-only-testing:"ToyFlightSimulatorTests/RendererTests"`.
3. `grep -rn "RenderState" "ToyFlightSimulator Shared" ToyFlightSimulatorTests` returns nothing (proves full retirement; catches stragglers in comments too).
4. Manual, macOS app, Metal validation ON, default scene: full renderer switch matrix (default ↔ TiledDeferredMSAA / TiledDeferred / SinglePass / OIT) — no asserts; gear (`G`) animates under every renderer with animated variants; shadows animate with the gear; canopy transparency intact; Cmd+R reset and an aircraft swap after a switch still work.

## Risks

- Mechanical but wide: ~10 call sites across 6 files plus the shadow protocol. The compiler drives the migration (every missing `passPipeline` is an error), which is exactly the property this refactor buys.
- The end-of-loop restores change encoder state at two points where today a stale animated PSO leaks (lines / fully-transparent objects). This is intended and strictly more correct, but it is a *behavior* change if any scene accidentally relied on the leak — none does (lines and fully-transparent objects are non-skinned primitives).
- `SetupAnimation` becomes `private`; nothing outside `DrawManager` references it today (verified — call sites are only DrawOpaque/DrawTransparent/DrawShadows).
