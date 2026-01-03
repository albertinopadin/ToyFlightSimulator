//
//  DrawManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/14/24.
//

import MetalKit

final class DrawManager {
    // TODO: Consider removing this as it's the same code as in RenderPassEncoding protocol extension:
    static func EncodeRender(using renderEncoder: MTLRenderCommandEncoder, label: String, _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    static func DrawOpaque(with renderEncoder: MTLRenderCommandEncoder, applyMaterials: Bool = true) {
        // Test:
//        renderEncoder.setFrontFacing(.counterClockwise)
//        renderEncoder.setCullMode(.front)
        
        for (model, data) in SceneManager.GetUniformsData() {
            for meshData in data.meshDatas {
                if !meshData.opaqueSubmeshes.isEmpty {
                    /*
                     * ------------------------------- Animation -------------------------------
                     */
                    
                    if let paletteBuffer = meshData.mesh.skin?.jointMatrixPaletteBuffer {
                        renderEncoder.setVertexBuffer(paletteBuffer,
                                                      offset: 0,
                                                      index: TFSBufferIndexJointBuffer.index)
                        
                        // Hack for now to set the proper PSO:
                        if RenderState.CurrentPipelineStateType != .TiledMSAAGBufferAnimated {
                            RenderState.PreviousPipelineStateType = RenderState.CurrentPipelineStateType
                            RenderState.CurrentPipelineStateType = .TiledMSAAGBufferAnimated
                            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAGBufferAnimated])
                        }
                    } else {
                        // TODO: Will only work with Tiled renderer for now:
                        if RenderState.CurrentPipelineStateType == .TiledMSAAGBufferAnimated {
                            renderEncoder.setVertexBuffer(nil,
                                                          offset: 0,
                                                          index: TFSBufferIndexJointBuffer.index)
                            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[RenderState.PreviousPipelineStateType])
                            RenderState.CurrentPipelineStateType = RenderState.PreviousPipelineStateType
                        }
                    }
                    /*
                     * ---------------------------------------------------------------------------
                     */
                    
                    Draw(renderEncoder,
                         model: model,
                         uniforms: data.uniforms,
                         mesh: meshData.mesh,
                         submeshes: meshData.opaqueSubmeshes,
                         applyMaterials: applyMaterials)
                }
            }
        }
        
        DrawLines(with: renderEncoder)
    }
    
    static func DrawTransparent(with renderEncoder: MTLRenderCommandEncoder, applyMaterials: Bool = true) {
        for (model, data) in SceneManager.GetUniformsData() {
            for meshData in data.meshDatas {
                if !meshData.transparentSubmeshes.isEmpty {
                    /*
                     * ------------------------------- Animation -------------------------------
                     */
                    
                    if let paletteBuffer = meshData.mesh.skin?.jointMatrixPaletteBuffer {
                        renderEncoder.setVertexBuffer(paletteBuffer,
                                                      offset: 0,
                                                      index: TFSBufferIndexJointBuffer.index)
                        
                        // Hack for now to set the proper PSO:
                        if RenderState.CurrentPipelineStateType != .TiledMSAAGBufferAnimated {
                            RenderState.PreviousPipelineStateType = RenderState.CurrentPipelineStateType
                            RenderState.CurrentPipelineStateType = .TiledMSAAGBufferAnimated
                            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAGBufferAnimated])
                        }
                    } else {
                        // TODO: Will only work with Tiled renderer for now:
                        if RenderState.CurrentPipelineStateType == .TiledMSAAGBufferAnimated {
                            renderEncoder.setVertexBuffer(nil,
                                                          offset: 0,
                                                          index: TFSBufferIndexJointBuffer.index)
                            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[RenderState.PreviousPipelineStateType])
                            RenderState.CurrentPipelineStateType = RenderState.PreviousPipelineStateType
                        }
                    }
                    /*
                     * ---------------------------------------------------------------------------
                     */
                    
                    Draw(renderEncoder,
                         model: model,
                         uniforms: data.uniforms,
                         mesh: meshData.mesh,
                         submeshes: meshData.transparentSubmeshes,
                         applyMaterials: applyMaterials)
                }
            }
        }
        
        for (model, data) in SceneManager.GetTransparentUniformsData() {
            for mesh in model.meshes {
                Draw(renderEncoder,
                     model: model,
                     uniforms: data.uniforms,
                     mesh: mesh,
                     submeshes: model.meshes.flatMap { $0.submeshes },
                     applyMaterials: applyMaterials)
            }
        }
    }
    
    // I really don't like this long term...
    static func DrawShadows(with renderEncoder: MTLRenderCommandEncoder) {
        for (model, data) in SceneManager.GetUniformsData() {
            for meshData in data.meshDatas {
                /*
                 * ------------------------------- Animation -------------------------------
                 */
                
                if let paletteBuffer = meshData.mesh.skin?.jointMatrixPaletteBuffer {
                    renderEncoder.setVertexBuffer(paletteBuffer,
                                                  offset: 0,
                                                  index: TFSBufferIndexJointBuffer.index)
                    
                    // Hack for now to set the proper PSO:
                    if RenderState.CurrentPipelineStateType != .TiledMSAAShadowAnimated {
                        RenderState.PreviousPipelineStateType = RenderState.CurrentPipelineStateType
                        RenderState.CurrentPipelineStateType = .TiledMSAAShadowAnimated
                        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAShadowAnimated])
                    }
                } else {
                    // TODO: Will only work with Tiled renderer for now:
                    if RenderState.CurrentPipelineStateType == .TiledMSAAShadowAnimated {
                        renderEncoder.setVertexBuffer(nil,
                                                      offset: 0,
                                                      index: TFSBufferIndexJointBuffer.index)
                        
                        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[RenderState.PreviousPipelineStateType])
                        RenderState.CurrentPipelineStateType = RenderState.PreviousPipelineStateType
                    }
                }
                /*
                 * ---------------------------------------------------------------------------
                 */
                
                Draw(renderEncoder,
                     model: model,
                     uniforms: data.uniforms,
                     mesh: meshData.mesh,
                     submeshes: meshData.opaqueSubmeshes,
                     applyMaterials: false)
            }
        }
    }
    
    // TODO: Maybe it would be a good idea to refactor this class;
    //       Have the Renderer provide a dict of [RenderPipelineStateType : GameObject Type]
    //       Then parametrize Draw command on the pso to draw the appropriate objects
