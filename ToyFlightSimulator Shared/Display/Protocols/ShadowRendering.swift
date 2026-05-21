//
//  ShadowRendering.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

import MetalKit

protocol ShadowRendering: RenderPassEncoding {
    static var ShadowMapSize: Int { get }
    static var CascadeCount: Int { get }
    /// Texture2DArray, arrayLength = CascadeCount. Sampled by the GBuffer/
    /// lighting shaders. For non-MSAA renderers this is also the render
    /// target of the shadow generation passes. For MSAA renderers this is
    /// the resolve destination of `shadowMSAATexture` (see below).
    var shadowMaps: MTLTexture { get set }
    /// MSAA path only: single non-array MSAA texture reused across the N
    /// cascade passes as the multisample source. Each cascade pass resolves
    /// into slice `i` of `shadowMaps`. `nil` for non-MSAA renderers.
    var shadowMSAATexture: MTLTexture? { get set }
    /// One render pass descriptor per cascade. `depthAttachment.slice = i`
    /// for descriptor i; everything else identical.
    var shadowRenderPassDescriptors: [MTLRenderPassDescriptor] { get set }
}

extension ShadowRendering {
    // CSM: cascade 0 gets a tight ortho box around the camera at this
    // resolution; deeper cascades cover proportionally more world space with
    // the same texel count. 4096² × 4 cascades = 256 MB total — same memory
    // footprint as the pre-CSM single 8192² shadow map but with the resolution
    // concentrated around the camera. Cascade-0 texel size at radius 300
    // world units = 600/4096 ≈ 0.146 world units (vs 0.293 at 2048).
    //
    // NOTE: must match `LightObject._shadowMapRes` (used for texel-snap math
    // in ShadowCascadeFitting). If you change one, change the other.
    static var ShadowMapSize: Int { 4_096 }
    static var CascadeCount: Int { Int(TFS_MAX_SHADOW_CASCADES) }

    /// Allocate one `MTLTextureType2DArray` with `arrayLength = CascadeCount`.
    /// Sampled by GBuffer/lighting shaders as `depth2d_array<float>`.
    public static func makeShadowMapArray(label: String) -> MTLTexture {
        let desc = MTLTextureDescriptor()
        desc.textureType  = .type2DArray
        desc.pixelFormat  = .depth32Float
        desc.width        = Self.ShadowMapSize
        desc.height       = Self.ShadowMapSize
        desc.arrayLength  = Self.CascadeCount
        desc.mipmapLevelCount = 1
        desc.resourceOptions = .storageModePrivate
        desc.usage = [.renderTarget, .shaderRead]

        guard let tex = Engine.Device.makeTexture(descriptor: desc) else {
            fatalError("[ShadowRendering] Could not create shadow map array texture.")
        }
        tex.label = label
        return tex
    }

    /// Single (non-array) MSAA depth target used by MSAA renderers as the
    /// multisample side of each cascade's render pass. Resolves into the
    /// corresponding slice of `shadowMaps`. One texture is reused across all
    /// N cascade passes — within a single command buffer, the MSAA contents
    /// are throw-away once the resolve writes the array slice.
    public static func makeShadowMSAATarget(label: String, sampleCount: Int) -> MTLTexture {
        let desc = MTLTextureDescriptor()
        desc.textureType  = .type2DMultisample
        desc.pixelFormat  = .depth32Float
        desc.width        = Self.ShadowMapSize
        desc.height       = Self.ShadowMapSize
        desc.sampleCount  = sampleCount
        desc.resourceOptions = .storageModePrivate
        desc.usage = [.renderTarget]
        guard let tex = Engine.Device.makeTexture(descriptor: desc) else {
            fatalError("[ShadowRendering] Could not create MSAA shadow target.")
        }
        tex.label = label
        return tex
    }

    /// Build `CascadeCount` render pass descriptors, each targeting one slice
    /// of the shadow map array.
    public static func makeShadowRenderPassDescriptors(shadowMapArray: MTLTexture) -> [MTLRenderPassDescriptor] {
        (0..<Self.CascadeCount).map { i in
            let desc = MTLRenderPassDescriptor()
            desc.depthAttachment.texture     = shadowMapArray
            desc.depthAttachment.slice       = i
            desc.depthAttachment.level       = 0
            desc.depthAttachment.loadAction  = .clear
            desc.depthAttachment.storeAction = .store
            return desc
        }
    }

    /// MSAA variant: render into a shared MSAA target each cascade pass,
    /// resolve into slice `i` of the shadow map array.
    static func makeMSAAShadowRenderPassDescriptors(msaaTexture: MTLTexture,
                                                    resolveArray: MTLTexture) -> [MTLRenderPassDescriptor] {
        (0..<Self.CascadeCount).map { i in
            let desc = MTLRenderPassDescriptor()
            desc.depthAttachment.texture        = msaaTexture
            desc.depthAttachment.resolveTexture = resolveArray
            desc.depthAttachment.resolveSlice   = i
            desc.depthAttachment.loadAction     = .clear
            desc.depthAttachment.storeAction    = .multisampleResolve
            return desc
        }
    }

