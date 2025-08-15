//
//  SceneManager.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit
import os

enum SceneType {
    case Sandbox
    case Flightbox
    case FreeCamFlightbox
    case BallPhysics
    case FlightboxWithTerrain
}

// Good Idea ... ?
//enum UniformsDataType {
//    case Model
//    case TransparentModel
//    case Sky
//}

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

struct UniformsData: Sendable {
    let uniforms: [ModelConstants]
    let opaqueSubmeshes: [Submesh]
    let transparentSubmeshes: [Submesh]
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

struct TransparentUniformsData: Sendable {
    let uniforms: [ModelConstants]
}

final class SceneManager {
    nonisolated(unsafe) public static var CurrentScene: GameScene?
    nonisolated(unsafe) private static var _sceneType: SceneType?
    nonisolated(unsafe) private static var _rendererType: RendererType?
    
    nonisolated(unsafe) public static var modelDatas: [Model: ModelData] = [:]  // TODO -> wrap this in a thread safe container (?)
    nonisolated(unsafe) public static var transparentObjectDatas: [Model: TransparentObjectData] = [:]
    nonisolated(unsafe) public static var particleObjects: [ParticleEmitterObject] = []
    nonisolated(unsafe) public static var tessellatables: [Tessellatable] = []
    nonisolated(unsafe) public static var skyData = ModelData()
    nonisolated(unsafe) public static var lines: [Line] = []
    nonisolated(unsafe) public static var icosahedrons: [Icosahedron] = []
    
    nonisolated(unsafe) private static var _paused: Bool = false
    public static var Paused: Bool {
        get {
            return _paused
        }
        
        set {
            _paused = newValue
            Engine.PauseView(newValue)
        }
    }
    
    private static let uniformsLock = OSAllocatedUnfairLock()
    
    public static func SetScene(_ sceneType: SceneType, rendererType: RendererType) {
        _sceneType = sceneType
        _rendererType = rendererType
        
        // TODO: Is there a more elegant way to do this ???
        switch sceneType {
            case .Sandbox:
                CurrentScene = SandboxScene(name: "Sandbox", rendererType: rendererType)
            case .Flightbox:
                CurrentScene = FlightboxScene(name: "Flightbox", rendererType: rendererType)
            case .FreeCamFlightbox:
                CurrentScene = FreeCamFlightboxScene(name: "FreeCamFlightbox", rendererType: rendererType)
            case .BallPhysics:
                CurrentScene = BallPhysicsScene(name: "BallPhysicsSandbox", rendererType: rendererType)
            case .FlightboxWithTerrain:
                CurrentScene = FlightboxWithTerrain(name: "Flightbox with Terrain", rendererType: rendererType)
        }
    }
    
    public static func ResetScene() {
        if let _sceneType, let _rendererType {
            SetScene(_sceneType, rendererType: _rendererType)
        }
    }
    
    public static func TeardownScene() {
        CurrentScene?.teardownScene()
        
        // Clear all collections to prevent memory leaks
        modelDatas.removeAll()
        transparentObjectDatas.removeAll()
        particleObjects.removeAll()
        tessellatables.removeAll()
        skyData = ModelData()
        lines.removeAll()
        icosahedrons.removeAll()
        
        _sceneType = nil
        _rendererType = nil
    }
    
    public static func Update(deltaTime: Double) {
        if !Paused {
            GameTime.UpdateTime(deltaTime)
            
            // Lock when updating uniforms (model constants)
            uniformsLock.lock()
            
            CurrentScene?.updateCameras(deltaTime: deltaTime)
            CurrentScene?.update()
            
            uniformsLock.unlock()
        }
    }
    
