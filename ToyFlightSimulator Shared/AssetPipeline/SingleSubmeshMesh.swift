//
//  SingleSMMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit
import os

struct SingleMeshVertexMetadata {
    let initialPositionInParentMesh: float3
    let uniqueVertices: Int
    let minX: Float
    let maxX: Float
    let minY: Float
    let maxY: Float
    let minZ: Float
    let maxZ: Float
}

class SingleSubmeshMesh: Mesh {
    private static let initialScale: Float = 1.0

    // Parsed parent models, cached so repeated submesh extractions from the same
    // file parse it (and load its textures) only once. Serialized by the lock.
    // Each extracted SingleSubmeshMesh copies its vertex buffer (see init), so
    // sharing one cached asset across sibling submeshes is safe.
    nonisolated(unsafe) private static var _loadedModels: [String: (asset: MDLAsset, root: MDLObject)] = [:]
    private static let _loadedModelsLock = OSAllocatedUnfairLock()

    internal var _submesh: Submesh!
    public let vertexMetadata: SingleMeshVertexMetadata

    init(asset: MDLAsset, mtkMesh: MTKMesh, mdlMesh: MDLMesh, submesh: Submesh, basisTransform: float4x4 = .identity) {
        // Centralize vertices:
        let vertBuf = mtkMesh.vertexBuffers[0].buffer
        vertexMetadata = SingleSubmeshMesh.getVertexMetadata(submesh: submesh,
                                                             vertexBuffer: vertBuf,
                                                             vertexCount: mtkMesh.vertexCount)
        
        // copyVertexBuffer: true — this MTKMesh's vertex buffer may be shared with
        // sibling submeshes from the same cached parent asset, so let super.init hand
        // us a private copy that translateSubmeshVertices(...) can recenter in place.
        super.init(mdlMesh: mdlMesh, mtkMesh: mtkMesh, basisTransform: basisTransform, copyVertexBuffer: true)

        name = submesh.name

        if mtkMesh.vertexBuffers.count > 1 {
            print("[SingleSubmeshMesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
        }
        self._vertexCount = mtkMesh.vertexCount
        _submesh = submesh
        _submesh.parentMesh = self
        
        self.submeshes = [_submesh]
        
        print("[SingleSubmeshMesh init] \(name) Initial average vertex position: \(vertexMetadata.initialPositionInParentMesh)")
        print("[SingleSubmeshMesh init] \(name) vertex count: \(vertexMetadata.uniqueVertices)")
        print("[SingleSubmeshMesh init] \(name) mesh vertex metadata: \(vertexMetadata)")
        
        translateSubmeshVertices(delta: -vertexMetadata.initialPositionInParentMesh)
    }
    
    public func translateSubmeshVerticesToMatchParentScale(_ parentScale: Float) {
        translateSubmeshVertices(delta: Self.initialScale * -vertexMetadata.initialPositionInParentMesh)
        translateSubmeshVertices(delta: parentScale * vertexMetadata.initialPositionInParentMesh)
    }
    
    private static func processVertices(submesh: Submesh,
                                        vertexBuffer: MTLBuffer,
                                        vertexCount: Int,
                                        handleBlock: (_ vertexBufferPointer: UnsafeMutablePointer<Vertex>,
                                                      _ indexBufferPointer: UnsafeMutablePointer<UInt32>) -> Void) {
        let vertexBufferPointer: UnsafeMutablePointer<Vertex> = vertexBuffer.contents().bindMemory(to: Vertex.self,
                                                                                                    capacity: vertexCount)
        var indexBufferPointer: UnsafeMutablePointer<UInt32> =
                                submesh.indexBuffer.contents().bindMemory(to: UInt32.self, capacity: submesh.indexCount)
        indexBufferPointer += submesh.indexBufferOffset
        handleBlock(vertexBufferPointer, indexBufferPointer)
    }
    
    private static func getVertexMetadata(submesh: Submesh, vertexBuffer: MTLBuffer, vertexCount: Int) -> SingleMeshVertexMetadata {
        var indexDict: [UInt32: Bool] = [:]
        var totalPosition = float3(0, 0, 0)
        var minCoords = float3(.infinity, .infinity, .infinity)
        var maxCoords = float3(-.infinity, -.infinity, -.infinity)
        
        processVertices(submesh: submesh, vertexBuffer: vertexBuffer, vertexCount: vertexCount) {
            vertexBufferPointer, indexBufferPointer in
            for i in 0..<submesh.indexCount {
                let index: UInt32 = indexBufferPointer[i]
                let seen = indexDict[index] ?? false
                if !seen {
                    let vertexPosition = vertexBufferPointer[Int(index)].position
                    totalPosition += vertexPosition
                    indexDict[index] = true
                    
                    if vertexPosition.x < minCoords.x {
                        minCoords.x = vertexPosition.x
                    }
                    
                    if vertexPosition.y < minCoords.y {
                        minCoords.y = vertexPosition.y
                    }
                    
                    if vertexPosition.z < minCoords.z {
                        minCoords.z = vertexPosition.z
                    }
                    
                    if vertexPosition.x > maxCoords.x {
                        maxCoords.x = vertexPosition.x
                    }
                    
                    if vertexPosition.y > maxCoords.y {
                        maxCoords.y = vertexPosition.y
                    }
                    
                    if vertexPosition.z > maxCoords.z {
                        maxCoords.z = vertexPosition.z
                    }
                }
            }
        }
        
        let uniqueVertices = indexDict.count
        print("[getAverageVertexPosition] number of unique vertices: \(uniqueVertices)")
        
        let averagePosition = float3(totalPosition.x / Float(uniqueVertices),
                                     totalPosition.y / Float(uniqueVertices),
                                     totalPosition.z / Float(uniqueVertices))
        
        return SingleMeshVertexMetadata(initialPositionInParentMesh: averagePosition,
                                        uniqueVertices: uniqueVertices,
                                        minX: minCoords.x,
                                        maxX: maxCoords.x,
                                        minY: minCoords.y,
                                        maxY: maxCoords.y,
                                        minZ: minCoords.z,
                                        maxZ: maxCoords.z)
    }
    
    public func translateSubmeshVertices(delta: float3) {
        var indexDict: [UInt32: Bool] = [:]
        SingleSubmeshMesh.processVertices(submesh: _submesh, vertexBuffer: vertexBuffer, vertexCount: _vertexCount) {
            vertexBufferPointer, indexBufferPointer in
            for i in 0..<_submesh.indexCount {
                let index: UInt32 = indexBufferPointer[i]
                let seen = indexDict[index] ?? false
                if !seen {
                    var vertex = vertexBufferPointer[Int(index)]
                    vertex.position += delta
                    vertexBufferPointer[Int(index)] = vertex
                    indexDict[index] = true
                }
            }
        }
    }
    
    public func setSubmeshOrigin(_ origin: float3) {
        translateSubmeshVertices(delta: origin)
    }
    
    private func createBuffer() {
        if _vertices.count > 0 {
            vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices,
                                                    length: Vertex.stride(_vertices.count),
                                                    options: [])
        }
    }
    
