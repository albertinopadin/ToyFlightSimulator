//
//  SinglePassDeferredRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/28/23.
//

import MetalKit

class SinglePassDeferredLightingRenderer: Renderer {
    // Create quad for fullscreen composition drawing
    private let _quadVertices: [TFSSimpleVertex] = [
        .init(position: .init(x: -1, y: -1)),
        .init(position: .init(x: -1, y:  1)),
        .init(position: .init(x:  1, y: -1)),
        
        .init(position: .init(x:  1, y: -1)),
        .init(position: .init(x: -1, y:  1)),
        .init(position: .init(x:  1, y:  1))
    ]
    
    private let _quadVertexBuffer: MTLBuffer!
    
    private let _gBufferAndLightingRenderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[Int(TFSRenderTargetAlbedo.rawValue)].storeAction = .dontCare
        descriptor.colorAttachments[Int(TFSRenderTargetNormal.rawValue)].storeAction = .dontCare
        descriptor.colorAttachments[Int(TFSRenderTargetDepth.rawValue)].storeAction = .dontCare
        return descriptor
    }()
    
    private var gBufferTextures = GBufferTextures()
    
    override init(_ mtkView: MTKView) {
        _quadVertexBuffer = Engine.Device.makeBuffer(bytes: _quadVertices,
                                                     length: MemoryLayout<TFSSimpleVertex>.stride * _quadVertices.count)
        super.init(mtkView)
    }
    
    func setGBufferTextures(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFragmentTexture(gBufferTextures.albedoSpecular, index: Int(TFSRenderTargetAlbedo.rawValue))
        renderEncoder.setFragmentTexture(gBufferTextures.normalShadow, index: Int(TFSRenderTargetNormal.rawValue))
        renderEncoder.setFragmentTexture(gBufferTextures.depth, index: Int(TFSRenderTargetDepth.rawValue))
    }
    
    func setGBufferTextures(_ renderPassDescriptor: MTLRenderPassDescriptor) {
        renderPassDescriptor.colorAttachments[Int(TFSRenderTargetAlbedo.rawValue)].texture = gBufferTextures.albedoSpecular
        renderPassDescriptor.colorAttachments[Int(TFSRenderTargetNormal.rawValue)].texture = gBufferTextures.normalShadow
        renderPassDescriptor.colorAttachments[Int(TFSRenderTargetDepth.rawValue)].texture = gBufferTextures.depth
    }
    
    func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "GBuffer Generation Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.GBufferGenerationMaterial])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.GBufferGeneration])
            // NOTE: For some reason, setting cull mode to back makes meshes appear 'extruded' or turned inside out.
//            renderEncoder.setCullMode(.back)  // TODO: Set this on ???
//            renderEncoder.setCullMode(.front)
            renderEncoder.setStencilReferenceValue(128)
            SceneManager.SetSceneConstants(renderCommandEncoder: renderEncoder)
            SceneManager.SetDirectionalLightConstants(renderCommandEncoder: renderEncoder)
            renderEncoder.setFragmentTexture(shadowMap, index: Int(TFSTextureIndexShadow.rawValue))
            SceneManager.RenderGBuffer(renderCommandEncoder: renderEncoder)
        }
    }
    
    func encodeDirectionalLightingStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Directional Lighting Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.DirectionalLighting])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.DirectionalLighting])
            renderEncoder.setCullMode(.back)
            renderEncoder.setStencilReferenceValue(128)
            
            renderEncoder.setVertexBuffer(_quadVertexBuffer,
                                          offset: 0,
                                          index: Int(TFSBufferIndexMeshPositions.rawValue))
            
            SceneManager.SetSceneConstants(renderCommandEncoder: renderEncoder)
            SceneManager.SetDirectionalLightConstants(renderCommandEncoder: renderEncoder)
            
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    func encodeLightMaskStage(using renderEncoder: MTLRenderCommandEncoder) {
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
            
            SceneManager.SetSceneConstants(renderCommandEncoder: renderEncoder)
            SceneManager.SetPointLightConstants(renderCommandEncoder: renderEncoder)
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
            
            SceneManager.SetSceneConstants(renderCommandEncoder: renderEncoder)
            SceneManager.SetPointLightConstants(renderCommandEncoder: renderEncoder)
        }
    }
    
    func encodeSkyboxStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Skybox Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Skybox])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Skybox])
//            renderEncoder.setCullMode(.front)
//            renderEncoder.setCullMode(.back)  <-- This or not setting the cull mode works. WTF?
            
            SceneManager.SetSceneConstants(renderCommandEncoder: renderEncoder)
            SceneManager.Render(renderCommandEncoder: renderEncoder, renderPipelineStateType: .Skybox, applyMaterials: false)
        }
    }
    
    // TODO: Must be doing something wrong because there are strange artifacts, like:
    //       - Seeing shadow of bombs and landing gear through aircraft
    //       - Shadows on 'back side' of jet look odd
    //       - If I pitch or roll jet, shadows look very different on adjacent panels in mesh.
    func encodeShadowMapPass(into commandBuffer: MTLCommandBuffer) {
        encodePass(into: commandBuffer, using: shadowRenderPassDescriptor, label: "Shadow Map Pass") { renderEncoder in
            encodeStage(using: renderEncoder, label: "Shadow Generation Stage") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.ShadowGeneration])
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.ShadowGeneration])
                renderEncoder.setCullMode(.back)
//                renderEncoder.setDepthBias(0.015, slopeScale: 7, clamp: 0.02)
//                renderEncoder.setDepthBias(0.015, slopeScale: 1, clamp: 0.02)
//                renderEncoder.setDepthBias(0.001, slopeScale: 2, clamp: 1)
                renderEncoder.setDepthBias(0.001, slopeScale: 1, clamp: 0.02)
                SceneManager.SetDirectionalLightConstants(renderCommandEncoder: renderEncoder)
                SceneManager.RenderShadows(renderCommandEncoder: renderEncoder)
            }
        }
    }
    
    override func draw(in view: MTKView) {
        SceneManager.Update(deltaTime: 1.0 / Float(view.preferredFramesPerSecond))
        
        var commandBuffer = beginFrame()
        commandBuffer.label = "Shadow Commands"
        
        encodeShadowMapPass(into: commandBuffer)
        commandBuffer.commit()
        
        commandBuffer = beginDrawableCommands()
        commandBuffer.label = "GBuffer & Lighting Commands"
        
        if let drawableTexture = view.currentDrawable?.texture {
            _gBufferAndLightingRenderPassDescriptor.colorAttachments[Int(TFSRenderTargetLighting.rawValue)].texture = drawableTexture
            _gBufferAndLightingRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
            _gBufferAndLightingRenderPassDescriptor.stencilAttachment.texture = view.depthStencilTexture
            
            encodePass(into: commandBuffer, using: _gBufferAndLightingRenderPassDescriptor, label: "GBuffer & Lighting Pass") {
                renderEncoder in
                
                encodeGBufferStage(using: renderEncoder)
                encodeDirectionalLightingStage(using: renderEncoder)
//                encodeLightMaskStage(using: renderEncoder)
//                encodePointLightStage(using: renderEncoder)
                encodeSkyboxStage(using: renderEncoder)
            }
        }
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    override func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("[drawableSizeWillChange] new size: \(size)")
        gBufferTextures.makeTextures(device: Engine.Device, size: size, storageMode: .memoryless)
        // Re-set GBuffer textures in the view render pass descriptor after they have been reallocated by a resize
        setGBufferTextures(_gBufferAndLightingRenderPassDescriptor)
    }
}