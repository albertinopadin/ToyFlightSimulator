//
//  DrawManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/14/24.
//

import MetalKit

struct GameObjectSubmeshes {
    var gameObject: GameObject?
    var opaqueSubmeshes: [Submesh] = []
    var transparentSubmeshes: [Submesh] = []
    
    mutating func setGameObject(_ gameObject: GameObject) {
        self.gameObject = gameObject
    }
    
    mutating func appendOpaque(submesh: Submesh) {
        self.opaqueSubmeshes.append(submesh)
    }
    
    mutating func appendTransparent(submesh: Submesh) {
        self.transparentSubmeshes.append(submesh)
    }
}

final class DrawManager {
    static var gameObjectToSubmeshes: [GameObject: GameObjectSubmeshes] = [:]
    static var particleObjects: [ParticleEmitterObject] = []
    static var skySubmeshes = GameObjectSubmeshes()
    
    static var SubmeshCount: Int {
        return gameObjectToSubmeshes.reduce(0) { $0 + $1.value.opaqueSubmeshes.count + $1.value.transparentSubmeshes.count }
    }
    
    static func RegisterObject(_ gameObject: GameObject) {
        if gameObject is SkyBox || gameObject is SkySphere {
            for mesh in gameObject.model.meshes {
                for submesh in mesh.submeshes {
                    if skySubmeshes.gameObject == nil {
                        skySubmeshes.gameObject = gameObject
                    }
                    
                    if let isTransparent = submesh.material?.isTransparent, isTransparent {
                        skySubmeshes.appendTransparent(submesh: submesh)
                    } else {
                        skySubmeshes.appendOpaque(submesh: submesh)
                    }
                }
            }
        } else {
            if let particleObject = gameObject as? ParticleEmitterObject {
                particleObjects.append(particleObject)
            } else if !(gameObject is LightObject) {
                for mesh in gameObject.model.meshes {
                    for submesh in mesh.submeshes {
                        if let _ = gameObjectToSubmeshes[gameObject] {
                            if let isTransparent = submesh.material?.isTransparent, isTransparent {
                                gameObjectToSubmeshes[gameObject]?.appendTransparent(submesh: submesh)
                            } else {
                                gameObjectToSubmeshes[gameObject]?.appendOpaque(submesh: submesh)
                            }
                        } else {
                            var goSubmeshes = GameObjectSubmeshes()
                            if let isTransparent = submesh.material?.isTransparent, isTransparent {
                                goSubmeshes.appendTransparent(submesh: submesh)
                            } else {
                                goSubmeshes.appendOpaque(submesh: submesh)
                            }
                            gameObjectToSubmeshes[gameObject] = goSubmeshes
                        }
                    }
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
        for (gameObject, submeshes) in gameObjectToSubmeshes {
            // Set constants / uniforms
            
            if withTransparency {
                Draw(renderEncoder, 
                     gameObject: gameObject,
                     submeshes: submeshes.transparentSubmeshes, 
                     applyMaterials: applyMaterials)
            } else {
                Draw(renderEncoder, 
                     gameObject: gameObject,
                     submeshes: submeshes.opaqueSubmeshes,
                     applyMaterials: applyMaterials)
            }
        }
        
//        DrawSky(with: renderEncoder, withTransparency: withTransparency, applyMaterials: applyMaterials)
    }
    
    static func DrawSky(with renderEncoder: MTLRenderCommandEncoder,
                        withTransparency: Bool,
                        applyMaterials: Bool) {
        if let skyObj = skySubmeshes.gameObject as? SkyEntity {
            renderEncoder.setFragmentTexture(Assets.Textures[skyObj.textureType], index: 10)
            
            if withTransparency {
                Draw(renderEncoder,
                     gameObject: skySubmeshes.gameObject!,
                     submeshes: skySubmeshes.transparentSubmeshes,
                     applyMaterials: applyMaterials)
            } else {
                Draw(renderEncoder,
                     gameObject: skySubmeshes.gameObject!,
                     submeshes: skySubmeshes.opaqueSubmeshes,
                     applyMaterials: applyMaterials)
            }
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
    
    static private func Draw(_ renderEncoder: MTLRenderCommandEncoder,
                             gameObject: GameObject,
                             submeshes: [Submesh],
                             applyMaterials: Bool) {
        EncodeRender(using: renderEncoder, label: "Rendering \(gameObject.getName())") {
            renderEncoder.setVertexBytes(&gameObject.modelConstants,
                                         length: ModelConstants.stride,
                                         index: TFSBufferModelConstants.index)
            
            for submesh in submeshes {
                if let vertexBuffer = submesh.parentMesh!.vertexBuffer {
                    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                    
                    if applyMaterials {
                        submesh.material?.applyTextures(with: renderEncoder,
                                                        baseColorTextureType: gameObject.baseColorTextureType,
                                                        normalMapTextureType: gameObject.normalMapTextureType,
                                                        specularTextureType: gameObject.specularTextureType)
                        submesh.applyMaterial(with: renderEncoder, customMaterial: gameObject.material)
                    }
                    
                    renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                        indexCount: submesh.indexCount,
                                                        indexType: submesh.indexType,
                                                        indexBuffer: submesh.indexBuffer,
                                                        indexBufferOffset: submesh.indexBufferOffset,
                                                        instanceCount: submesh.parentMesh!.instanceCount)
                }
            }
        }
    }
}
