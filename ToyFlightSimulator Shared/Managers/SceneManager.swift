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
    case PhysicsStressTest
}

// Good Idea ... ?
//enum UniformsDataType {
//    case Model
//    case TransparentModel
//    case Sky
//}

struct MeshData: @unchecked Sendable {
    let mesh: Mesh
    
    var opaqueSubmeshes: [Submesh] = []
    var transparentSubmeshes: [Submesh] = []
    
    mutating func appendOpaque(submesh: Submesh) {
        self.opaqueSubmeshes.append(submesh)
    }
    
    mutating func appendTransparent(submesh: Submesh) {
        self.transparentSubmeshes.append(submesh)
    }
}

struct ModelData {
    var gameObjects = ContiguousArray<GameObject>()
    var meshDatas: [MeshData] = []
    
    mutating func addGameObject(_ gameObject: GameObject) {
        self.gameObjects.append(gameObject)
    }
    
    mutating func addMeshData(_ meshData: MeshData) {
        self.meshDatas.append(meshData)
    }
}

struct UniformsData: Sendable {
    let uniforms: [ModelConstants]
    let meshDatas: [MeshData]
}

/// A region in the per-frame ring buffer that holds pre-written ModelConstants.
/// Written by the update thread, read by the render thread — no lock needed.
struct RingBufferRegion {
    let offset: Int       // Byte offset into the ring buffer
    let count: Int        // Number of ModelConstants written
    let meshDatas: [MeshData]
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
    
    // TODO -> wrap this in a thread safe container (?):
    nonisolated(unsafe) public static var modelDatas: [Model: ModelData] = [:]
    nonisolated(unsafe) public static var transparentObjectDatas: [Model: TransparentObjectData] = [:]
    nonisolated(unsafe) public static var particleObjects: [ParticleEmitterObject] = []
    nonisolated(unsafe) public static var tessellatables: [Tessellatable] = []
    nonisolated(unsafe) public static var skyData = ModelData()
    nonisolated(unsafe) public static var lines: [Line] = []
    nonisolated(unsafe) public static var icosahedrons: [Icosahedron] = []
    
    // ===================== Per-Frame Ring Buffer Snapshots ===================== //
    // Triple-buffered snapshots: update thread writes, render thread reads.
    // Indexed by frameIndex % maxFramesInFlight.
    nonisolated(unsafe) private static var opaqueSnapshots: [[Model: RingBufferRegion]] = [[:], [:], [:]]
    nonisolated(unsafe) private static var transparentSnapshots: [[Model: RingBufferRegion]] = [[:], [:], [:]]
    nonisolated(unsafe) private static var skySnapshots: [RingBufferRegion?] = [nil, nil, nil]

    /// Frame index for the next update. Set by the render thread before signaling update.
    nonisolated(unsafe) public static var nextFrameIndex: Int = 0
    // ========================================================================= //
    
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
    
    // uniformsLock removed: ring buffer snapshots eliminate shared mutable state between threads.
    
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
            case .PhysicsStressTest:
                CurrentScene = PhysicsStressTestScene(name: "PhysicsStressTest", rendererType: rendererType)
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
        
        // Clear ring buffer snapshots:
        opaqueSnapshots = [[:], [:], [:]]
        transparentSnapshots = [[:], [:], [:]]
        skySnapshots = [nil, nil, nil]
        
