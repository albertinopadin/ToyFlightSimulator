//
//  DrawManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/14/24.
//

import MetalKit

struct ModelData {
    var gameObjects: [GameObject] = []
    var opaqueSubmeshes: [Submesh] = []
    var transparentSubmeshes: [Submesh] = []
    
    mutating func addGameObject(_ gameObject: GameObject) {
        self.gameObjects.append(gameObject)
    }
    
    mutating func appendOpaque(submesh: Submesh) {
        self.opaqueSubmeshes.append(submesh)
    }
    
    mutating func appendTransparent(submesh: Submesh) {
        self.transparentSubmeshes.append(submesh)
    }
}

struct TransparentObjectData {
    var gameObjects: [GameObject] = []
    var models: [Model] = []
    
    mutating func addGameObject(_ gameObject: GameObject) {
        self.gameObjects.append(gameObject)
    }
    
    mutating func addModel(_ model: Model) {
        self.models.append(model)
    }
}

final class DrawManager {
    static var modelDatas: [Model: ModelData] = [:]
    static var transparentObjectDatas: [Model: TransparentObjectData] = [:]
    static var particleObjects: [ParticleEmitterObject] = []
    static var skyData = ModelData()
    static var lines: [Line] = []
    static var icosahedrons: [Icosahedron] = []
    
    static var SubmeshCount: Int {
        return modelDatas.reduce(0) { $0 + $1.value.opaqueSubmeshes.count + $1.value.transparentSubmeshes.count }
    }
    
    static func Register(_ gameObject: GameObject) {
        switch gameObject {
            case is SkyBox, is SkySphere:
                RegisterSky(gameObject)
            case is LightObject:
                print("[DrawMgr RegisterObject] got LightObject")
            case let icosahedron as Icosahedron:
                icosahedrons.append(icosahedron)
            case let line as Line:
                lines.append(line)
            case let particleObject as ParticleEmitterObject:
                particleObjects.append(particleObject)
            default:
                RegisterObject(gameObject)
        }
    }
    
    static private func RegisterObject(_ gameObject: GameObject) {
        if gameObject.isTransparent {
            registerTransparentObject(gameObject)
        } else {
            if let _ = modelDatas[gameObject.model] {
                modelDatas[gameObject.model]!.addGameObject(gameObject)
            } else {
                var modelData = ModelData()
                modelData.addGameObject(gameObject)
                
                for mesh in gameObject.model.meshes {
                    for submesh in mesh.submeshes {
                        if isTransparent(submesh: submesh) {
                            modelData.appendTransparent(submesh: submesh)
                        } else {
                            modelData.appendOpaque(submesh: submesh)
                        }
                    }
                }
                
                modelDatas[gameObject.model] = modelData
            }
        }
    }
    
    static private func registerTransparentObject(_ gameObject: GameObject) {
        if let _ = transparentObjectDatas[gameObject.model] {
            transparentObjectDatas[gameObject.model]!.addGameObject(gameObject)
        } else {
            var transparentObjectData = TransparentObjectData()
            transparentObjectData.addGameObject(gameObject)
            transparentObjectData.addModel(gameObject.model)
            transparentObjectDatas[gameObject.model] = transparentObjectData
        }
    }
    
    static private func isTransparent(submesh: Submesh) -> Bool {
        if let isTransparent = submesh.material?.isTransparent, isTransparent {
            return true
        }
        
        return false
    }
    
    static private func RegisterSky(_ gameObject: GameObject) {
        // TODO: Hack to set sky object - think of something better
        if skyData.gameObjects.isEmpty {
            skyData.gameObjects.append(gameObject)
        }
        
        for mesh in gameObject.model.meshes {
            for submesh in mesh.submeshes {
                if let isTransparent = submesh.material?.isTransparent, isTransparent {
                    skyData.appendTransparent(submesh: submesh)
                } else {
                    skyData.appendOpaque(submesh: submesh)
                }
            }
        }
    }
    
