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
    
    public var skin: Skin?
    public var transform: TransformComponent?
    
    init() {
        createMesh()
        createBuffer()
    }
    
    init(mdlMesh: MDLMesh, mtkMesh: MTKMesh, basisTransform: float4x4? = nil) {
        print("[Mesh init] mdlMesh name: \(mdlMesh.name)")
        name = mdlMesh.name
        
        self._metalKitMesh = mtkMesh
        if _metalKitMesh!.vertexBuffers.count > 1 {
            // TODO: Figure out how to handle multiple vertex layouts with potentially multiple buffers
            print("[Mesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
        }
        self.vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        let basisFlipsOrientation: Bool = {
            if let basisTransform {
                return transformMeshBasis(basisTransform)
            }
            return false
        }()

        self._vertexCount = mtkMesh.vertexCount
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            let submesh = Submesh(mtkSubmesh: mtkSubmesh,
                                  mdlSubmesh: mdlSubmesh)
            addSubmesh(submesh)
        }

        if basisFlipsOrientation {
            print("[Mesh init] basis transform has det<0 for mesh '\(mdlMesh.name)'; "
                + "reversing triangle winding in \(mtkMesh.submeshes.count) submeshes "
                + "to compensate.")
            reverseTriangleWinding()
        }

        print("[Mesh init] Num submeshes for \(mdlMesh.name): \(submeshes.count)")
    }
    
    convenience init(asset: MDLAsset,
                     mdlMesh: MDLMesh,
                     vertexDescriptor: MDLVertexDescriptor,
                     addTangentBases: Bool = true,
                     basisTransform: float4x4? = nil) {
        do {
            if addTangentBases {
                mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                        normalAttributeNamed: MDLVertexAttributeNormal,
                                        tangentAttributeNamed: MDLVertexAttributeTangent)
                
                mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                        tangentAttributeNamed: MDLVertexAttributeTangent,
                                        bitangentAttributeNamed: MDLVertexAttributeBitangent)
            }
            
            mdlMesh.vertexDescriptor = vertexDescriptor
            
