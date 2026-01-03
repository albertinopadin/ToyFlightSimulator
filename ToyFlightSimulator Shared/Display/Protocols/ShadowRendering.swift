//
//  ShadowRendering.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

import MetalKit

protocol ShadowRendering: RenderPassEncoding {
    static var ShadowMapSize: Int { get }
    var shadowMap: MTLTexture { get set }
    var shadowResolveTexture: MTLTexture? { get set }
    var shadowRenderPassDescriptor: MTLRenderPassDescriptor { get set }
}

extension ShadowRendering {
    static var ShadowMapSize: Int { 8_192 }
    
    public static func makeShadowMap(label: String, sampleCount: Int = 1) -> MTLTexture {
        let shadowTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                               width: Self.ShadowMapSize,
                                                                               height: Self.ShadowMapSize,
                                                                               mipmapped: false)
        shadowTextureDescriptor.resourceOptions = .storageModePrivate
        shadowTextureDescriptor.usage = [.renderTarget, .shaderRead]
        
        if sampleCount > 1 {
            shadowTextureDescriptor.textureType = .type2DMultisample
            shadowTextureDescriptor.sampleCount = sampleCount
        }
        
        guard let sm = Engine.Device.makeTexture(descriptor: shadowTextureDescriptor) else {
            fatalError("[ShadowRenderer makeShadowMap] Could not create shadow map texture.")
        }
        sm.label = label
        return sm
    }
    
    public static func makeShadowRenderPassDescriptor(shadowMapTexture: MTLTexture) -> MTLRenderPassDescriptor {
        let mShadowRenderPassDescriptor = MTLRenderPassDescriptor()
        mShadowRenderPassDescriptor.depthAttachment.texture = shadowMapTexture
        mShadowRenderPassDescriptor.depthAttachment.loadAction = .clear
        mShadowRenderPassDescriptor.depthAttachment.storeAction = .store
        return mShadowRenderPassDescriptor
    }
    
    static func makeMultiSampledShadowRenderPassDescriptor(shadowTexture: MTLTexture,
                                                           resolveTexture: MTLTexture) -> MTLRenderPassDescriptor {
        let mShadowRenderPassDescriptor = MTLRenderPassDescriptor()
        mShadowRenderPassDescriptor.depthAttachment.texture = shadowTexture
        mShadowRenderPassDescriptor.depthAttachment.resolveTexture = resolveTexture
        mShadowRenderPassDescriptor.depthAttachment.loadAction = .clear
        mShadowRenderPassDescriptor.depthAttachment.storeAction = .multisampleResolve
        return mShadowRenderPassDescriptor
    }
    
    // TODO: Must be doing something wrong because there are strange artifacts, like:
    //       - Seeing shadow of bombs and landing gear through aircraft
    //       - Shadows on 'back side' of jet look odd
    //       - If I pitch or roll jet, shadows look very different on adjacent panels in mesh.
    // ADDENDUM: Might fix issues if I implement soft shadows...
    func encodeShadowMapPass(into commandBuffer: MTLCommandBuffer) {
        encodeRenderPass(into: commandBuffer, using: shadowRenderPassDescriptor, label: "Shadow Map Pass") { renderEncoder in
            SceneManager.SetDirectionalLightConstants(with: renderEncoder)
            encodeRenderStage(using: renderEncoder, label: "Shadow Generation Stage") {
//                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.ShadowGeneration])
                setRenderPipelineState(renderEncoder, state: .ShadowGeneration)
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.ShadowGeneration])
//                renderEncoder.setCullMode(.back)
//                renderEncoder.setCullMode(.front)
//                renderEncoder.setDepthBias(0.015, slopeScale: 7, clamp: 0.02)
                renderEncoder.setDepthBias(0.1, slopeScale: 1, clamp: 0.0)
                DrawManager.DrawShadows(with: renderEncoder)
            }
        }
    }
    
    // TODO: Merge / Refactor into single func
    func encodeShadowPassTiledDeferred(into commandBuffer: MTLCommandBuffer) {
        encodeRenderPass(into: commandBuffer, using: shadowRenderPassDescriptor, label: "Shadow Pass") { renderEncoder in
            encodeRenderStage(using: renderEncoder, label: "Shadow Texture Stage") {
//                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredShadow])
                setRenderPipelineState(renderEncoder, state: .TiledDeferredShadow)
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredShadow])
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                DrawManager.DrawOpaque(with: renderEncoder)  // TODO: Why not DrawShadows ???
            }
        }
    }
    
    func encodeMSAAShadowPass(into commandBuffer: MTLCommandBuffer) {
        encodeRenderPass(into: commandBuffer, using: shadowRenderPassDescriptor, label: "MSAA Shadow Pass") { renderEncoder in
            encodeRenderStage(using: renderEncoder, label: "Shadow Texture Stage") {
//                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAShadow])
                setRenderPipelineState(renderEncoder, state: .TiledMSAAShadow)
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredShadow])
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
//                DrawManager.DrawOpaque(with: renderEncoder)
                DrawManager.DrawShadows(with: renderEncoder)
            }
        }
    }
}
