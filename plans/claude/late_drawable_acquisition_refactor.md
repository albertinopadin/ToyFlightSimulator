# Late Drawable Acquisition Refactor (4 Renderers)

## Context

The four renderers in this list all currently acquire `view.currentDrawable` (or `view.currentRenderPassDescriptor`, which implicitly does the same) before encoding several milliseconds of GBuffer/lighting/transparency/compute work:

- `ToyFlightSimulator Shared/Display/TiledMultisampleRenderer.swift` — line 172 (also reads `currentRenderPassDescriptor` at line 175)
- `ToyFlightSimulator Shared/Display/TiledMSAATessellatedRenderer.swift` — line 182 (also reads `currentRenderPassDescriptor` at line 185)
- `ToyFlightSimulator Shared/Display/TiledDeferredRenderer.swift` — line 144
- `ToyFlightSimulator Shared/Display/SinglePassDeferredLightingRenderer.swift` — line 181

Apple's documented guidance (Metal Best Practices Guide → Drawables; WWDC 2019 Session 606) is to acquire the drawable **as late as possible** and release it **as soon as possible**, because drawables come from a small pool (max 3) and holding one across CPU encoding work shrinks the pool and stalls `nextDrawable()` on subsequent frames. Today the drawable is held for ~1–8 ms per frame; the goal is to drop that to microseconds.

Full design rationale and references: [`investigations/claude/metal_drawable_acquisition_and_presentation_research_2026-04-19.md`](../../investigations/claude/metal_drawable_acquisition_and_presentation_research_2026-04-19.md).

The fix (per §267–275 of that document) is structural: render GBuffer/lighting/MSAA-resolve into an **app-owned intermediate texture** in an early command buffer, then in a separate late command buffer acquire the drawable and execute only a trivial composite-into-drawable pass before presenting.

## Outcome

Each renderer's `draw(in:)` becomes three command buffers:

1. **Early CB #1**: shadow only. (Already correct in all 4 renderers today.)
2. **Early CB #2**: all view-independent GPU work — particle compute, tessellation compute, GBuffer, lighting, transparency, particle render, MSAA resolve — writing into an app-owned `lightingResolveTexture`. Touches nothing on `view`.
3. **Late CB #3**: `guard let drawable = view.currentDrawable`, then a single full-screen quad composite of `lightingResolveTexture` into `drawable.texture`, then `commandBuffer.present(drawable)`.

Expected impact (per follow-up analysis):
- **Latency**: drawable hold time ~1–8 ms → microseconds.
- **GPU time**: unchanged.
- **CPU time**: unchanged within noise.
- **Memory**: +8–33 MB per renderer (one drawable-sized BGRA8 texture). Single texture, not ring-buffered, in line with the codebase's existing convention for shadow maps and GBuffer textures.

## Critical Files

- **NEW** `ToyFlightSimulator Shared/Display/Protocols/LateDrawablePresenting.swift` — shared infrastructure (texture factories + composite stage)
- `ToyFlightSimulator Shared/Display/SinglePassDeferredLightingRenderer.swift`
- `ToyFlightSimulator Shared/Display/TiledDeferredRenderer.swift`
- `ToyFlightSimulator Shared/Display/TiledMultisampleRenderer.swift`
- `ToyFlightSimulator Shared/Display/TiledMSAATessellatedRenderer.swift`

## Reused Existing Infrastructure

