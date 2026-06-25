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
    case FlightboxWithTerrain
    case FlightboxWithPhysics
    case BallPhysics
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
    
    mutating func removeGameObject(_ gameObject: GameObject) {
        self.gameObjects.removeAll(where: { $0.id == gameObject.id })
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
    // ContiguousArray to match ModelData — lets writeFrameSnapshot hand this
    // straight to DrawManager.writeModelConstants without a per-frame copy.
    var gameObjects = ContiguousArray<GameObject>()
    var models: [Model] = []
    var meshDatas: [MeshData] = []

    mutating func addGameObject(_ gameObject: GameObject) {
        self.gameObjects.append(gameObject)
    }

    mutating func removeGameObject(_ gameObject: GameObject) {
        self.gameObjects.removeAll(where: { $0.id == gameObject.id })
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
            case .FlightboxWithPhysics:
                CurrentScene = FlightboxWithPhysics(name: "Flightbox with Physics", rendererType: rendererType)
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

        // Drop render-thread caches keyed by Mesh identity (animated-uniforms
        // cache) so stale keys don't linger across scene loads:
        DrawManager.ClearFrameCaches()

        // Release parent MDLAssets retained only for single-submesh extraction
        // (e.g. the FA-18F). Already-extracted submeshes live in the library's
        // own cache, so this reclaims the source geometry/textures without forcing
        // re-extraction of parts still in use.
        SingleSubmeshMesh.clearCachedSourceModels()

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
            if let offset = DrawManager.writeModelConstants(
                gameObjects: objData.gameObjects,
                frameIndex: frameIndex
            ) {
                transparent[model] = RingBufferRegion(
                    offset: offset,
                    count: objData.gameObjects.count,
                    meshDatas: objData.meshDatas
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
        transparentObjectData.meshDatas = gameObject.model.meshes.map { mesh in
            MeshData(mesh: mesh,
                     opaqueSubmeshes: [],
                     transparentSubmeshes: mesh.submeshes)
        }
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
        var total = 0
        for (_, data) in modelDatas {
            for md in data.meshDatas {
                total += md.opaqueSubmeshes.count + md.transparentSubmeshes.count
            }
        }
        return total
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
    
    /*
     * TODO: placing this here for now:
     */
    public static func SetPlayerAircraft(_ aircraft: AircraftType) {
        CurrentScene?.setPlayerAircraft(aircraft)
    }
    
    public static func RemoveObject(_ gameObject: GameObject) {
        CurrentScene?.removeChild(gameObject)
        Unregister(gameObject)
    }

    /// Inverse of `Register` / `GameScene.registerChildObject`: removes `node`
    /// and its entire subtree from whatever batched collections each node was
    /// registered into.
    ///
    /// This must recurse: composite objects register their descendants *flat*
    /// in these collections, not under the parent (an F-18's control surfaces
    /// land in `modelDatas`, an F-22's afterburners in `particleObjects`).
    /// Removing only the top node would orphan them — `writeFrameSnapshot`
    /// would keep writing their now-frozen ModelConstants every frame and they
    /// would never deallocate.
    static func Unregister(_ node: Node) {
        for subtreeNode in subtreeNodes(of: node) {
            unregisterSingle(subtreeNode)
        }
    }

    /// `node` plus its full descendant subtree (pre-order). Pure scene-graph
    /// traversal — no Metal — so it's unit-testable directly. Mirrors how
    /// `registerChildObject` recurses grandchildren, so removal covers exactly
    /// the set registration added.
    static func subtreeNodes(of node: Node) -> [Node] {
        var nodes: [Node] = [node]
        for child in node.children {
            nodes.append(contentsOf: subtreeNodes(of: child))
        }
        return nodes
    }

    /// Removes a single node from the one collection it was registered into.
    /// The type dispatch mirrors `Register`, plus the `Camera` skip from
    /// `registerChildObject` (cameras are never registered, but they live in
    /// the aircraft subtree). Non-GameObjects and never-registered nodes are
    /// no-ops.
    private static func unregisterSingle(_ node: Node) {
        guard let gameObject = node as? GameObject else { return }

        switch gameObject {
            case is Camera, is SkyBox, is SkySphere, is LightObject:
                // Cameras aren't registered; sky is singleton-managed; lights
                // live in LightManager, not in these collections.
                break
            case let icosahedron as Icosahedron:
                icosahedrons.removeAll { $0.id == icosahedron.id }
            case let line as Line:
                lines.removeAll { $0.id == line.id }
            case let particleObject as ParticleEmitterObject:
                particleObjects.removeAll { $0.id == particleObject.id }
            // NOTE: `tessellatables` is intentionally not handled — nothing
            // removable registers as `Tessellatable` today (terrain is built
            // once and never swapped). Add a case here if that changes.
            default:
                removeRenderable(gameObject)
        }
    }

    /// Removes a renderable from `modelDatas` / `transparentObjectDatas`,
    /// mirroring `RegisterObject`. Drops the per-Model entry once its last
    /// object is gone so the dictionaries (and the per-frame snapshot loop)
    /// stay tight; the `isEmpty` guard leaves shared/instanced models intact
    /// until their final instance is removed.
    private static func removeRenderable(_ gameObject: GameObject) {
        let model = gameObject.model
        if gameObject.isTransparent {
            transparentObjectDatas[model]?.removeGameObject(gameObject)
            if transparentObjectDatas[model]?.gameObjects.isEmpty == true {
                transparentObjectDatas[model] = nil
            }
        } else {
            modelDatas[model]?.removeGameObject(gameObject)
            if modelDatas[model]?.gameObjects.isEmpty == true {
                modelDatas[model] = nil
            }
        }
    }
}
