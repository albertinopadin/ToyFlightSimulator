//
//  SingleSMMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit

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

class SingleSMMesh {
    public var name: String = "SingleSMMesh"
    private var _vertices: [Vertex] = []
    private var _vertexCount: Int = 0
    private var _vertexBuffer: MTLBuffer!
    private var _instanceCount: Int = 1
    internal var _submesh: Submesh!
    public let vertexMetadata: SingleMeshVertexMetadata

    init(mtkMesh: MTKMesh, submesh: Submesh) {
        name = submesh.name

        if mtkMesh.vertexBuffers.count > 1 {
            print("[SingleSMMesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
        }
        self._vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        self._vertexCount = mtkMesh.vertexCount
        _submesh = submesh
        
        // Centralize vertices:
        vertexMetadata = SingleSMMesh.getVertexMetadata(submesh: _submesh, vertexBuffer: _vertexBuffer, vertexCount: _vertexCount)
        
        print("[SingleSMMesh init] \(name) Initial average vertex position: \(vertexMetadata.initialPositionInParentMesh)")
        print("[SingleSMMesh init] \(name) vertex count: \(vertexMetadata.uniqueVertices)")
        
        print("[SingleSMMesh init] \(name) mesh vertex metadata: \(vertexMetadata)")
        
        translateSubmeshVertices(delta: -vertexMetadata.initialPositionInParentMesh)
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
        SingleSMMesh.processVertices(submesh: _submesh, vertexBuffer: _vertexBuffer, vertexCount: _vertexCount) {
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
            _vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices,
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
                                                         object: MDLObject,
                                                         vertexDescriptor: MDLVertexDescriptor) -> SingleSMMesh? {
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
                print("[SingleSMMesh makeSingleSMMeshWithSubmeshNamed] Creating Submesh...")
                let submesh = Submesh(mtkSubmesh: mtkSubmesh, 
                                      mdlSubmesh: mdlSubmesh)
                return SingleSMMesh(mtkMesh: metalKitMesh, submesh: submesh)
            }
        }

        if object.conforms(to: MDLObjectContainerComponent.self) {
            for child in object.children.objects {
                if let mesh = makeSingleSMMeshWithSubmeshNamed(submeshName,
                                                               object: child,
                                                               vertexDescriptor: vertexDescriptor) {
                    return mesh
                }
            }
        }
        
        return nil
    }

    public static func createSingleSMMeshFromModel(modelName: String, submeshName: String, ext: String = "obj") -> SingleSMMesh {
        print("[createSingleSMMeshFromModel] model name: \(modelName)")

        guard let assetURL = Bundle.main.url(forResource: modelName, withExtension: ext) else {
            fatalError("Asset \(modelName) does not exist.")
        }

        let descriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Base])
        descriptor.attribute(TFSVertexAttributePosition.rawValue).name  = MDLVertexAttributePosition
        descriptor.attribute(TFSVertexAttributeColor.rawValue).name     = MDLVertexAttributeColor
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).name  = MDLVertexAttributeTextureCoordinate
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).name    = MDLVertexAttributeNormal
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).name   = MDLVertexAttributeTangent
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).name = MDLVertexAttributeBitangent

        let asset: MDLAsset = MDLAsset(url: assetURL,
                                       vertexDescriptor: descriptor,
                                       bufferAllocator: Mesh.mtkMeshBufferAllocator,
                                       preserveTopology: false,
                                       error: nil)
        asset.loadTextures()

        let child = asset.childObjects(of: MDLObject.self)[0]
        print("[createSingleSMMeshFromModel] \(modelName) child name: \(child.name)")
        
        guard let cMesh = SingleSMMesh.makeSingleSMMeshWithSubmeshNamed(submeshName,
                                                                        object: child,
                                                                        vertexDescriptor: descriptor) else {
            fatalError("[SingleSMMesh makeMeshWithSubmeshNamed] Could not find any submesh named \(submeshName)")
        }
        
        return cMesh
    }

    func setInstanceCount(_ count: Int) {
        self._instanceCount = count
    }

    func applyMaterial(renderEncoder: MTLRenderCommandEncoder, material: MaterialProperties?) {
        var mat = material
        renderEncoder.setFragmentBytes(&mat, length: MaterialProperties.stride, index: TFSBufferIndexMaterial.index)
    }

    func drawPrimitives(_ renderEncoder: MTLRenderCommandEncoder,
                        material: MaterialProperties? = nil,
                        applyMaterials: Bool = true,
                        baseColorTextureType: TextureType = .None,
                        normalMapTextureType: TextureType = .None,
                        specularTextureType: TextureType = .None) {
        if let _vertexBuffer {
            renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)

            if applyMaterials {
                _submesh.material?.applyTextures(with: renderEncoder,
                                                 baseColorTextureType: baseColorTextureType,
                                                 normalMapTextureType: normalMapTextureType,
                                                 specularTextureType: specularTextureType)
                _submesh.applyMaterial(with: renderEncoder, customMaterial: material)
            }

            renderEncoder.drawIndexedPrimitives(type: _submesh.primitiveType,
                                                indexCount: _submesh.indexCount,
                                                indexType: _submesh.indexType,
                                                indexBuffer: _submesh.indexBuffer,
                                                indexBufferOffset: _submesh.indexBufferOffset,
                                                instanceCount: _instanceCount)
        }
    }

    func drawShadowPrimitives(_ renderEncoder: MTLRenderCommandEncoder) {
        if let _vertexBuffer = _vertexBuffer {
            renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)

            renderEncoder.drawIndexedPrimitives(type: _submesh.primitiveType,
                                                indexCount: _submesh.indexCount,
                                                indexType: _submesh.indexType,
                                                indexBuffer: _submesh.indexBuffer,
                                                indexBufferOffset: _submesh.indexBufferOffset,
                                                instanceCount: _instanceCount)
        }
    }
}