    // ----------------------------------------------------------------------------- //
    
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
            case let tessellatable as Tessellatable:
                tessellatables.append(tessellatable)
            case let subMeshGameObject as SubMeshGameObject:
                RegisterSubMeshObject(subMeshGameObject)
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
                modelDatas[gameObject.model] = CreateModelData(gameObject: gameObject)
            }
        }
    }
    
    static private func CreateModelData(gameObject: GameObject) -> ModelData {
        var modelData = ModelData()
        modelData.addGameObject(gameObject)
        
        for mesh in gameObject.model.meshes {
            for submesh in mesh.submeshes {
                if gameObject.shouldRenderSubmesh(submesh) {
                    if isTransparent(submesh: submesh) {
                        modelData.appendTransparent(submesh: submesh)
                    } else {
                        modelData.appendOpaque(submesh: submesh)
                    }
                }
            }
        }
        
        return modelData
    }
    
    // TODO: Eventually we can remove this method (?):
    static private func RegisterSubMeshObject(_ subMeshObject: SubMeshGameObject) {
        print("[SceneMgr RegisterSubMeshObject] registering \(subMeshObject.getName()) with model \(subMeshObject.model.name)")
        
        if let parentObj = subMeshObject.parentMeshGameObject,
           let modelData = modelDatas[parentObj.model],
           let gameObj = modelData.gameObjects.first(where: { $0.getID() == parentObj.id }) {
            if !gameObj.shouldRenderSubmesh(subMeshObject.submeshName) {
                var idx = -1
                for (meshIdx, oMesh) in modelData.opaqueSubmeshes.enumerated() {
                    if oMesh.name == subMeshObject.submeshName {
                        idx = meshIdx
                        break
                    }
                }
                
                if idx >= 0 {
                    print("[RegisterSubMeshObject] removing submesh \(subMeshObject.submeshName) from model \(parentObj.model.name) [idx: \(idx)]")
                    modelDatas[parentObj.model]!.opaqueSubmeshes.remove(at: idx)
                }
            }
        }
        
        RegisterObject(subMeshObject)
    }
    
    static private func registerTransparentObject(_ gameObject: GameObject) {
        if let _ = transparentObjectDatas[gameObject.model] {
            transparentObjectDatas[gameObject.model]!.addGameObject(gameObject)
        } else {
            transparentObjectDatas[gameObject.model] = CreateTransparentObjectData(gameObject: gameObject)
        }
    }
    
    static private func registerTransparentSubMeshObject(_ subMeshObject: SubMeshGameObject) {
        
    }
    
    static private func CreateTransparentObjectData(gameObject: GameObject) -> TransparentObjectData {
        var transparentObjectData = TransparentObjectData()
        transparentObjectData.addGameObject(gameObject)
        transparentObjectData.addModel(gameObject.model)
        return transparentObjectData
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
    
    // TODO: Find best way to copy model constants into separate buffer...
    
    public static func GetUniformsData() -> [Model: UniformsData] {
        // Lock when reading uniforms (model constants)
        uniformsLock.lock()
        var uniformsData: [Model: UniformsData] = [:]
        for key in modelDatas.keys {
            let modelData = modelDatas[key]!
            uniformsData[key] = UniformsData(uniforms: modelData.gameObjects.compactMap(\.modelConstants),
                                             opaqueSubmeshes: modelData.opaqueSubmeshes,
                                             transparentSubmeshes: modelData.transparentSubmeshes)
        }
        uniformsLock.unlock()
        
        return uniformsData
    }
    
    public static func GetTransparentUniformsData() -> [Model: TransparentUniformsData] {
        uniformsLock.lock()
        var transparentUniformsData: [Model: TransparentUniformsData] = [:]
        for key in transparentObjectDatas.keys {
            let modelData = transparentObjectDatas[key]!
            transparentUniformsData[key] = TransparentUniformsData(uniforms: modelData.gameObjects.compactMap(\.modelConstants))
        }
        uniformsLock.unlock()
        
        return transparentUniformsData
    }
    
    public static func GetSkyUniformsData() -> UniformsData {
        // Lock here?
        return UniformsData(uniforms: skyData.gameObjects.compactMap(\.modelConstants),
                            opaqueSubmeshes: skyData.opaqueSubmeshes,
                            transparentSubmeshes: skyData.transparentSubmeshes)
    }
    
    public static var SubmeshCount: Int {
        return modelDatas.reduce(0) { $0 + $1.value.opaqueSubmeshes.count + $1.value.transparentSubmeshes.count }
    }
    
    
    // ----------------------------------------------------------------------------- //
    
    public static func SetSceneConstants(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setSceneConstants(with: renderEncoder)
    }
    
    public static func SetDirectionalLightConstants(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setDirectionalLightConstants(with: renderEncoder)
    }
    
    public static func SetPointLightConstants(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setPointLightConstants(with: renderEncoder)
    }
    
    public static func SetDirectionalLightData(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setDirectionalLightData(with: renderEncoder)
    }
    
    public static func SetPointLightData(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setPointLightData(with: renderEncoder)
    }
    
    public static func SetAspectRatio(_ aspectRatio: Float) {
        CurrentScene?.setAspectRatio(aspectRatio)
    }
}
