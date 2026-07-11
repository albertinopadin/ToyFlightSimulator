# Renderer-Switch Crash: Stale `RenderState` Binds a Shadow PSO into the GBuffer Pass

Status: **implemented** (2026-07-11), including the sticky `view.sampleCount` latent issue. Implementation notes: all three fix parts landed as proposed; the "optional consistency" raw binds (`ParticleRendering.swift:26`, `DrawSky`'s bind in `DrawManager`) were left raw — no `SetupAnimation`-bearing loop follows them within a pass, and `DrawManager` has no access to the instance-side tracked helper. The view-config fix moved `view.sampleCount` into every renderer's `metalView.didSet` (4 for MSAA, 1 otherwise) and removed the per-frame sets from `draw(in:)`; OIT's new `didSet` also resets `depthStencilPixelFormat` to `.invalid`, confirmed against `FinalRenderPipelineState`, which bakes single-sample color and no depth attachment. Manual switch-matrix verification below still pending (user-driven).

## Summary

The assert is **not** a stale-texture or sample-count-rebuild problem — the switched-to renderer rebuilds its GBuffer/depth targets at the correct sample count. The pipeline being *set* is a **shadow PSO** (zero color attachments, `depth32Float`, `rasterSampleCount = 1`), bound inside the live 4× GBuffer pass by `DrawManager.SetupAnimation`'s restore path. It gets there because the animation PSO-switching workaround tracks "current/previous pipeline" in the process-global `RenderState`, and that tracker is only updated by the `RenderPassEncoding.setRenderPipelineState(_:state:)` helper — which, of the six renderers, **only `TiledMSAATessellatedRenderer` (the launch default) uses** for its per-pass binds. `TiledMultisampleRenderer` and `TiledDeferredRenderer` bind their pass PSOs through the raw `MTLRenderCommandEncoder` API, so `RenderState` still holds the shadow pass's value when the opaque draw loop runs, and the first non-skinned mesh after a skinned one "restores" the shadow PSO into the GBuffer encoder.

A second, compounding defect — `SetupAnimation`'s **hardcoded MSAA-family animated PSOs** (`.TiledMSAAGBufferAnimated` default, `.TiledMSAAShadowAnimated` in `DrawShadows`) — produces the same class of assert in the non-MSAA renderers (4× animated PSO set inside a 1× pass), which is why "switching to other renderers" fails too.

### Decoding the assert log

The reported pipeline/framebuffer pair matches exactly:

| Log line | Identification |
|---|---|
| pipeline colors all `MTLPixelFormatInvalid`, depth `Depth32Float`, stencil `Invalid`, sample count 1 | `TiledMSAAShadowPipelineState` / `…ShadowAnimated` descriptor verbatim (`TiledMSAAPipeline.swift:19-44`: color = `.invalid`, depth = `.depth32Float`, `rasterSampleCount = 1`) |
| framebuffer color 0 `BGRA8Unorm_sRGB` (4×) | `TFSRenderTargetLighting = 0` → `Preferences.MainPixelFormat` |
| color 1 `BGRA8Unorm`, color 2 `RGBA16Float`, color 4 `RGBA16Float` (4×) | `TFSRenderTargetAlbedo = 1`, `Normal = 2`, `Position = 4` (`TFSCommon.h:184-189`) — the tiled GBuffer at `sampleCount: 4` (`TiledMultisampleRenderer.swift:195`) |
| attachment 3 absent | `TFSRenderTargetDepth = 3` slot unused by this pass |
| depth/stencil `Depth32Float_Stencil8` (4×) | `TiledDeferredGBufferTextures.depthPixelFormat` (`TiledDeferredGBufferTextures.swift:21`) |

So the framebuffer is the **correct** 4× GBuffer of the new renderer; only the PSO being bound is wrong.

## Why this surfaced right after the semaphore-wiring fix

Before `renderer_switch_semaphore_wiring_fix` landed, a runtime switch left the update thread dead: `TeardownScene` cleared the ring-buffer snapshots and `writeFrameSnapshot` never ran again, so `DrawOpaque` iterated **zero** models post-switch — `SetupAnimation` never executed and this latent bug was masked (frozen world, no crash). Now the update thread survives the switch, snapshots repopulate with the skinned F-22, and the bug detonates on the first properly-rendered frame. The semaphore fix did not cause this; it unmasked a pre-existing defect.

## Root cause chain

### Step 1: the global tracker and its two writers

`RenderState` (`Display/RenderState.swift`, added 1/3/26 with the animation system) is two process-global statics, never reset by teardown or renderer init:

```swift
final class RenderState {
    nonisolated(unsafe)
    public static var CurrentPipelineStateType: RenderPipelineStateType = .TiledMSAAGBuffer
    nonisolated(unsafe)
    public static var PreviousPipelineStateType: RenderPipelineStateType = .TiledMSAAGBuffer
}
```

Only two things write it. The tracking helper (`Display/Protocols/RenderPassEncoding.swift:13-17`):

```swift
func setRenderPipelineState(_ renderEncoder: MTLRenderCommandEncoder, state: RenderPipelineStateType) {
    RenderState.PreviousPipelineStateType = RenderState.CurrentPipelineStateType
    RenderState.CurrentPipelineStateType = state
    renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[state])
}
```

and `DrawManager.SetupAnimation` (`Managers/DrawManager.swift:215-239`), which swaps to an animated PSO for skinned meshes and **restores `PreviousPipelineStateType`** for the next non-skinned mesh:

```swift
static func SetupAnimation(_ renderEncoder: MTLRenderCommandEncoder,
                           mesh: Mesh,
                           animationPipelineStateType: RenderPipelineStateType = .TiledMSAAGBufferAnimated) {
    if let paletteBuffer = mesh.skin?.jointMatrixPaletteBuffer {
        renderEncoder.setVertexBuffer(paletteBuffer, offset: 0, index: TFSBufferIndexJointBuffer.index)
        // Hack for now to set the proper PSO:
        if RenderState.CurrentPipelineStateType != animationPipelineStateType {
            RenderState.PreviousPipelineStateType = RenderState.CurrentPipelineStateType
            RenderState.CurrentPipelineStateType = animationPipelineStateType
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[animationPipelineStateType])
        }
    } else {
        // TODO: Will only work with Tiled renderer for now:
        if RenderState.CurrentPipelineStateType == animationPipelineStateType {
            renderEncoder.setVertexBuffer(nil, offset: 0, index: TFSBufferIndexJointBuffer.index)
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[RenderState.PreviousPipelineStateType])  // ← the crash site
            RenderState.CurrentPipelineStateType = RenderState.PreviousPipelineStateType
        }
    }
}
```

The workaround's correctness rests on one invariant: **when a `DrawManager` draw loop runs, `RenderState.CurrentPipelineStateType` equals the PSO actually bound on the encoder.**

### Step 2: the shadow pass writes the tracker every frame

All CSM renderers encode cascades through `ShadowRendering.encodeCascadePasses`, which uses the **tracked** helper (`ShadowRendering.swift:95`): `.TiledMSAAShadow` for both MSAA renderers, `.TiledDeferredShadow` for TiledDeferred, `.ShadowGeneration` for SinglePass. Since the shadow command buffer is encoded first each frame, `RenderState.CurrentPipelineStateType` = a shadow type when the GBuffer pass begins.

### Step 3: only the default renderer keeps the tracker truthful afterward

`TiledMSAATessellatedRenderer` binds all four of its stages through the helper — and its old raw calls are still there, **commented out** (`TiledMSAATessellatedRenderer.swift:88-89, 106-107, 119-120, 130-131`):

```swift
//            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAGBuffer])
            setRenderPipelineState(renderEncoder, state: .TiledMSAAGBuffer)
```

That's the tell: when the animation workaround landed, the conversion was applied to the default renderer only. The other renderers still bind raw, which updates the encoder but **not** the tracker:

- `TiledMultisampleRenderer` (`.TiledDeferredMSAA`): raw at `:82` (GBuffer), `:99` (DirLight), `:111` (Transparency), `:119` (MSAAResolve)
- `TiledDeferredRenderer` (`.TiledDeferred`): raw at `:71` (GBuffer), `:88` (DirLight), `:98` (PointLight), `:119` (Transparency)
- `SinglePassDeferredLightingRenderer`: raw at `:103, :115, :131, :139, :151, :164, :175`
- `OITRenderer`: raw at `:76, :86, :99, :109, :122`

### Step 4: first-frame trace after switching to TiledDeferredMSAA (the reported crash)

1. **Shadow CB** (tracked): cascades bind `.TiledMSAAShadow`; skinned F-22 meshes swap to `.TiledMSAAShadowAnimated` and restore. Depending on whether the *last* caster drawn was skinned, `Current` ends as `.TiledMSAAShadow` or `.TiledMSAAShadowAnimated` (snapshot is a `Dictionary` — order varies per run).
2. **GBuffer stage**: `TiledMultisampleRenderer.swift:82` binds `.TiledMSAAGBuffer` **raw**. Encoder is correct; `RenderState.Current` still says *shadow*.
3. **`DrawOpaque`**, first skinned mesh: `Current (shadow) != .TiledMSAAGBufferAnimated` → `Previous = shadow type`, binds `.TiledMSAAGBufferAnimated` (4×, attachment-compatible — still fine).
4. **Next non-skinned mesh**: `Current == .TiledMSAAGBufferAnimated` → restore fires: `setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAShadow])` — a no-color / `depth32Float` / sample-count-1 PSO — **inside the live 4× GBuffer encoder**. Metal validation asserts with exactly the reported message.

Trigger precondition: a non-skinned mesh drawn after a skinned one in the same pass — near-certain in the default scene (skinned F-22 + many primitive objects), modulo dictionary order.

### Step 5: why non-MSAA switch targets fail too

`TiledDeferredRenderer` has the same raw-bind hole, **plus** both hardcoded animated types are MSAA-family:

- First skinned opaque mesh binds `.TiledMSAAGBufferAnimated` (**`rasterSampleCount = 4`**, `TiledMSAAPipeline.swift:71`) into the **1×** TiledDeferred GBuffer pass → "texture sample count (1) does not match … colorSampleCount (4)" — the inverse mismatch, matching the note that non-MSAA renderers should be 1×.
- Independently, the restore path can bind a shadow PSO exactly as in Step 4.

(`DrawShadows`'s explicit `.TiledMSAAShadowAnimated` happens to *work* in TiledDeferred/SinglePass shadow passes today only because every shadow pass shares the same attachment layout — no color, `depth32Float`, 1×.)

### Step 6: "switch" is incidental

Nothing in the mechanism depends on the switch itself — only on which renderer encodes. **Prediction:** changing the initial `rendererType` in `MacGameUIView.swift:18` to `.TiledDeferredMSAA` (or `.TiledDeferred`) and cold-launching should assert identically on the first frame, with no switch involved. The default `.TiledMSAATessellated` is the only renderer whose pass binds keep the tracker truthful — which is why it *appears* that "launch works, switching breaks."

### Per-renderer status

| Renderer | Pass binds | With skinned meshes in scene |
|---|---|---|
| TiledMSAATessellated (default) | tracked helper | works (the only safe one) |
| TiledDeferredMSAA | raw | asserts: shadow PSO restored into 4× GBuffer (reported crash) |
| TiledDeferred | raw | asserts: 4× animated PSO in 1× pass, and/or shadow-PSO restore |
| SinglePassDeferred | raw | asserts: `.TiledMSAAGBufferAnimated` (4×, tiled formats) in its GBuffer pass |
| OIT | raw | asserts: same cross-family animated bind in the OIT pass |
| ForwardPlus | stub | n/a |

## Proposed fix

Three parts, one commit. Parts 1+3 restore the tracker invariant; part 2 removes the hardcoded MSAA animated types so every renderer family selects a *compatible* animated PSO (or safely skips).

### Fix 1 — route all per-pass PSO binds through the tracked helper

Exactly the conversion `TiledMSAATessellatedRenderer` already received. All renderers inherit the helper via `Renderer: BaseRendering: RenderPassEncoding`.

`ToyFlightSimulator Shared/Display/TiledMultisampleRenderer.swift` (4 sites):

```diff
     func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
         encodeRenderStage(using: renderEncoder, label: "Tiled GBuffer Stage") {
-            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAGBuffer])
+            setRenderPipelineState(renderEncoder, state: .TiledMSAAGBuffer)
```
```diff
         encodeRenderStage(using: renderEncoder, label: "Directional Light Stage") {
-            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAADirectionalLight])
+            setRenderPipelineState(renderEncoder, state: .TiledMSAADirectionalLight)
```
```diff
         encodeRenderStage(using: renderEncoder, label: "Transparent Object Rendering") {
-            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAATransparency])
+            setRenderPipelineState(renderEncoder, state: .TiledMSAATransparency)
```
```diff
         encodeRenderStage(using: renderEncoder, label: "MSAA Resolve Stage") {
-            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAAverageResolve])
+            setRenderPipelineState(renderEncoder, state: .TiledMSAAAverageResolve)
```

`ToyFlightSimulator Shared/Display/TiledDeferredRenderer.swift` — same transform at `:71` (`.TiledDeferredGBuffer`), `:88` (`.TiledDeferredDirectionalLight`), `:98` (`.TiledDeferredPointLight`), `:119` (`.TiledDeferredTransparency`).

`SinglePassDeferredLightingRenderer.swift` (`:103, :115, :131, :139, :151, :164, :175`) and `OITRenderer.swift` (`:76, :86, :99, :109, :122`) — same transform. This is required (not just hygiene): with Fix 2, `SetupAnimation` derives behavior from `RenderState.Current`, so those renderers' draw loops must see their *own* pass types (whose animated variant is nil → safe skip) rather than a stale tiled type.

Optional consistency (no skinned draws follow them in-pass, so not load-bearing): `ParticleRendering.swift:26` and `DrawManager.DrawSky`'s bind at `DrawManager.swift:359`.

### Fix 2 — derive the animated PSO from the pass PSO; delete the hardcoded MSAA defaults

Add to `RenderPipelineStateType` (in `Graphics/Libraries/Pipelines/Render/RenderPipelineStateLibrary.swift`, below the enum):

```swift
extension RenderPipelineStateType {
    /// Skinned-mesh variant of a pass PSO, nil when the pass has none.
    /// Transparency stages map to the GBuffer-animated PSO because they run in
    /// the same tile encoder with the same attachments (matches the behavior
    /// the default renderer has always had). All shadow passes share one
    /// animated PSO: every cascade pass has the same attachment layout
    /// (no color, depth32Float, sample count 1).
    var animatedVariant: RenderPipelineStateType? {
        switch self {
            case .TiledMSAAGBuffer, .TiledMSAATransparency:
                return .TiledMSAAGBufferAnimated
            case .TiledDeferredGBuffer, .TiledDeferredTransparency:
                return .TiledDeferredGBufferAnimated
            case .TiledMSAAShadow, .TiledDeferredShadow, .ShadowGeneration:
                return .TiledMSAAShadowAnimated
            default:
                return nil
        }
    }

    var isAnimatedVariant: Bool {
        self == .TiledMSAAGBufferAnimated
            || self == .TiledDeferredGBufferAnimated
            || self == .TiledMSAAShadowAnimated
    }
}
```

Rewrite `SetupAnimation` (`DrawManager.swift:215-239`) to consume it:

```swift
    static func SetupAnimation(_ renderEncoder: MTLRenderCommandEncoder, mesh: Mesh) {
        if let paletteBuffer = mesh.skin?.jointMatrixPaletteBuffer {
            renderEncoder.setVertexBuffer(paletteBuffer,
                                          offset: 0,
                                          index: TFSBufferIndexJointBuffer.index)

            // Hack for now to set the proper PSO: derive the animated variant
            // from the pass PSO the renderer bound via the tracked helper.
            // (Hardcoding an MSAA-family type here is what bound 4x/shadow
            // PSOs into mismatched passes — the renderer-switch assert.)
            // nil variant (OIT / SinglePass / already-animated): keep the
            // current PSO; the mesh draws in bind pose rather than crashing.
            guard let animated = RenderState.CurrentPipelineStateType.animatedVariant else { return }
            RenderState.PreviousPipelineStateType = RenderState.CurrentPipelineStateType
            RenderState.CurrentPipelineStateType = animated
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[animated])
        } else {
            if RenderState.CurrentPipelineStateType.isAnimatedVariant {
                renderEncoder.setVertexBuffer(nil,
                                              offset: 0,
                                              index: TFSBufferIndexJointBuffer.index)
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[RenderState.PreviousPipelineStateType])
                RenderState.CurrentPipelineStateType = RenderState.PreviousPipelineStateType
            }
        }
    }
```

And drop the now-removed parameter at the `DrawShadows` call site (`DrawManager.swift:248`):

```diff
-                SetupAnimation(renderEncoder, mesh: meshData.mesh, animationPipelineStateType: .TiledMSAAShadowAnimated)
+                SetupAnimation(renderEncoder, mesh: meshData.mesh)
```

(`DrawOpaque:163` / `DrawTransparent:190` already call it without the parameter.)

Behavior under the default renderer is bit-identical: GBuffer → `.TiledMSAAGBufferAnimated`, shadows → `.TiledMSAAShadowAnimated`, transparency → `.TiledMSAAGBufferAnimated` — the same PSOs the hardcoded values produced. Consecutive skinned meshes still short-circuit (an animated `Current` has a nil variant → early return after rebinding the palette).

**Known limitation (safe):** OIT and SinglePass have no animated pipeline variants in the library, so with this fix skinned meshes under those renderers render in **bind pose** (palette bound but unread) instead of asserting. Today they bind a cross-family 4× PSO and crash, so this is a strict improvement. Adding `OIT*/SinglePass*Animated` pipelines is follow-up work if animated aircraft matter under those renderers.

### Fix 3 — reset the tracker on teardown

A renderer switch must not leak the old renderer's last-bound types into the new renderer's first frame (a stale `*Animated` value in `Current` would trigger a bogus restore before any tracked bind runs — relevant for OIT, which has no shadow pass ahead of its opaque loop).

`Display/RenderState.swift`:

```diff
 final class RenderState {
     nonisolated(unsafe)
     public static var CurrentPipelineStateType: RenderPipelineStateType = .TiledMSAAGBuffer
     
     nonisolated(unsafe)
     public static var PreviousPipelineStateType: RenderPipelineStateType = .TiledMSAAGBuffer
+
+    /// Back to the process-start defaults. Called from SceneManager.TeardownScene
+    /// so a renderer switch can't leak the previous renderer's last-bound
+    /// pipeline types into the next renderer's first frame.
+    public static func Reset() {
+        CurrentPipelineStateType = .TiledMSAAGBuffer
+        PreviousPipelineStateType = .TiledMSAAGBuffer
+    }
 }
```

`Managers/SceneManager.swift`, in `TeardownScene`:

```diff
         // Drop render-thread caches keyed by Mesh identity (animated-uniforms
         // cache) so stale keys don't linger across scene loads:
         DrawManager.ClearFrameCaches()
+
+        // The animation PSO-switching workaround tracks bound pipelines in
+        // global RenderState; reset it so the next renderer's first frame
+        // can't restore a pipeline the old renderer left behind.
+        RenderState.Reset()
```

### Unit test (Metal-free)

`animatedVariant`/`isAnimatedVariant` are pure enum logic — add a small Swift Testing suite (e.g. `ToyFlightSimulatorTests/Graphics/RenderPipelineStateTypeAnimatedVariantTests.swift`): GBuffer/transparency/shadow cases map to their family's animated PSO, animated cases and OIT/SinglePass/compute-adjacent cases map to nil, and `isAnimatedVariant` is true for exactly the three animated cases. This pins the mapping so adding a renderer family without an animated variant fails safe (nil) rather than inheriting an MSAA default.

## Related latent issue (separate, smaller fix): sticky `view.sampleCount`

The MSAA renderers set `view.sampleCount = 4` **per frame in `draw(in:)`** (`TiledMultisampleRenderer.swift:127-128`, with an existing `// TODO: Why not put this in the metalView didSet...?`), and nothing ever sets it back to 1. This doesn't affect the tiled renderers (their GBuffer targets are app-owned), but after an MSAA → OIT/SinglePass switch:

- `OITRenderer` builds its pass from `view.currentRenderPassDescriptor` (`OITRenderer.swift:137-138`) → 4× view attachments vs its 1× pipelines;
- `SinglePassDeferredLightingRenderer` reads `view.depthStencilTexture` (`:198-199`), which inherits the view's sample count.

Proposed (resolves the existing TODO): move per-renderer view configuration into each `metalView` `didSet` — `view.sampleCount = 4` in the two MSAA renderers, `view.sampleCount = 1` in TiledDeferred/SinglePass/OIT (OIT currently has no `didSet` override; adding one is also the right home for its depth-format expectations — see the "Does not work if gameView.depthStencilPixelFormat = .depth32Float_stencil8" note in `Engine.InitRenderer`). Not required for the reported crash; verify with the MSAA → OIT and MSAA → SinglePass switch legs below.

## Verification plan

**Pre-fix confirmation (optional, to validate the diagnosis before touching code):**
1. Breakpoint or log at `DrawManager.swift:235` — after switching to TiledDeferredMSAA, `RenderState.PreviousPipelineStateType` is `.TiledMSAAShadow`/`.TiledMSAAShadowAnimated` at GBuffer time.
2. Cold-launch prediction: set the initial `rendererType` in `MacGameUIView.swift:18` to `.TiledDeferredMSAA` — the same assert should fire on the first frame with no switch involved.

**Post-fix:**
1. Builds: macOS Debug + iOS Simulator (commands in CLAUDE.md).
2. Scoped tests: the new animated-variant suite + existing `RendererTests` (`test-without-building -only-testing:…`; full local suite hangs at app-host launch — known).
3. Manual matrix, macOS app, Metal API validation ON, default FlightboxWithPhysics scene (skinned F-22 present):
   - Switch default → each of TiledDeferredMSAA, TiledDeferred, SinglePassDeferred, OIT, and back — no validation asserts, world keeps simulating (semaphore fix), stats overlay ticking.
   - After each switch: toggle gear (`G`) — under the three tiled renderers the animation must play (proves animated PSOs still bind); under OIT/SinglePass the aircraft may show bind pose (documented limitation), but no crash.
   - Shadows present and animating with the gear under tiled renderers; canopy transparency intact (transparency→GBufferAnimated mapping unchanged).
   - Cold-launch each renderer type once (temporarily change the initial `rendererType`) — no assert on first frame.

## Follow-ups (out of scope here)

- Animated pipeline variants for the OIT and SinglePassDeferred families (removes the bind-pose limitation).
- Long-term: retire the `RenderState` global entirely — pass a per-pass context (pass PSO + its animated variant) into the `DrawManager` entry points instead of threading it through process-global statics. AGENTS.md already flags `RenderState` as a hack to treat carefully.
- When the fix lands: update AGENTS.md ("`RenderState` globally tracks…" bullet and the High-Risk note) to state the invariant — *every per-pass PSO bind must go through the tracked helper* — and CLAUDE.md's renderer-recipe step 5 (`setRenderPipelineState(encoder, state:)` is mandatory, not stylistic).