    static func EncodeRender(using renderEncoder: MTLRenderCommandEncoder, label: String, _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    static func Draw(with renderEncoder: MTLRenderCommandEncoder,
                     withTransparency: Bool = false,
                     applyMaterials: Bool = true) {
        for (model, data) in modelDatas {
            if withTransparency {
                if !data.transparentSubmeshes.isEmpty {
                    Draw(renderEncoder,
                         model: model,
                         gameObjects: data.gameObjects,
                         submeshes: data.transparentSubmeshes,
                         applyMaterials: applyMaterials)
                }
            } else {
                if !data.opaqueSubmeshes.isEmpty {
                    Draw(renderEncoder,
                         model: model,
                         gameObjects: data.gameObjects,
                         submeshes: data.opaqueSubmeshes,
                         applyMaterials: applyMaterials)
                }
            }
        }
        
        if withTransparency {
            for (model, data) in transparentObjectDatas {
                Draw(renderEncoder,
                     model: model,
                     gameObjects: data.gameObjects,
                     submeshes: model.meshes.flatMap { $0.submeshes },
                     applyMaterials: applyMaterials)
            }
        } else {
            DrawLines(with: renderEncoder)
        }
    }
    
    // I really don't like this long term...
    static func DrawShadows(with renderEncoder: MTLRenderCommandEncoder) {
        for (model, data) in modelDatas {
            Draw(renderEncoder,
                 model: model,
                 gameObjects: data.gameObjects,
                 submeshes: data.opaqueSubmeshes,
                 applyMaterials: false)
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
        if !pointLights.isEmpty {
            Draw(renderEncoder,
                 model: Assets.Models[.Icosahedron],
                 gameObjects: pointLights,
                 submeshes: Assets.Models[.Icosahedron].meshes.flatMap { $0.submeshes },
                 applyMaterials: true)
        }
    }
    
    static func DrawIcosahedrons(with renderEncoder: MTLRenderCommandEncoder) {
        if !icosahedrons.isEmpty {
            Draw(renderEncoder,
                 model: Assets.Models[.Icosahedron],
                 gameObjects: icosahedrons,
                 submeshes: icosahedrons.first!.model.meshes.flatMap { $0.submeshes },
                 applyMaterials: true)
        }
    }
    
    static func DrawSky(with renderEncoder: MTLRenderCommandEncoder) {
        if let skyObj = skyData.gameObjects.first as? SkyEntity {
            let pso: RenderPipelineStateType = ((skyObj as? SkyBox) != nil) ? .Skybox : .SkySphere
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[pso])
            renderEncoder.setFragmentTexture(Assets.Textures[skyObj.textureType], index: TFSTextureIndexSkyBox.index)
            
            Draw(renderEncoder,
                 model: skyObj.model,
                 gameObjects: skyData.gameObjects,
                 submeshes: skyData.opaqueSubmeshes,
                 applyMaterials: false)
        }
    }
    
    static func DrawParticles(with renderEncoder: MTLRenderCommandEncoder) {
        for particleObject in particleObjects {
            if particleObject.shouldEmit && particleObject.emitter.currentParticles > 0 {
                EncodeRender(using: renderEncoder, label: "Rendering \(particleObject.getName())") {
                    renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Particle])
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
    
    static func DrawLines(with renderEncoder: MTLRenderCommandEncoder) {
        if !lines.isEmpty {
            EncodeRender(using: renderEncoder, label: "Rendering Lines") {
                renderEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
                
                for line in lines {
                    renderEncoder.setVertexBytes(&line.modelConstants,
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
                             gameObjects: [GameObject],
                             submeshes: [Submesh],
                             applyMaterials: Bool) {
        EncodeRender(using: renderEncoder, label: "Rendering \(model.name)") {
            var constants = gameObjects.map { $0.modelConstants }
            renderEncoder.setVertexBytes(&constants,
                                         length: ModelConstants.stride(gameObjects.count),
                                         index: TFSBufferModelConstants.index)
            
            for submesh in submeshes {
                if let vertexBuffer = submesh.parentMesh!.vertexBuffer {
                    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                    
                    if applyMaterials {
                        submesh.material!.applyTextures(with: renderEncoder)
                        
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
                                                        instanceCount: submesh.parentMesh!.instanceCount * gameObjects.count)
                }
            }
        }
    }
}