- `Engine.Device` ([`Core/Engine.swift:11`](../../ToyFlightSimulator%20Shared/Core/Engine.swift#L11)) — thread-safe `MTLDevice` singleton.
- `ShadowRendering.makeShadowMap(label:sampleCount:)` ([`Display/Protocols/ShadowRendering.swift:20`](../../ToyFlightSimulator%20Shared/Display/Protocols/ShadowRendering.swift#L20)) — pattern for `[.renderTarget, .shaderRead]` + `.storageModePrivate`.
- `Preferences.MainPixelFormat = .bgra8Unorm_srgb` ([`Core/Preferences.swift:24`](../../ToyFlightSimulator%20Shared/Core/Preferences.swift#L24)).
- `RenderPipelineStateLibrary` `.Composite` pipeline state — already used by both MSAA renderers; full-screen quad sampling one texture, color format = `Preferences.MainPixelFormat`.
- `RenderPassEncoding.encodeRenderPass(into:using:label:_:)` and `encodeRenderStage(using:label:_:)` ([`Display/Protocols/RenderPassEncoding.swift`](../../ToyFlightSimulator%20Shared/Display/Protocols/RenderPassEncoding.swift)).
- `Renderer.runDrawableCommands(_:)` ([`Display/Renderer.swift:71`](../../ToyFlightSimulator%20Shared/Display/Renderer.swift#L71)) — wraps semaphore wait + CB make + commit. **No changes needed.** Each call = one CB; three CBs per frame still respects the wait/signal contract.
- `setRenderPipelineState(_:state:)` ([`Display/Protocols/BaseRendering.swift`](../../ToyFlightSimulator%20Shared/Display/Protocols/BaseRendering.swift)) helper used by MSAA renderers for `.Composite`.

---

## 1. New Shared Protocol — `LateDrawablePresenting`

**New file:** `ToyFlightSimulator Shared/Display/Protocols/LateDrawablePresenting.swift`

```swift
import MetalKit

protocol LateDrawablePresenting: RenderPassEncoding, BaseRendering {
    var lightingResolveTexture: MTLTexture! { get set }
    var compositeRenderPassDescriptor: MTLRenderPassDescriptor { get }
}

extension LateDrawablePresenting {
    /// Single-sample app-owned texture that the GBuffer/lighting pass resolves into.
    /// Read by the composite shader; cannot be `.memoryless` because it spans render passes.
    static func makeLightingResolveTexture(size: CGSize, label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.MainPixelFormat,
            width:  max(1, Int(size.width)),
            height: max(1, Int(size.height)),
            mipmapped: false
        )
        descriptor.usage       = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        descriptor.textureType = .type2D
        descriptor.sampleCount = 1
        guard let texture = Engine.Device.makeTexture(descriptor: descriptor) else {
            fatalError("[LateDrawablePresenting] Failed to allocate lightingResolveTexture")
        }
        texture.label = label
        return texture
    }

    /// MSAA color texture for the GBuffer/lighting pass on MSAA renderers.
    /// `.memoryless` is correct here — TBDR resolves it in tile memory at end-of-pass.
    static func makeMSAALightingTexture(size: CGSize, sampleCount: Int) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Preferences.MainPixelFormat,
            width:  max(1, Int(size.width)),
            height: max(1, Int(size.height)),
            mipmapped: false
        )
        descriptor.usage       = [.renderTarget]
        descriptor.storageMode = .memoryless
        descriptor.textureType = .type2DMultisample
        descriptor.sampleCount = sampleCount
        guard let texture = Engine.Device.makeTexture(descriptor: descriptor) else {
            fatalError("[LateDrawablePresenting] Failed to allocate MSAA lighting texture")
        }
        texture.label = "Lighting MSAA"
        return texture
    }

    /// `.dontCare` (not `.clear`) — composite covers every pixel of the drawable.
    static func makeCompositeRenderPassDescriptor() -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        let lighting = descriptor.colorAttachments[TFSRenderTargetLighting.index]!
        lighting.loadAction  = .dontCare
        lighting.storeAction = .store
        // .texture set per-frame to drawable.texture in the late CB
        return descriptor
    }

    /// Shared composite shader invocation. Replaces the duplicated
    /// `encodeCompositeStage` in the two MSAA renderers.
    func encodeCompositeStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Composite Stage") {
            setRenderPipelineState(renderEncoder, state: .Composite)
            renderEncoder.setFragmentTexture(lightingResolveTexture, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
}
```

---

## 2. Per-Renderer Changes

### 2.1 `TiledDeferredRenderer.swift` (do this first — simplest)

No MSAA, has particle compute, no existing composite — adds composite pass.

**Class declaration (line 10):**
```swift
// Before
final class TiledDeferredRenderer: Renderer, ShadowRendering, ParticleRendering, @unchecked Sendable {

// After
final class TiledDeferredRenderer: Renderer, ShadowRendering, ParticleRendering, LateDrawablePresenting, @unchecked Sendable {
```

**New stored properties (after line 13):**
```swift
var lightingResolveTexture: MTLTexture!
let compositeRenderPassDescriptor: MTLRenderPassDescriptor = Self.makeCompositeRenderPassDescriptor()
```

**Lighting attachment store action (line 36 — add):**
```swift
// Before
descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
return descriptor

// After
descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
descriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .store
return descriptor
```

**`updateDrawableSize` (lines 176–181):**
```swift
// Before
func updateDrawableSize(size: CGSize) {
    gBufferTextures.makeTextures(device: Engine.Device, size: size, storageMode: .memoryless)
    setGBufferTextures(tiledDeferredRenderPassDescriptor)
    updateScreenSize(size: size)
}

// After
func updateDrawableSize(size: CGSize) {
    gBufferTextures.makeTextures(device: Engine.Device, size: size, storageMode: .memoryless)
    lightingResolveTexture = Self.makeLightingResolveTexture(size: size, label: "TiledDeferred Lighting Resolve")
    tiledDeferredRenderPassDescriptor
        .colorAttachments[TFSRenderTargetLighting.index].texture = lightingResolveTexture
    setGBufferTextures(tiledDeferredRenderPassDescriptor)
    updateScreenSize(size: size)
}
```

**`draw(in:)` (lines 134–168):**
```swift
// Before
override func draw(in view: MTKView) {
    render {
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeShadowPassTiledDeferred(into: commandBuffer)
        }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "GBuffer & Lighting Commands"

            if let drawableTexture = view.currentDrawable?.texture {
                tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = drawableTexture

                encodeParticleComputePass(into: commandBuffer)

                encodeRenderPass(into: commandBuffer,
                                 using: tiledDeferredRenderPassDescriptor,
                                 label: "GBuffer & Lighting Pass") { renderEncoder in
                    SceneManager.SetSceneConstants(with: renderEncoder)
                    SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                    SceneManager.SetPointLightData(with: renderEncoder)

                    encodeGBufferStage(using: renderEncoder)
                    encodeLightingStage(using: renderEncoder)
                    encodeTransparencyStage(using: renderEncoder)
                    encodeParticleRenderStage(using: renderEncoder)
                }
            }

            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
        }
    }
}

// After
override func draw(in view: MTKView) {
    render {
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeShadowPassTiledDeferred(into: commandBuffer)
        }

        // Early CB: all view-independent work, into app-owned lightingResolveTexture.
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "GBuffer & Lighting Commands"

            encodeParticleComputePass(into: commandBuffer)

            encodeRenderPass(into: commandBuffer,
                             using: tiledDeferredRenderPassDescriptor,
                             label: "GBuffer & Lighting Pass") { renderEncoder in
                SceneManager.SetSceneConstants(with: renderEncoder)
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                SceneManager.SetPointLightData(with: renderEncoder)

                encodeGBufferStage(using: renderEncoder)
                encodeLightingStage(using: renderEncoder)
                encodeTransparencyStage(using: renderEncoder)
                encodeParticleRenderStage(using: renderEncoder)
            }
        }

        // Late CB: acquire drawable, composite, present.
        guard let drawable = view.currentDrawable else { return }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Composite + Present"
            compositeRenderPassDescriptor
                .colorAttachments[TFSRenderTargetLighting.index].texture = drawable.texture

            encodeRenderPass(into: commandBuffer,
                             using: compositeRenderPassDescriptor,
                             label: "Composite Pass") { renderEncoder in
                encodeCompositeStage(using: renderEncoder)
            }

            commandBuffer.present(drawable)
        }
    }
}
```

---

### 2.2 `SinglePassDeferredLightingRenderer.swift`

No MSAA, no compute, no existing composite. Note: `view.depthStencilTexture` is **not** drawable-tied (it's a separately-allocated MTKView property), so we can keep using it. Allocating an app-owned depth stencil is a separate follow-up.

**Class declaration (line 10):**
```swift
// Before
final class SinglePassDeferredLightingRenderer: Renderer, ShadowRendering, @unchecked Sendable {

// After
final class SinglePassDeferredLightingRenderer: Renderer, ShadowRendering, LateDrawablePresenting, @unchecked Sendable {
```

**New stored properties (after line 41):**
```swift
var lightingResolveTexture: MTLTexture!
let compositeRenderPassDescriptor: MTLRenderPassDescriptor = Self.makeCompositeRenderPassDescriptor()
```

**Lighting attachment store action (line 37 — add):**
```swift
// Before
descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
return descriptor

// After
descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
descriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .store
return descriptor
```

**`updateDrawableSize` (lines 215–221):**
```swift
// Before
func updateDrawableSize(size: CGSize) {
    gBufferTextures.makeTextures(device: Engine.Device, size: size, storageMode: .memoryless)
    setGBufferTextures(_gBufferAndLightingRenderPassDescriptor)
    updateScreenSize(size: size)
}

// After
func updateDrawableSize(size: CGSize) {
    gBufferTextures.makeTextures(device: Engine.Device, size: size, storageMode: .memoryless)
    lightingResolveTexture = Self.makeLightingResolveTexture(size: size, label: "SPDL Lighting Resolve")
    _gBufferAndLightingRenderPassDescriptor
        .colorAttachments[TFSRenderTargetLighting.index].texture = lightingResolveTexture
    setGBufferTextures(_gBufferAndLightingRenderPassDescriptor)
    updateScreenSize(size: size)
}
```

**`draw(in:)` (lines 171–206):**
```swift
// Before
override func draw(in view: MTKView) {
    render {
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeShadowMapPass(into: commandBuffer)
        }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "GBuffer & Lighting Commands"

            if let drawableTexture = view.currentDrawable?.texture {
                _gBufferAndLightingRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = drawableTexture
                _gBufferAndLightingRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
                _gBufferAndLightingRenderPassDescriptor.stencilAttachment.texture = view.depthStencilTexture

                encodeRenderPass(into: commandBuffer, using: _gBufferAndLightingRenderPassDescriptor, label: "GBuffer & Lighting Pass") {
                    renderEncoder in
                    SceneManager.SetSceneConstants(with: renderEncoder)
                    SceneManager.SetDirectionalLightConstants(with: renderEncoder)

                    encodeGBufferStage(using: renderEncoder)
                    encodeDirectionalLightingStage(using: renderEncoder)
                    encodeTransparencyStage(using: renderEncoder)
                    encodeLightMaskStage(using: renderEncoder)
                    encodePointLightStage(using: renderEncoder)
                    encodeSkyboxStage(using: renderEncoder)
                }
            }

            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
        }
    }
}

// After
override func draw(in view: MTKView) {
    render {
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeShadowMapPass(into: commandBuffer)
        }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "GBuffer & Lighting Commands"

            // view.depthStencilTexture does NOT acquire the drawable; safe to reference here.
            _gBufferAndLightingRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
            _gBufferAndLightingRenderPassDescriptor.stencilAttachment.texture = view.depthStencilTexture

            encodeRenderPass(into: commandBuffer,
                             using: _gBufferAndLightingRenderPassDescriptor,
                             label: "GBuffer & Lighting Pass") { renderEncoder in
                SceneManager.SetSceneConstants(with: renderEncoder)
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)

                encodeGBufferStage(using: renderEncoder)
                encodeDirectionalLightingStage(using: renderEncoder)
                encodeTransparencyStage(using: renderEncoder)
                encodeLightMaskStage(using: renderEncoder)
                encodePointLightStage(using: renderEncoder)
                encodeSkyboxStage(using: renderEncoder)
            }
        }

        guard let drawable = view.currentDrawable else { return }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Composite + Present"
            compositeRenderPassDescriptor
                .colorAttachments[TFSRenderTargetLighting.index].texture = drawable.texture

            encodeRenderPass(into: commandBuffer,
                             using: compositeRenderPassDescriptor,
                             label: "Composite Pass") { renderEncoder in
                encodeCompositeStage(using: renderEncoder)
            }

            commandBuffer.present(drawable)
        }
    }
}
```

---

### 2.3 `TiledMultisampleRenderer.swift`

MSAA + particles + composite-as-self-blit. Biggest change because we now own both the MSAA color texture AND the resolve texture, instead of copying them from `view.currentRenderPassDescriptor`.

**Class declaration (line 10):**
```swift
// Before
final class TiledMultisampleRenderer: Renderer, ShadowRendering, ParticleRendering, @unchecked Sendable {

// After
final class TiledMultisampleRenderer: Renderer, ShadowRendering, ParticleRendering, LateDrawablePresenting, @unchecked Sendable {
```

**New stored properties (after line 17):**
```swift
var lightingResolveTexture: MTLTexture!
private var lightingMSAATexture: MTLTexture!
```

**Replace existing `compositeRenderPassDescriptor` (lines 48–54):**
```swift
// Before
private let compositeRenderPassDescriptor: MTLRenderPassDescriptor = {
    let descriptor = MTLRenderPassDescriptor()
    descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
    descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
    descriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .store
    return descriptor
}()

// After
let compositeRenderPassDescriptor: MTLRenderPassDescriptor = Self.makeCompositeRenderPassDescriptor()
```

**Delete the local `encodeCompositeStage` (lines 144–151)** — the protocol provides it. Keep `encodeMSAAResolveStage`.

**`updateDrawableSize` (lines 216–224):**
```swift
// Before
func updateDrawableSize(size: CGSize) {
    gBufferTextures.makeTextures(device: Engine.Device,
                                 size: size,
                                 storageMode: .memoryless,
                                 sampleCount: Self.sampleCount)
    setGBufferTextures(tiledDeferredRenderPassDescriptor)
    updateScreenSize(size: size)
}

// After
func updateDrawableSize(size: CGSize) {
    gBufferTextures.makeTextures(device: Engine.Device,
                                 size: size,
                                 storageMode: .memoryless,
                                 sampleCount: Self.sampleCount)

    lightingMSAATexture    = Self.makeMSAALightingTexture(size: size, sampleCount: Self.sampleCount)
    lightingResolveTexture = Self.makeLightingResolveTexture(size: size, label: "TiledMSAA Lighting Resolve")

    let lighting = tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index]!
    lighting.texture        = lightingMSAATexture
    lighting.resolveTexture = lightingResolveTexture
    // loadAction/clearColor/storeAction = .multisampleResolve already set in static init.

    setGBufferTextures(tiledDeferredRenderPassDescriptor)
    updateScreenSize(size: size)
}
```

**`draw(in:)` (lines 155–208):**
```swift
// Before
override func draw(in view: MTKView) {
    view.sampleCount = Self.sampleCount

    if firstRun {
        let screenSize = CGSize(width: CGFloat(Renderer.ScreenSize.x),
                                height: CGFloat(Renderer.ScreenSize.y))
        updateDrawableSize(size: screenSize)
        firstRun.toggle()
    }

    render {
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeMSAAShadowPass(into: commandBuffer)
        }

        if let drawable = view.currentDrawable {
            runDrawableCommands { commandBuffer in
                commandBuffer.label = "GBuffer & Lighting Commands"
                let viewColorAttachment = view.currentRenderPassDescriptor!.colorAttachments[TFSRenderTargetLighting.index]
                tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index] = viewColorAttachment

                encodeParticleComputePass(into: commandBuffer)

                encodeRenderPass(into: commandBuffer,
                                 using: tiledDeferredRenderPassDescriptor,
                                 label: "GBuffer & Lighting Pass") { renderEncoder in
                    SceneManager.SetSceneConstants(with: renderEncoder)
                    SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                    SceneManager.SetPointLightData(with: renderEncoder)

                    encodeGBufferStage(using: renderEncoder)
                    encodeLightingStage(using: renderEncoder)
                    encodeTransparencyStage(using: renderEncoder)
                    encodeParticleRenderStage(using: renderEncoder, withMSAA: true)

                    encodeMSAAResolveStage(using: renderEncoder)
                }

                compositeRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .store
                compositeRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = drawable.texture

                encodeRenderPass(into: commandBuffer,
                                 using: compositeRenderPassDescriptor,
                                 label: "Composite Pass") { renderEncoder in
                    encodeCompositeStage(using: renderEncoder)
                }

                commandBuffer.present(drawable)
            }
        }
    }
}

// After
override func draw(in view: MTKView) {
    view.sampleCount = Self.sampleCount

    if firstRun {
        let screenSize = CGSize(width: CGFloat(Renderer.ScreenSize.x),
                                height: CGFloat(Renderer.ScreenSize.y))
        updateDrawableSize(size: screenSize)
        firstRun.toggle()
    }

    render {
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeMSAAShadowPass(into: commandBuffer)
        }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "GBuffer & Lighting Commands"

            encodeParticleComputePass(into: commandBuffer)

            encodeRenderPass(into: commandBuffer,
                             using: tiledDeferredRenderPassDescriptor,
                             label: "GBuffer & Lighting Pass") { renderEncoder in
                SceneManager.SetSceneConstants(with: renderEncoder)
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                SceneManager.SetPointLightData(with: renderEncoder)

                encodeGBufferStage(using: renderEncoder)
                encodeLightingStage(using: renderEncoder)
                encodeTransparencyStage(using: renderEncoder)
                encodeParticleRenderStage(using: renderEncoder, withMSAA: true)

                encodeMSAAResolveStage(using: renderEncoder)
            }
        }

        guard let drawable = view.currentDrawable else { return }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Composite + Present"
            compositeRenderPassDescriptor
                .colorAttachments[TFSRenderTargetLighting.index].texture = drawable.texture

            encodeRenderPass(into: commandBuffer,
                             using: compositeRenderPassDescriptor,
                             label: "Composite Pass") { renderEncoder in
                encodeCompositeStage(using: renderEncoder)
            }

            commandBuffer.present(drawable)
        }
    }
}
```

---

### 2.4 `TiledMSAATessellatedRenderer.swift`

Identical to TiledMultisample plus a tessellation compute pass and tessellation render stage.

**Class declaration (line 10):**
```swift
// Before
final class TiledMSAATessellatedRenderer:   Renderer,
                                            ShadowRendering,
                                            ParticleRendering,
                                            TessellationRendering,
                                            @unchecked Sendable {

// After
final class TiledMSAATessellatedRenderer:   Renderer,
                                            ShadowRendering,
                                            ParticleRendering,
                                            TessellationRendering,
                                            LateDrawablePresenting,
                                            @unchecked Sendable {
```

**New stored properties (after line 21):**
```swift
var lightingResolveTexture: MTLTexture!
private var lightingMSAATexture: MTLTexture!
```

**Replace existing `compositeRenderPassDescriptor` (lines 52–58):**
```swift
let compositeRenderPassDescriptor: MTLRenderPassDescriptor = Self.makeCompositeRenderPassDescriptor()
```

**Delete the local `encodeCompositeStage` (lines 154–162).** Keep `encodeMSAAResolveStage`.

**`updateDrawableSize` (lines 228–236):** Same pattern as TiledMultisample:
```swift
func updateDrawableSize(size: CGSize) {
    gBufferTextures.makeTextures(device: Engine.Device,
                                 size: size,
                                 storageMode: .memoryless,
                                 sampleCount: Self.sampleCount)

    lightingMSAATexture    = Self.makeMSAALightingTexture(size: size, sampleCount: Self.sampleCount)
    lightingResolveTexture = Self.makeLightingResolveTexture(size: size, label: "TiledMSAATess Lighting Resolve")

    let lighting = tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index]!
    lighting.texture        = lightingMSAATexture
    lighting.resolveTexture = lightingResolveTexture

    setGBufferTextures(tiledDeferredRenderPassDescriptor)
    updateScreenSize(size: size)
}
```

**`draw(in:)` (lines 166–220):**
```swift
// Before
override func draw(in view: MTKView) {
    view.sampleCount = Self.sampleCount

    if firstRun {
        let screenSize = CGSize(width: CGFloat(Renderer.ScreenSize.x),
                                height: CGFloat(Renderer.ScreenSize.y))
        updateDrawableSize(size: screenSize)
        firstRun.toggle()
    }

    render {
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeMSAAShadowPass(into: commandBuffer)
        }

        if let drawable = view.currentDrawable {
            runDrawableCommands { commandBuffer in
                commandBuffer.label = "GBuffer & Lighting Commands"
                let viewColorAttachment = view.currentRenderPassDescriptor!.colorAttachments[TFSRenderTargetLighting.index]
                tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index] = viewColorAttachment

                encodeParticleComputePass(into: commandBuffer)
                encodeTessellationComputePass(into: commandBuffer)

                encodeRenderPass(into: commandBuffer,
                                 using: tiledDeferredRenderPassDescriptor,
                                 label: "GBuffer & Lighting Pass") { renderEncoder in
                    SceneManager.SetSceneConstants(with: renderEncoder)
                    SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                    SceneManager.SetPointLightData(with: renderEncoder)

                    encodeTessellationRenderPass(with: renderEncoder)
                    encodeGBufferStage(using: renderEncoder)
                    encodeLightingStage(using: renderEncoder)
                    encodeTransparencyStage(using: renderEncoder)
                    encodeParticleRenderStage(using: renderEncoder, withMSAA: true)

                    encodeMSAAResolveStage(using: renderEncoder)
                }

                compositeRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .store
                compositeRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = drawable.texture

                encodeRenderPass(into: commandBuffer,
                                 using: compositeRenderPassDescriptor,
                                 label: "Composite Pass") { renderEncoder in
                    encodeCompositeStage(using: renderEncoder)
                }

                commandBuffer.present(drawable)
            }
        }
    }
}

// After
override func draw(in view: MTKView) {
    view.sampleCount = Self.sampleCount

    if firstRun {
        let screenSize = CGSize(width: CGFloat(Renderer.ScreenSize.x),
                                height: CGFloat(Renderer.ScreenSize.y))
        updateDrawableSize(size: screenSize)
        firstRun.toggle()
    }

    render {
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeMSAAShadowPass(into: commandBuffer)
        }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "GBuffer & Lighting Commands"

            encodeParticleComputePass(into: commandBuffer)
            encodeTessellationComputePass(into: commandBuffer)

            encodeRenderPass(into: commandBuffer,
                             using: tiledDeferredRenderPassDescriptor,
                             label: "GBuffer & Lighting Pass") { renderEncoder in
                SceneManager.SetSceneConstants(with: renderEncoder)
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                SceneManager.SetPointLightData(with: renderEncoder)

                encodeTessellationRenderPass(with: renderEncoder)
                encodeGBufferStage(using: renderEncoder)
                encodeLightingStage(using: renderEncoder)
                encodeTransparencyStage(using: renderEncoder)
                encodeParticleRenderStage(using: renderEncoder, withMSAA: true)

                encodeMSAAResolveStage(using: renderEncoder)
            }
        }

        guard let drawable = view.currentDrawable else { return }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Composite + Present"
            compositeRenderPassDescriptor
                .colorAttachments[TFSRenderTargetLighting.index].texture = drawable.texture

            encodeRenderPass(into: commandBuffer,
                             using: compositeRenderPassDescriptor,
                             label: "Composite Pass") { renderEncoder in
                encodeCompositeStage(using: renderEncoder)
            }

            commandBuffer.present(drawable)
        }
    }
}
```

---

## 3. Pitfalls and Notes

1. **Pixel format / color space.** Both `lightingResolveTexture` and `drawable.texture` use `Preferences.MainPixelFormat` (`.bgra8Unorm_srgb`). The composite shader's sRGB-aware sample-then-write is correct for an sRGB-in, sRGB-out copy. If `Preferences.MainPixelFormat` ever changes, both follow it because the protocol uses the constant.

2. **`storeAction` for the lighting attachment.** SinglePassDeferred and TiledDeferred currently rely on the default store action (which has been `.store` historically but is best to set explicitly now that the texture is app-owned and read by a subsequent pass). Both descriptors are updated to set `.store` explicitly. The two MSAA renderers already set `.multisampleResolve`; left alone.

3. **`view.depthStencilTexture` is NOT drawable-tied.** It's a separately-allocated MTKView property based on `depthStencilPixelFormat`, independent of `currentDrawable`. SinglePassDeferred can keep using it. Allocating an app-owned depth/stencil is a follow-up, not in scope.

4. **MSAA descriptor invariant.** When `storeAction = .multisampleResolve`, both `texture` (MSAA) and `resolveTexture` (single-sample) MUST be non-nil. Both are now bound in `updateDrawableSize` and never per-frame, so a missed resize will surface as a Metal validation failure.

5. **Resize safety.** In-flight CBs hold strong references to the old textures via the encoder snapshot; reallocating new ones in `updateDrawableSize` is safe. `mtkView(_:drawableSizeWillChange:)` and `draw(in:)` are both main-thread-callbacks and cannot run concurrently.

6. **Frame-skip semantics.** If `view.currentDrawable` returns nil in the late CB, the early CBs still execute and `lightingResolveTexture` is overwritten next frame. No leak; on-screen frame is simply skipped. Same as today.

7. **`compositeRenderPassDescriptor` uses `loadAction = .dontCare`** rather than `.clear` (small bandwidth win — the composite shader writes every pixel). Diverges from the current `.clear` in both MSAA renderers.

8. **`maxFramesInFlight` is unchanged.** Three CBs per frame still respect the wait/signal contract since each `runDrawableCommands` waits and signals exactly once. If Metal System Trace later shows the early CBs throttled, bumping the semaphore value is a follow-up.

9. **Single texture, not ring-buffered.** Matches the codebase's convention (shadow maps, GBuffer textures). The `inFlightSemaphore` serializes frames sufficiently. Ring-buffering is a follow-up if System Trace shows the next frame's early CB stalling on the previous frame's late CB read.

## 4. Implementation Order

1. Create `LateDrawablePresenting.swift`.
2. Refactor `TiledDeferredRenderer` (simplest). Build & visually verify.
3. Refactor `SinglePassDeferredLightingRenderer`. Build & visually verify.
4. Refactor `TiledMultisampleRenderer` (introduces MSAA color + resolve pair). Build & visually verify.
5. Refactor `TiledMSAATessellatedRenderer`. Build & visually verify.
6. Run full verification (§5).

## 5. Verification

### 5.1 Build

```bash
# macOS Debug
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# macOS Release
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# iOS Simulator (cross-platform sanity check)
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug

# Tests
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### 5.2 Visual correctness (per renderer, switched via macOS menu)

For each of the four renderers:
- Load a non-trivial scene (FlightboxScene with terrain, particles, MSAA where applicable).
- Image should be visually identical to pre-refactor.
- Resize the window to multiple sizes — no crashes, no validation errors, no stale image.
- Switch between renderers via menu — no crashes, each renderer rebuilds its textures.

For renderer-specific checks:
- **SinglePassDeferred**: skybox visible behind objects.
- **TiledDeferred**: particles visible.
- **TiledMultisample**: 4× MSAA edges look smooth, particles visible.
- **TiledMSAATessellated**: terrain tessellation, particles, MSAA all visible.

Capture a frame in Xcode → Debug → Capture GPU Frame and verify:
- `lightingResolveTexture` contents at end of GBuffer/Lighting pass match pre-refactor drawable contents.
- Drawable texture at end of Composite pass is identical (composite shader is a copy).

### 5.3 Latency win (the actual goal)

Two complementary measurements, before and after the refactor:

1. **Metal Performance HUD**: Set `MTL_HUD_ENABLED=1` in the scheme's environment. Compare frame-interval graph at 60 Hz and 120 Hz (ProMotion). Peak (red) frame-interval values should be lower or eliminated; mean unchanged.

2. **Instruments → Metal System Trace**: Capture 5–10 seconds at steady state. Look for:
   - "Thread blocked waiting for next drawable" annotations should be absent or moved to the start of the late CB only.
   - Early CB's GBuffer/Lighting pass should start GPU execution before the CPU calls `view.currentDrawable`.
   - Late CB's composite pass should be measured in tens of µs.

### 5.4 Tests

```bash
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
`RendererTests` and `NodeTests` should all pass. They don't exercise the drawable path; this is a regression sanity check.

## 6. Out of Scope (Follow-Ups)

- App-owned depth/stencil for SinglePassDeferred (symmetry win, not a latency win).
- Ring-buffered `lightingResolveTexture` (only if System Trace shows next-frame stall).
- Apply same pattern to `OITRenderer` and `ForwardPlusTileShadingRenderer`.
- Bump `maxFramesInFlight` from 3 to 9 if the tightened CB pacing causes throttling.
