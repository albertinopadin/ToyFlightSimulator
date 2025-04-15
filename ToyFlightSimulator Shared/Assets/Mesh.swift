//
//  Mesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/6/23.
//

@preconcurrency import MetalKit

class Mesh {
    public static let mtkMeshBufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
    
    private static let loadingQueue = DispatchQueue(label: "mesh-model-loading-queue")
    
    public var name: String = "Mesh"
    public var parentModel: Model?
    
    public var vertexBuffer: MTLBuffer! = nil
    public var instanceCount: Int = 1
    public var submeshes: [Submesh] = []
    
    internal var _vertices: [Vertex] = []
    internal var _vertexCount: Int = 0
    internal var _metalKitMesh: MTKMesh? = nil
    
    init() {
        createMesh()
        createBuffer()
    }
    
    init(mdlMesh: MDLMesh, vertexDescriptor: MDLVertexDescriptor, addTangentBases: Bool = true) {
        print("[Mesh init] mdlMesh name: \(mdlMesh.name)")
        name = mdlMesh.name
        
        if addTangentBases {
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                    normalAttributeNamed: MDLVertexAttributeNormal,
                                    tangentAttributeNamed: MDLVertexAttributeTangent)
            
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                    tangentAttributeNamed: MDLVertexAttributeTangent,
                                    bitangentAttributeNamed: MDLVertexAttributeBitangent)
        }
        
        mdlMesh.vertexDescriptor = vertexDescriptor
        do {
            print("[Mesh init] instantiating MTKMesh...")
            _metalKitMesh = try MTKMesh(mesh: mdlMesh, device: Engine.Device)
            print("[Mesh init] MTKMesh: \(String(describing: _metalKitMesh))")
            if _metalKitMesh!.vertexBuffers.count > 1 {
                print("[Mesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
            }
            self.vertexBuffer = _metalKitMesh!.vertexBuffers[0].buffer
            self._vertexCount = _metalKitMesh!.vertexCount
            for i in 0..<_metalKitMesh!.submeshes.count {
                let mtkSubmesh = _metalKitMesh!.submeshes[i]
                let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
                let submesh = Submesh(mtkSubmesh: mtkSubmesh, 
                                      mdlSubmesh: mdlSubmesh)
                addSubmesh(submesh)
            }
        } catch {
            print("ERROR::LOADING_MDLMESH::__::\(error.localizedDescription)")
        }
        
        print("Num submeshes for \(mdlMesh.name): \(submeshes.count)")
    }
    
    init(mtkMesh: MTKMesh, mdlMesh: MDLMesh, addTangentBases: Bool = true) {
        name = mtkMesh.name
        
        if addTangentBases {
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                    normalAttributeNamed: MDLVertexAttributeNormal,
                                    tangentAttributeNamed: MDLVertexAttributeTangent)
            
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                    tangentAttributeNamed: MDLVertexAttributeTangent,
                                    bitangentAttributeNamed: MDLVertexAttributeBitangent)
        }
        
        self._metalKitMesh = mtkMesh
        if _metalKitMesh!.vertexBuffers.count > 1 {
            // TODO: Figure out how to handle multiple vertex layouts with potentially multiple buffers
            print("[Mesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
        }
        self.vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        self._vertexCount = mtkMesh.vertexCount
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            let submesh = Submesh(mtkSubmesh: mtkSubmesh, 
                                  mdlSubmesh: mdlSubmesh)
            addSubmesh(submesh)
        }
    }
    
    func createMesh() { }
    
    private func createBuffer() {
        if _vertices.count > 0 {
            vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices,
                                                     length: Vertex.stride(_vertices.count),
                                                     options: [])
        }
    }
    
    internal static func createMdlVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Base])
        descriptor.attribute(TFSVertexAttributePosition.rawValue).name      = MDLVertexAttributePosition
        descriptor.attribute(TFSVertexAttributePosition.rawValue).format    = .float3
        descriptor.attribute(TFSVertexAttributeColor.rawValue).name         = MDLVertexAttributeColor
        descriptor.attribute(TFSVertexAttributeColor.rawValue).format       = .float4
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).name      = MDLVertexAttributeTextureCoordinate
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).format    = .float2
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).name        = MDLVertexAttributeNormal
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).format      = .float3
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).name       = MDLVertexAttributeTangent
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).format     = .float3
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).name     = MDLVertexAttributeBitangent
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).format   = .float3
        return descriptor
    }
    
    func setInstanceCount(_ count: Int) {
        self.instanceCount = count
    }
    
    func addSubmesh(_ submesh: Submesh) {
        self.submeshes.append(submesh)
        submesh.parentMesh = self
    }
    
    func addVertex(position: float3,
                   color: float4 = float4(1, 0, 1, 1),
                   textureCoordinate: float2 = float2(0, 0),
                   normal: float3 = float3(0, 1, 0),
                   tangent: float3 = float3(1, 0, 0),
                   bitangent: float3 = float3(0, 0, 1)) {
        _vertices.append(Vertex(position: position,
                                color: color,
                                textureCoordinate: textureCoordinate,
                                normal: normal,
                                tangent: tangent,
                                bitangent: bitangent))
    }
}