//            mdlMesh.flipTextureCoordinates(inAttributeNamed: MDLVertexAttributeTextureCoordinate)
            
            print("[Mesh init] instantiating MTKMesh...")
            let mtkMesh = try MTKMesh(mesh: mdlMesh, device: Engine.Device)
            print("[Mesh init] MTKMesh: \(String(describing: mtkMesh))")
            self.init(mdlMesh: mdlMesh, mtkMesh: mtkMesh, basisTransform: basisTransform)
        } catch {
            fatalError("ERROR::LOADING_MDLMESH::__::\(error.localizedDescription)")
        }
        
        if mdlMesh.transform != nil {
            transform = TransformComponent(object: mdlMesh,
                                           startTime: asset.startTime,
                                           endTime: asset.endTime,
                                           basisTransform: basisTransform)
        }
    }
    
    convenience init(asset: MDLAsset,
                     mtkMesh: MTKMesh,
                     mdlMesh: MDLMesh,
                     basisTransform: float4x4? = nil) {
        self.init(mdlMesh: mdlMesh, mtkMesh: mtkMesh, basisTransform: basisTransform)
        
        if mdlMesh.transform != nil {
            transform = TransformComponent(object: mdlMesh,
                                           startTime: asset.startTime,
                                           endTime: asset.endTime,
                                           basisTransform: basisTransform)
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
    
    /// Apply `basisTransform` to every vertex's position, normal, tangent, bitangent.
    /// Returns `true` if the basis is orientation-reversing (3x3 determinant < 0), in
    /// which case callers should also reverse triangle index order via
    /// `reverseTriangleWinding()` *after* submeshes have been constructed.
    @discardableResult
    private func transformMeshBasis(_ basisTransform: float4x4) -> Bool {
        let count = vertexBuffer.length / Vertex.stride
        var pointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: count)
        for _ in 0..<count {
            pointer.pointee.position  = simd_mul(float4(pointer.pointee.position,  1), basisTransform).xyz
            pointer.pointee.normal    = simd_mul(float4(pointer.pointee.normal,    0), basisTransform).xyz
            pointer.pointee.tangent   = simd_mul(float4(pointer.pointee.tangent,   0), basisTransform).xyz
            pointer.pointee.bitangent = simd_mul(float4(pointer.pointee.bitangent, 0), basisTransform).xyz
            pointer = pointer.advanced(by: 1)
        }

        let m = basisTransform
        let det = simd_determinant(simd_float3x3(
            SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        ))
        return det < 0
    }

    /// Reverse the per-triangle index order in every submesh so that screen-space
    /// winding flips. Called after `transformMeshBasis` when the basis matrix has
    /// a negative determinant — that mirror flips screen-space winding, and this
    /// reversal puts it back in agreement with the engine's global
    /// `setFrontFacing(.clockwise)`.
    private func reverseTriangleWinding() {
        for submesh in submeshes {
            guard submesh.primitiveType == .triangle else {
                print("[Mesh reverseTriangleWinding] Skipping submesh '\(submesh.name)' "
                    + "with non-triangle primitiveType=\(submesh.primitiveType.rawValue) "
                    + "in mesh '\(name)'. Triangle strips/fans not handled here.")
                continue
            }

            let buffer = submesh.indexBuffer
            let offset = submesh.indexBufferOffset
            let count  = submesh.indexCount
            let triangleCount = count / 3
            guard triangleCount > 0 else { continue }

            switch submesh.indexType {
            case .uint16:
                let p = (buffer.contents() + offset).bindMemory(to: UInt16.self, capacity: count)
                for t in 0..<triangleCount {
                    let base = t * 3
                    let tmp = p[base + 1]
                    p[base + 1] = p[base + 2]
                    p[base + 2] = tmp
                }

            case .uint32:
                let p = (buffer.contents() + offset).bindMemory(to: UInt32.self, capacity: count)
                for t in 0..<triangleCount {
                    let base = t * 3
                    let tmp = p[base + 1]
                    p[base + 1] = p[base + 2]
                    p[base + 2] = tmp
                }

            @unknown default:
                print("[Mesh reverseTriangleWinding] Unknown indexType=\(submesh.indexType.rawValue) "
                    + "in submesh '\(submesh.name)'; cannot reverse winding.")
                continue
            }

            #if os(macOS)
            // MTKMeshBufferAllocator returns shared-storage buffers on iOS/Apple Silicon Macs,
            // but managed buffers can show up on Intel discrete GPUs. didModifyRange is a
            // no-op on shared buffers and required on managed ones.
            if buffer.storageMode == .managed {
                let byteCount = count * indexByteStride(for: submesh.indexType)
                buffer.didModifyRange(offset..<(offset + byteCount))
            }
            #endif
        }
    }

    /// Bytes per index for didModifyRange computations.
    private func indexByteStride(for type: MTLIndexType) -> Int {
        switch type {
            case .uint16: return 2
            case .uint32: return 4
            @unknown default: return 4
        }
    }
    
    internal static func createMdlVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Simple])
        descriptor.attribute(TFSVertexAttributePosition.rawValue).name       = MDLVertexAttributePosition
        descriptor.attribute(TFSVertexAttributePosition.rawValue).format     = .float3
        descriptor.attribute(TFSVertexAttributeColor.rawValue).name          = MDLVertexAttributeColor
        descriptor.attribute(TFSVertexAttributeColor.rawValue).format        = .float4
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).name       = MDLVertexAttributeTextureCoordinate
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).format     = .float2
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).name         = MDLVertexAttributeNormal
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).format       = .float3
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).name        = MDLVertexAttributeTangent
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).format      = .float3
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).name      = MDLVertexAttributeBitangent
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).format    = .float3
        descriptor.attribute(TFSVertexAttributeJoints.rawValue).name         = MDLVertexAttributeJointIndices
        descriptor.attribute(TFSVertexAttributeJoints.rawValue).format       = .uShort4
        descriptor.attribute(TFSVertexAttributeJointWeights.rawValue).name   = MDLVertexAttributeJointWeights
        descriptor.attribute(TFSVertexAttributeJointWeights.rawValue).format = .float4
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
