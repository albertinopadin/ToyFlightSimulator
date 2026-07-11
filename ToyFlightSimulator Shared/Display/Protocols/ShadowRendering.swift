//
//  ShadowRendering.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

import MetalKit

protocol ShadowRendering: RenderPassEncoding {
    static var ShadowMapSize: Int { get }
    static var CascadeCount:  Int { get }

    // Single-sample depth32Float texture2DArray; one slice per cascade. PCF in
    // the shader handles edge softening, so the shadow map itself is never MSAA.
    var shadowMapArray: MTLTexture { get set }
    var shadowRenderPassDescriptors: [MTLRenderPassDescriptor] { get set }
}

extension ShadowRendering {
    static var ShadowMapSize: Int { 4_096 }
    static var CascadeCount:  Int { 4 }

    public static func makeShadowMapArray(label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat      = .depth32Float
        descriptor.width            = Self.ShadowMapSize
        descriptor.height           = Self.ShadowMapSize
        descriptor.arrayLength      = Self.CascadeCount
        descriptor.mipmapLevelCount = 1
        descriptor.textureType      = .type2DArray
        descriptor.resourceOptions  = .storageModePrivate
        descriptor.usage            = [.renderTarget, .shaderRead]

        guard let sm = Engine.Device.makeTexture(descriptor: descriptor) else {
            fatalError("[ShadowRendering makeShadowMapArray] Could not create shadow map array.")
        }
        sm.label = label
        return sm
    }

    public static func makeShadowRenderPassDescriptors(shadowArray: MTLTexture)
                                                       -> [MTLRenderPassDescriptor] {
        precondition(shadowArray.arrayLength == Self.CascadeCount,
                     "Shadow array length (\(shadowArray.arrayLength)) must equal CascadeCount (\(Self.CascadeCount))")
        var descriptors: [MTLRenderPassDescriptor] = []
        descriptors.reserveCapacity(Self.CascadeCount)
        for i in 0..<Self.CascadeCount {
            let d = MTLRenderPassDescriptor()
            d.depthAttachment.texture     = shadowArray
            d.depthAttachment.slice       = i
            d.depthAttachment.loadAction  = .clear
            d.depthAttachment.clearDepth  = 1.0   // forward-Z ortho: far = 1
            d.depthAttachment.storeAction = .store
            descriptors.append(d)
        }
        return descriptors
    }

    /// Reify the active directional light's per-cascade view-projection matrices.
    /// The cascade VPs are camera-independent (built from world-space data), so
    /// the identity view matrix passed here only affects `lightEyeDirection`,
    /// which the shadow pass doesn't read.
    private func cascadeViewProjections() -> [float4x4] {
        guard var light = LightManager.GetDirectionalLightData(viewMatrix: matrix_identity_float4x4).first else {
            return []
        }
        let count = Int(light.cascadeCount)
        guard count > 0 else { return [] }
        return withUnsafePointer(to: &light.cascadeViewProjectionMatrices) { tuplePtr in
            tuplePtr.withMemoryRebound(to: float4x4.self,
                                       capacity: Int(TFS_MAX_SHADOW_CASCADES)) { ptr in
                (0..<count).map { ptr[$0] }
            }
        }
    }

    /// Shared cascade loop: one render pass per cascade slice, binding that
    /// cascade's view-projection matrix as a push constant at
    /// TFSBufferIndexShadowCascadeVP before drawing all shadow casters.
    /// NOTE: no `setDepthBias` — the shader's per-cascade slope-scaled epsilon
    /// handles bias without Peter-panning thin aircraft shadows.
    private func encodeCascadePasses(into commandBuffer: MTLCommandBuffer,
                                     pipeline: RenderPipelineStateType,
                                     depthStencil: DepthStencilStateType) {
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
                    DrawManager.DrawShadows(with: renderEncoder, psoType: pipeline)
                }
            }
        }
    }

    func encodeShadowMapPass(into commandBuffer: MTLCommandBuffer) {
        encodeCascadePasses(into: commandBuffer, pipeline: .ShadowGeneration, depthStencil: .ShadowGeneration)
    }

    func encodeShadowPassTiledDeferred(into commandBuffer: MTLCommandBuffer) {
        encodeCascadePasses(into: commandBuffer, pipeline: .TiledDeferredShadow, depthStencil: .TiledDeferredShadow)
    }

    func encodeMSAAShadowPass(into commandBuffer: MTLCommandBuffer) {
        encodeCascadePasses(into: commandBuffer, pipeline: .TiledMSAAShadow, depthStencil: .TiledDeferredShadow)
    }
}
