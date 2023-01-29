//
//  SinglePassDeferredRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/28/23.
//

import MetalKit

class SinglePassDeferredRenderer: Renderer {
    private let _gBufferAndLightingRenderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[Int(TFSRenderTargetAlbedo.rawValue)].storeAction = .dontCare
        descriptor.colorAttachments[Int(TFSRenderTargetNormal.rawValue)].storeAction = .dontCare
        descriptor.colorAttachments[Int(TFSRenderTargetDepth.rawValue)].storeAction = .dontCare
        return descriptor
    }()
    
    private var gBufferTextures = GBufferTextures()
    
    override init(_ mtkView: MTKView) {
        super.init(mtkView)
    }
    
    func setGBufferTextures(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFragmentTexture(gBufferTextures.albedoSpecular, index: Int(TFSRenderTargetAlbedo.rawValue))
        renderEncoder.setFragmentTexture(gBufferTextures.normalShadow, index: Int(TFSRenderTargetNormal.rawValue))
        renderEncoder.setFragmentTexture(gBufferTextures.depth, index: Int(TFSRenderTargetDepth.rawValue))
    }
    
    func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "GBuffer Generation Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.GBufferGeneration])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.GBufferGeneration])
            renderEncoder.setCullMode(.back)
            renderEncoder.setStencilReferenceValue(128)
//            renderEncoder.setVertexBuffer(scene.frameData, offset: 0, index: Int(TFSBufferFrameData.rawValue))
//            renderEncoder.setFragmentBuffer(scene.frameData, offset: 0, index: Int(AAPLBufferFrameData.rawValue))
            renderEncoder.setFragmentTexture(shadowMap, index: Int(TFSTextureIndexShadow.rawValue))
//            renderEncoder.draw(meshes: scene.meshes)
        }
    }
    
    func encodeDirectionalLightingStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Directional Lighting Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.DirectionalLighting])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.DirectionalLighting])
            setGBufferTextures(renderEncoder: renderEncoder)
            renderEncoder.setCullMode(.back)
            renderEncoder.setStencilReferenceValue(128)
            
//            renderEncoder.setVertexBuffer(scene.quadVertexBuffer,
//                                          offset: 0,
//                                          index: Int(AAPLBufferIndexMeshPositions.rawValue))
//
//            renderEncoder.setVertexBuffer(scene.frameData,
//                                          offset: 0,
//                                          index: Int(AAPLBufferFrameData.rawValue))
//
//            renderEncoder.setFragmentBuffer(scene.frameData,
//                                            offset: 0,
//                                            index: Int(AAPLBufferFrameData.rawValue))
            
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    func encodeLightMaskStage(using renderEncoder: MTLRenderCommandEncoder) {
        // TODO: Get Light Mask pipeline state and depth stencil state here
        encodeStage(using: renderEncoder, label: "Point Light Mask Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.LightMask])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LightMask])
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setCullMode(.front)
            
//            renderEncoder.setVertexBuffer(scene.frameData,
//                                          offset: 0,
//                                          index: Int(AAPLBufferFrameData.rawValue))
//
//            renderEncoder.setVertexBuffer(scene.pointLights,
//                                          offset: 0,
//                                          index: Int(AAPLBufferIndexLightsData.rawValue))
//
//            renderEncoder.setVertexBuffer(scene.lightPositions,
//                                          offset: 0,
//                                          index: Int(AAPLBufferIndexLightsPosition.rawValue))
//
//            renderEncoder.setFragmentBuffer(scene.frameData,
//                                            offset: 0,
//                                            index: Int(AAPLBufferFrameData.rawValue))
//
//            renderEncoder.draw(meshes: [scene.icosahedron],
//                               instanceCount: scene.numberOfLights,
//                               requiresMaterials: false)
        }
    }
    
    func encodePointLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Point Light Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.PointLight])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.PointLight])
            setGBufferTextures(renderEncoder: renderEncoder)
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setCullMode(.back)
            
//            renderEncoder.setVertexBuffer(scene.frameData,
//                                          offset: 0,
//                                          index: Int(AAPLBufferFrameData.rawValue))
//
//            renderEncoder.setVertexBuffer(scene.pointLights,
//                                          offset: 0,
//                                          index: Int(AAPLBufferIndexLightsData.rawValue))
//
//            renderEncoder.setVertexBuffer(scene.lightPositions,
//                                          offset: 0,
//                                          index: Int(AAPLBufferIndexLightsPosition.rawValue))
//
//            renderEncoder.setFragmentBuffer(scene.frameData,
//                                            offset: 0,
//                                            index: Int(AAPLBufferFrameData.rawValue))
//
//            renderEncoder.setFragmentBuffer(scene.pointLights,
//                                            offset: 0,
//                                            index: Int(AAPLBufferIndexLightsData.rawValue))
//
//            renderEncoder.setFragmentBuffer(scene.lightPositions,
//                                            offset: 0,
//                                            index: Int(AAPLBufferIndexLightsPosition.rawValue))
//
//            renderEncoder.draw(meshes: [scene.icosahedron],
//                               instanceCount: scene.numberOfLights,
//                               requiresMaterials: false)
        }
    }
    
    func encodeSkyboxStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Skybox Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Skybox])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Skybox])
            renderEncoder.setCullMode(.front)
            
//            renderEncoder.setVertexBuffer(scene.frameData, offset: 0, index: Int(AAPLBufferFrameData.rawValue))
//            renderEncoder.setFragmentTexture(scene.skyMap, index: Int(AAPLTextureIndexBaseColor.rawValue))
//
//            renderEncoder.draw(meshes: [scene.skyMesh],
//                               requiresMaterials: false)
        }
    }
    
    func encodeShadowMapPass(into commandBuffer: MTLCommandBuffer) {
        encodePass(into: commandBuffer, using: shadowRenderPassDescriptor, label: "Shadow Map Pass") { renderEncoder in
            encodeStage(using: renderEncoder, label: "Shadow Generation Stage") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.ShadowGeneration])
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.ShadowGeneration])
                renderEncoder.setCullMode(.back)
                renderEncoder.setDepthBias(0.015, slopeScale: 7, clamp: 0.02)
                
//                renderEncoder.setVertexBuffer(scene.frameData, offset: 0, index: Int(AAPLBufferFrameData.rawValue))
//                
//                // The Shadow Command does not need mesh materials.
//                renderEncoder.draw(meshes: scene.meshes, requiresMaterials: false)
            }
        }
    }
    
}
