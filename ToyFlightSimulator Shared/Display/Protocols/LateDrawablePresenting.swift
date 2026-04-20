//
//  LateDrawablePresenting.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/19/26.
//
//  Shared infrastructure for renderers that defer Metal drawable acquisition
//  until immediately before a final composite-into-drawable pass, per Apple's
//  "acquire late, release early" guidance (Metal Best Practices Guide → Drawables;
//  WWDC 2019 Session 606 "Delivering Optimized Metal Apps and Games").
//
//  Conforming renderers maintain an app-owned `lightingResolveTexture` that the
//  GBuffer/lighting pass writes into, then perform a trivial full-screen quad
//  composite into `drawable.texture` in a separate (late) command buffer.
//

import MetalKit

protocol LateDrawablePresenting: RenderPassEncoding {
    var lightingResolveTexture: MTLTexture! { get set }
    var compositeRenderPassDescriptor: MTLRenderPassDescriptor { get }
}

extension LateDrawablePresenting {
    /// Single-sample app-owned color texture that the GBuffer/lighting pass
    /// resolves into. Cannot be `.memoryless` because it must persist across
    /// render passes (written by the GBuffer pass, sampled by the composite pass).
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
    /// `.memoryless` is correct: TBDR resolves it in tile memory at end-of-pass
    /// and only the resolve target lives in main memory.
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

    /// `loadAction = .dontCare` because the composite shader writes every pixel
    /// of the drawable, so a clear is wasted bandwidth.
    /// `.texture` is set per-frame to `drawable.texture` in the late CB.
    static func makeCompositeRenderPassDescriptor() -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        let lighting = descriptor.colorAttachments[TFSRenderTargetLighting.index]!
        lighting.loadAction  = .dontCare
        lighting.storeAction = .store
        return descriptor
    }

    /// Shared composite stage: full-screen quad sampling `lightingResolveTexture`,
    /// writing to whatever the encoder's color attachment is bound to (the drawable).
    func encodeCompositeStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Composite Stage") {
            setRenderPipelineState(renderEncoder, state: .Composite)
            renderEncoder.setFragmentTexture(lightingResolveTexture, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
}