//    static func Draw(with renderEncoder: MTLRenderCommandEncoder,
//                     psoType: RenderPipelineStateType,
//                     withTransparency: Bool = false,
//                     applyMaterials: Bool = true) {
//        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[psoType])
//        
//
//    }
    
    static func DrawFullScreenQuad(with renderEncoder: MTLRenderCommandEncoder) {
        for mesh in Assets.Models[.Quad].meshes {
            if let vertexBuffer = mesh.vertexBuffer {
                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                
                for submesh in mesh.submeshes {
                    renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                        indexCount: submesh.indexCount,
                                                        indexType: submesh.indexType,
                                                        indexBuffer: submesh.indexBuffer,
                                                        indexBufferOffset: submesh.indexBufferOffset,
                                                        instanceCount: mesh.instanceCount)
                }
            }
        }
    }
    
    static func DrawPointLights(with renderEncoder: MTLRenderCommandEncoder) {
        let pointLights = LightManager.GetLightObjects(lightType: Point)
        let uniforms = pointLights.map { $0.modelConstants }
        let pointLightModel = Assets.Models[.Icosahedron]
        let submeshes = pointLightModel.meshes.flatMap { $0.submeshes }
        
        if !pointLights.isEmpty {
            Draw(renderEncoder,
                 model: pointLightModel,
                 uniforms: uniforms,
                 mesh: pointLightModel.meshes.first!,
                 submeshes: submeshes,
                 applyMaterials: true)
        }
    }
    
    static func DrawIcosahedrons(with renderEncoder: MTLRenderCommandEncoder) {
        if !SceneManager.icosahedrons.isEmpty {
            // !!!
            let uniforms = SceneManager.icosahedrons.map { $0.modelConstants }
            let icosahedronModel = Assets.Models[.Icosahedron]
            let icosahedronSubmeshes = SceneManager.icosahedrons.first!.model.meshes.flatMap { $0.submeshes }
            
            Draw(renderEncoder,
                 model: icosahedronModel,
                 uniforms: uniforms,
                 mesh: icosahedronModel.meshes.first!,
                 submeshes: icosahedronSubmeshes,
                 applyMaterials: true)
        }
    }
    
    static func DrawSky(with renderEncoder: MTLRenderCommandEncoder) {
        if let skyObj = SceneManager.skyData.gameObjects.first as? SkyEntity {
            let pso: RenderPipelineStateType = ((skyObj as? SkyBox) != nil) ? .Skybox : .SkySphere
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[pso])
            renderEncoder.setFragmentTexture(Assets.Textures[skyObj.textureType], index: TFSTextureIndexSkyBox.index)
            
            // !!!
            let uniformsData = SceneManager.GetSkyUniformsData()
            
            Draw(renderEncoder,
                 model: skyObj.model,
                 uniforms: uniformsData.uniforms,
                 mesh: skyObj.model.meshes.first!,
                 submeshes: SceneManager.skyData.meshDatas.first!.opaqueSubmeshes,
                 applyMaterials: false)
        }
    }
    
    static func DrawParticles(with renderEncoder: MTLRenderCommandEncoder) {
        for particleObject in SceneManager.particleObjects {
            if particleObject.shouldEmit && particleObject.emitter.currentParticles > 0 {
                EncodeRender(using: renderEncoder, label: "Rendering \(particleObject.getName())") {
                    renderEncoder.setVertexBuffer(particleObject.emitter.particleBuffer, offset: 0, index: 0)
                    renderEncoder.setVertexBytes(&particleObject.emitter.position, length: float3.stride, index: 2)
                    
                    renderEncoder.setVertexBytes(&particleObject.modelConstants,
                                                 length: ModelConstants.stride,
                                                 index: TFSBufferModelConstants.index)
                    
                    if let emitterTexture = particleObject.emitter.particleTexture {
                        renderEncoder.setFragmentTexture(emitterTexture, index: TFSTextureIndexParticle.index)
                    }
                    
                    renderEncoder.drawPrimitives(type: .point,
                                                 vertexStart: 0,
                                                 vertexCount: 1,
                                                 instanceCount: particleObject.emitter.currentParticles)
                }
            }
        }
    }
    
    static func DrawTessellatables(with renderEncoder: MTLRenderCommandEncoder) {
        for tessellatable in SceneManager.tessellatables {
            EncodeRender(using: renderEncoder, label: "Rendering \(tessellatable.getName())") {
                renderEncoder.setVertexBytes(&tessellatable.modelConstants,
                                             length: ModelConstants.stride,
                                             index: TFSBufferModelConstants.index)
                
                tessellatable.setRenderState(renderEncoder)
                
                renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                                          patchStart: 0,
                                          patchCount: tessellatable.patchCount,
                                          patchIndexBuffer: nil,
                                          patchIndexBufferOffset: 0,
                                          instanceCount: 1,
                                          baseInstance: 0)
            }
        }
    }
    
    static func DrawLines(with renderEncoder: MTLRenderCommandEncoder) {
        if !SceneManager.lines.isEmpty {
            EncodeRender(using: renderEncoder, label: "Rendering Lines") {
                renderEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
                
                for line in SceneManager.lines {
                    renderEncoder.setVertexBytes(&line.modelConstants,  // !!!!!!!
                                                 length: ModelConstants.stride,
                                                 index: TFSBufferModelConstants.index)
                    renderEncoder.setVertexBuffer(line.vertexBuffer, offset: 0, index: 0)
                    renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: line.vertices.count)
                }
            }
        }
    }
    
    static private func Draw(_ renderEncoder: MTLRenderCommandEncoder,
                             model: Model,
                             uniforms: [ModelConstants],
                             mesh: Mesh,
                             submeshes: [Submesh],
                             applyMaterials: Bool) {
        EncodeRender(using: renderEncoder, label: "Rendering \(model.name)") {
            if !uniforms.isEmpty {
                var uniforms = uniforms
                
                /*
                 * ------------------------------- Animation -------------------------------
                 */
                
                // TODO2: Below code will animate *ALL* models that use the same mesh which is
                //        probably *NOT* what we want. Hack for now to make this work...
                let currentLocalTransform = mesh.transform?.currentTransform ?? .identity
                for idx in 0..<uniforms.count {
                    uniforms[idx].modelMatrix *= currentLocalTransform
                }
                
                /*
                 * ---------------------------------------------------------------------------
                 */
                
                // ***** Super not optimized! *****
                let uniformsBuffer = Engine.Device.makeBuffer(bytes: &uniforms,
                                                              length: ModelConstants.stride(uniforms.count))
                
                renderEncoder.setVertexBuffer(uniformsBuffer, offset: 0, index: TFSBufferModelConstants.index)
                // *********************************
                
                for submesh in submeshes {
                    if let vertexBuffer = submesh.parentMesh!.vertexBuffer {
                        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                        
                        if applyMaterials {
                            applyMaterialTextures(submesh.material!, with: renderEncoder)
                            
                            var materialProps = submesh.material!.properties
                            renderEncoder.setFragmentBytes(&materialProps,
                                                           length: MaterialProperties.stride,
                                                           index: TFSBufferIndexMaterial.index)
                        }
                        
                        renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                            indexCount: submesh.indexCount,
                                                            indexType: submesh.indexType,
                                                            indexBuffer: submesh.indexBuffer,
                                                            indexBufferOffset: submesh.indexBufferOffset,
                                                            instanceCount: mesh.instanceCount * uniforms.count)
                    }
                }
            }
        }
    }
    
    private static func applyMaterialTextures(_ material: Material, with renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        
        if let baseColorTexture = material.baseColorTexture {
            renderEncoder.setFragmentTexture(baseColorTexture, index: TFSTextureIndexBaseColor.index)
        } else {
            renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexBaseColor.index)
        }
        
        if let normalMapTexture = material.normalMapTexture {
            renderEncoder.setFragmentTexture(normalMapTexture, index: TFSTextureIndexNormal.index)
        } else {
            renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexNormal.index)
        }
        
        if let specularTexture = material.specularTexture {
            renderEncoder.setFragmentTexture(specularTexture, index: TFSTextureIndexSpecular.index)
        } else {
            renderEncoder.setFragmentTexture(nil, index: TFSTextureIndexSpecular.index)
        }
    }
}