        _sceneType = nil
        _rendererType = nil
    }
    
    public static func Update(deltaTime: Double) {
        if !Paused {
            GameTime.UpdateTime(deltaTime)

            CurrentScene?.updateCameras(deltaTime: deltaTime)
            CurrentScene?.update()

            // After all GameObjects have updated their modelConstants,
            // write them directly into the ring buffer for the next frame.
            // No lock needed: update thread writes here, render thread reads
            // from a different frame's snapshot (guarded by inFlightSemaphore).
            writeFrameSnapshot(frameIndex: nextFrameIndex)
        }
    }

    /// Write all ModelConstants directly into the ring buffer for the given frame slot.
    /// Called by the update thread after scene update completes.
    private static func writeFrameSnapshot(frameIndex: Int) {
        DrawManager.BeginFrameForUpdate(frameIndex: frameIndex)

        // Opaque objects:
        var opaque: [Model: RingBufferRegion] = [:]
        opaque.reserveCapacity(modelDatas.count)
        for (model, modelData) in modelDatas {
            guard !modelData.gameObjects.isEmpty else { continue }
            if let offset = DrawManager.writeModelConstants(
                gameObjects: modelData.gameObjects,
                frameIndex: frameIndex
            ) {
                opaque[model] = RingBufferRegion(
                    offset: offset,
                    count: modelData.gameObjects.count,
                    meshDatas: modelData.meshDatas
                )
            }
        }
        opaqueSnapshots[frameIndex] = opaque

        // Transparent objects:
        var transparent: [Model: RingBufferRegion] = [:]
        transparent.reserveCapacity(transparentObjectDatas.count)
        for (model, objData) in transparentObjectDatas {
            guard !objData.gameObjects.isEmpty else { continue }
            // Transparent objects use ContiguousArray via a temporary:
            let gameObjects = ContiguousArray(objData.gameObjects)
            if let offset = DrawManager.writeModelConstants(
                gameObjects: gameObjects,
                frameIndex: frameIndex
            ) {
                transparent[model] = RingBufferRegion(
                    offset: offset,
                    count: gameObjects.count,
                    meshDatas: model.meshes.map { mesh in
                        MeshData(mesh: mesh,
                                 opaqueSubmeshes: [],
                                 transparentSubmeshes: mesh.submeshes)
                    }
                )
            }
        }
        transparentSnapshots[frameIndex] = transparent

        // Sky:
        if !skyData.gameObjects.isEmpty {
            let gameObjects = skyData.gameObjects
            if let offset = DrawManager.writeModelConstants(
                gameObjects: gameObjects,
                frameIndex: frameIndex
            ) {
                skySnapshots[frameIndex] = RingBufferRegion(
                    offset: offset,
                    count: gameObjects.count,
                    meshDatas: skyData.meshDatas
                )
            }
        } else {
            skySnapshots[frameIndex] = nil
        }

        // Record end offset so render thread starts from here for ad-hoc draws:
        DrawManager.finishUpdateWrites(frameIndex: frameIndex)
    }

    /// Get the opaque snapshot for the current frame (called by render thread).
    public static func getOpaqueSnapshot(frameIndex: Int) -> [Model: RingBufferRegion] {
        return opaqueSnapshots[frameIndex]
    }

    /// Get the transparent snapshot for the current frame (called by render thread).
    public static func getTransparentSnapshot(frameIndex: Int) -> [Model: RingBufferRegion] {
        return transparentSnapshots[frameIndex]
    }

    /// Get the sky snapshot for the current frame (called by render thread).
    public static func getSkySnapshot(frameIndex: Int) -> RingBufferRegion? {
        return skySnapshots[frameIndex]
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
            var meshData = MeshData(mesh: mesh)
            
            for submesh in mesh.submeshes {
                if gameObject.shouldRenderSubmesh(submesh) {
                    if isTransparent(submesh: submesh) {
                        meshData.appendTransparent(submesh: submesh)
                    } else {
                        meshData.appendOpaque(submesh: submesh)
                    }
                }
            }
            modelData.addMeshData(meshData)
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
                var meshDataIdx = -1
                var meshToRemoveIdx = -1
                meshDataLoop: for (mdIdx, meshData) in modelData.meshDatas.enumerated() {
                    for (meshIdx, oMesh) in meshData.opaqueSubmeshes.enumerated() {
                        if oMesh.name == subMeshObject.submeshName {
                            meshDataIdx = mdIdx
                            meshToRemoveIdx = meshIdx
                            break meshDataLoop
                        }
                    }
                }
                
                if meshToRemoveIdx >= 0 {
                    print("[RegisterSubMeshObject] removing submesh \(subMeshObject.submeshName) from model \(parentObj.model.name) [idx: \(meshToRemoveIdx)]")
                    modelDatas[parentObj.model]!.meshDatas[meshDataIdx].opaqueSubmeshes.remove(at: meshToRemoveIdx)
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
            var skyMeshData = MeshData(mesh: mesh)
            for submesh in mesh.submeshes {
                if let isTransparent = submesh.material?.isTransparent, isTransparent {
                    skyMeshData.appendTransparent(submesh: submesh)
                } else {
                    skyMeshData.appendOpaque(submesh: submesh)
                }
            }
            skyData.addMeshData(skyMeshData)
        }
    }
    
    public static var SubmeshCount: Int {
        return modelDatas.map {
            $0.value.meshDatas.reduce(0) { $0 + $1.opaqueSubmeshes.count + $1.transparentSubmeshes.count }
        }.reduce(0, +)
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
