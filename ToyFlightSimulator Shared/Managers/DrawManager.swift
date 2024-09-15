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
    static var lines: [Line] = []
    static var icosahedrons: [Icosahedron] = []
    
    static var SubmeshCount: Int {
        return gameObjectToSubmeshes.reduce(0) { $0 + $1.value.opaqueSubmeshes.count + $1.value.transparentSubmeshes.count }
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
    
    static private func RegisterSky(_ gameObject: GameObject) {
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
        
        DrawLines(with: renderEncoder)
//        DrawSky(with: renderEncoder, withTransparency: withTransparency, applyMaterials: applyMaterials)
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
    
    static func DrawQuad(with renderEncoder: MTLRenderCommandEncoder) {
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
    
    static func DrawIcosahedrons(with renderEncoder: MTLRenderCommandEncoder) {
        for icosahedron in icosahedrons {
//            Draw(renderEncoder,
//                 gameObject: icosahedron,
//                 submeshes: icosahedron.model.meshes.reduce([]) { $1.submeshes },
//                 applyMaterials: true)
            
            Draw(renderEncoder,
                 gameObject: icosahedron,
                 submeshes: icosahedron.model.meshes.flatMap { $0.submeshes },
                 applyMaterials: true)
        }
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
    
    static func DrawLines(with renderEncoder: MTLRenderCommandEncoder) {
        for line in lines {
            EncodeRender(using: renderEncoder, label: "Rendering \(line.getName())") {
                renderEncoder.setVertexBytes(&line.modelConstants,
                                             length: ModelConstants.stride,
                                             index: TFSBufferModelConstants.index)
                renderEncoder.setVertexBuffer(line.vertexBuffer, offset: 0, index: 0)
                renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: line.vertices.count)
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