    // MARK: - Cascade-VP tuple read helper

    /// Read the i-th cascade view-projection matrix out of LightData's
    /// homogeneous-tuple `cascadeViewProjectionMatrices` field. Symmetric to
    /// `LightObject.writeCascadeMatrices` on the write side.
    private func cascadeVP(at i: Int, in light: LightObject) -> matrix_float4x4 {
        return withUnsafePointer(to: light.lightData.cascadeViewProjectionMatrices) { tuplePtr in
            tuplePtr.withMemoryRebound(to: matrix_float4x4.self, capacity: 4) { $0[i] }
        }
    }

    // MARK: - Per-cascade shadow generation passes

    /// Iterate over cascades, encoding one shadow generation pass per slice.
    /// Used by `SinglePassDeferredLightingRenderer`.
    func encodeShadowMapPass(into commandBuffer: MTLCommandBuffer) {
        let directionalLights = LightManager.GetLightObjects(lightType: Directional)
        guard let primaryLight = directionalLights.first else { return }
        let cascadeCount = Int(primaryLight.lightData.cascadeCount)

        for i in 0..<min(cascadeCount, Self.CascadeCount) {
            var cascadeVPLocal = cascadeVP(at: i, in: primaryLight)
            encodeRenderPass(into: commandBuffer,
                             using: shadowRenderPassDescriptors[i],
                             label: "Shadow Map Pass \(i)") { renderEncoder in
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                encodeRenderStage(using: renderEncoder, label: "Shadow Generation Stage \(i)") {
                    setRenderPipelineState(renderEncoder, state: .ShadowGeneration)
                    renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.ShadowGeneration])
                    // CSM: depth bias intentionally not set. The legacy
                    // `setDepthBias(0.1, slopeScale: 1)` was tuned for the
                    // single 4000-world-unit-deep ortho; for smaller cascade
                    // orthos the slope-scaled term peter-pans aircraft
                    // shadows off the ground. The shader-side per-cascade
                    // epsilon (`cascadeWorldSlack[i] / cascadeDepthRange[i]`)
                    // handles depth-compare bias correctly.
                    renderEncoder.setVertexBytes(&cascadeVPLocal,
                                                 length: matrix_float4x4.stride,
                                                 index: TFSBufferIndexShadowCascadeVP.index)
                    DrawManager.DrawShadows(with: renderEncoder)
                }
            }
        }
    }

    /// Tiled deferred shadow pass variant.
    func encodeShadowPassTiledDeferred(into commandBuffer: MTLCommandBuffer) {
        let directionalLights = LightManager.GetLightObjects(lightType: Directional)
        guard let primaryLight = directionalLights.first else { return }
        let cascadeCount = Int(primaryLight.lightData.cascadeCount)

        for i in 0..<min(cascadeCount, Self.CascadeCount) {
            var cascadeVPLocal = cascadeVP(at: i, in: primaryLight)
            encodeRenderPass(into: commandBuffer,
                             using: shadowRenderPassDescriptors[i],
                             label: "Shadow Pass \(i)") { renderEncoder in
                encodeRenderStage(using: renderEncoder, label: "Shadow Texture Stage \(i)") {
                    setRenderPipelineState(renderEncoder, state: .TiledDeferredShadow)
                    renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredShadow])
                    SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                    renderEncoder.setVertexBytes(&cascadeVPLocal,
                                                 length: matrix_float4x4.stride,
                                                 index: TFSBufferIndexShadowCascadeVP.index)
                    DrawManager.DrawOpaque(with: renderEncoder)
                }
            }
        }
    }

    /// MSAA shadow pass variant: renders to the MSAA target each iteration,
    /// resolves into slice `i` of the shadow map array.
    func encodeMSAAShadowPass(into commandBuffer: MTLCommandBuffer) {
        let directionalLights = LightManager.GetLightObjects(lightType: Directional)
        guard let primaryLight = directionalLights.first else { return }
        let cascadeCount = Int(primaryLight.lightData.cascadeCount)

        for i in 0..<min(cascadeCount, Self.CascadeCount) {
            var cascadeVPLocal = cascadeVP(at: i, in: primaryLight)
            encodeRenderPass(into: commandBuffer,
                             using: shadowRenderPassDescriptors[i],
                             label: "MSAA Shadow Pass \(i)") { renderEncoder in
                encodeRenderStage(using: renderEncoder, label: "Shadow Texture Stage \(i)") {
                    setRenderPipelineState(renderEncoder, state: .TiledMSAAShadow)
                    renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredShadow])
                    SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                    renderEncoder.setVertexBytes(&cascadeVPLocal,
                                                 length: matrix_float4x4.stride,
                                                 index: TFSBufferIndexShadowCascadeVP.index)
                    DrawManager.DrawShadows(with: renderEncoder)
                }
            }
        }
    }
}