    private static func getMdlSubmeshNamed(_ submeshName: String, mdlMesh: MDLMesh) -> MDLSubmesh? {
        for i in 0..<mdlMesh.submeshes!.count {
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            if mdlSubmesh.name == submeshName {
                return mdlSubmesh
            }
        }
        
        return nil
    }

    private static func makeSingleSMMeshWithSubmeshNamed(_ submeshName: String,
                                                         asset: MDLAsset,
                                                         object: MDLObject,
                                                         basisTransform: float4x4) -> SingleSubmeshMesh? {
        if let mdlMesh = object as? MDLMesh {
            if let mdlSubmesh = getMdlSubmeshNamed(submeshName, mdlMesh: mdlMesh) {
                mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                        normalAttributeNamed: MDLVertexAttributeNormal,
                                        tangentAttributeNamed: MDLVertexAttributeTangent)
                
                mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                        tangentAttributeNamed: MDLVertexAttributeTangent,
                                        bitangentAttributeNamed: MDLVertexAttributeBitangent)
                
                let metalKitMesh = try! MTKMesh(mesh: mdlMesh, device: Engine.Device)
                let mtkSubmesh = metalKitMesh.submeshes.filter({ $0.name == submeshName })[0]
                print("[SingleSubmeshMesh makeSingleSMMeshWithSubmeshNamed] Creating Submesh...")
                let submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh)
                return SingleSubmeshMesh(asset: asset,
                                         mtkMesh: metalKitMesh,
                                         mdlMesh: mdlMesh,
                                         submesh: submesh,
                                         basisTransform: basisTransform)
            }
        }

        if object.conforms(to: MDLObjectContainerComponent.self) {
            for child in object.children.objects {
                if let mesh = makeSingleSMMeshWithSubmeshNamed(submeshName,
                                                               asset: asset,
                                                               object: child,
                                                               basisTransform: basisTransform) {
                    return mesh
                }
            }
        }
        
        return nil
    }

    public static func createSingleSMMeshFromModel(modelName: String,
                                                   submeshName: String,
                                                   basisTransform: float4x4,
                                                   ext: String = "obj") -> SingleSubmeshMesh {
        print("[createSingleSMMeshFromModel] model: \(modelName), submesh: \(submeshName)")

        let (asset, root) = loadParentModel(modelName: modelName, ext: ext)

        guard let cMesh = SingleSubmeshMesh.makeSingleSMMeshWithSubmeshNamed(submeshName,
                                                                             asset: asset,
                                                                             object: root,
                                                                             basisTransform: basisTransform) else {
            fatalError("[SingleSubmeshMesh makeMeshWithSubmeshNamed] Could not find any submesh named \(submeshName)")
        }

        return cMesh
    }

    /// Loads (and caches) the parent `MDLAsset` for `modelName`, parsing the file and
    /// loading its textures only once. Repeated submesh extractions reuse the cached
    /// asset instead of re-reading the model from disk.
    private static func loadParentModel(modelName: String, ext: String) -> (asset: MDLAsset, root: MDLObject) {
        withLock(_loadedModelsLock) {
            if let cached = _loadedModels[modelName] {
                return cached
            }

            print("[SingleSubmeshMesh loadParentModel] loading \(modelName).\(ext)")

            guard let assetURL = Bundle.main.url(forResource: modelName, withExtension: ext) else {
                fatalError("Asset \(modelName) does not exist.")
            }

            let descriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Simple])
            descriptor.attribute(TFSVertexAttributePosition.rawValue).name  = MDLVertexAttributePosition
            descriptor.attribute(TFSVertexAttributeColor.rawValue).name     = MDLVertexAttributeColor
            descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).name  = MDLVertexAttributeTextureCoordinate
            descriptor.attribute(TFSVertexAttributeNormal.rawValue).name    = MDLVertexAttributeNormal
            descriptor.attribute(TFSVertexAttributeTangent.rawValue).name   = MDLVertexAttributeTangent
            descriptor.attribute(TFSVertexAttributeBitangent.rawValue).name = MDLVertexAttributeBitangent

            // MTKMesh(mesh:device:) requires MTKMeshBufferAllocator-backed buffers; the
            // per-submesh copy in SingleSubmeshMesh.init keeps these shared parent
            // buffers from being mutated by any one submesh's in-place recentering.
            let asset = MDLAsset(url: assetURL,
                                 vertexDescriptor: descriptor,
                                 bufferAllocator: Mesh.mtkMeshBufferAllocator,
                                 preserveTopology: false,
                                 error: nil)
            asset.loadTextures()

            let root = asset.childObjects(of: MDLObject.self)[0]
            print("[SingleSubmeshMesh loadParentModel] \(modelName) root child name: \(root.name)")

            let loaded = (asset: asset, root: root)
            _loadedModels[modelName] = loaded
            return loaded
        }
    }

    /// Releases cached parent assets retained by `loadParentModel`. Call once all
    /// required submeshes have been extracted to reclaim the parent geometry and
    /// textures (only the per-submesh meshes are needed afterward).
    public static func clearCachedSourceModels() {
        withLock(_loadedModelsLock) {
            _loadedModels.removeAll()
        }
    }
}
