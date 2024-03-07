//
//  BasicMeshes.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/5/24.
//

import MetalKit

class NoMesh: Mesh { }

class PlaneMesh: Mesh {
    init(extent: float3 = [1, 1, 1], segments: simd_uint2 = [4, 4]) {
        let mdlPlane = MDLMesh(planeWithExtent: extent,
                               segments: segments,
                               geometryType: .triangles,
                               allocator: Self.mtkMeshBufferAllocator)
        mdlPlane.vertexDescriptor = Graphics.MDLVertexDescriptors[.Base]
        mdlPlane.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                 tangentAttributeNamed: MDLVertexAttributeTangent,
                                 bitangentAttributeNamed: MDLVertexAttributeBitangent)
        let mtkMesh = try! MTKMesh(mesh: mdlPlane, device: Engine.Device)
        
        // TODO: Figure out why mesh seems to have normals opposite of front faces, which
        //       causes stencil depth test failures when rendering directional lights.
        Self.invertMeshNormals(mtkMesh: mtkMesh)
        
        super.init(mtkMesh: mtkMesh, mdlMesh: mdlPlane, addTangentBases: false)
    }
    
    static func invertMeshNormals(mtkMesh: MTKMesh) {
        let vertexLayoutStride = (mtkMesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride
        for meshBuffer in mtkMesh.vertexBuffers {
            for i in 0..<mtkMesh.vertexCount {
                let vertexPosition = (i * vertexLayoutStride)
                let vertexPtr = meshBuffer.buffer.contents()
                                                 .advanced(by: vertexPosition)
                                                 .bindMemory(to: Vertex.self, capacity: 1)
                var vertexValue: Vertex = vertexPtr.pointee
                vertexValue.normal = -vertexValue.normal
                vertexPtr.pointee = vertexValue
            }
        }
    }
}

class SphereMesh: Mesh {
    private var _color: float4
    
    init(radius: Float = 1.0, color: float4 = BLUE_COLOR) {
        let diameter = radius * 2
        _color = color
        
        let mdlSphere = MDLMesh(sphereWithExtent: float3(diameter, diameter, diameter),
                                segments: SIMD2<UInt32>(100, 100),
                                inwardNormals: false,
                                geometryType: .triangles,
                                allocator: Self.mtkMeshBufferAllocator)
        
        mdlSphere.vertexDescriptor = Graphics.MDLVertexDescriptors[.Base]
        let mtkMesh = try! MTKMesh(mesh: mdlSphere, device: Engine.Device)

        let vertexLayoutStride = (mtkMesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride
        for meshBuffer in mtkMesh.vertexBuffers {
            for i in 0..<mtkMesh.vertexCount {
                let colorPosition = (i * vertexLayoutStride) + float4.stride
                meshBuffer.buffer.contents().advanced(by: colorPosition).copyMemory(from: &_color, byteCount: float4.stride)
            }
        }
        
        super.init(mtkMesh: mtkMesh, mdlMesh: mdlSphere)
    }
}

class CapsuleMesh: Mesh {
    private var _color: float4
    
    init(radius: Float = 1.0, length: Float = 5.0, color: float4 = WHITE_COLOR) {
        _color = color
        
        let mdlCapsule = MDLMesh(capsuleWithExtent: float3(radius, length, radius),
                                 cylinderSegments: vector_uint2(32, 32),
                                 hemisphereSegments: 32,
                                 inwardNormals: false,
                                 geometryType: .triangles,
                                 allocator: Self.mtkMeshBufferAllocator)
        
        mdlCapsule.vertexDescriptor = Graphics.MDLVertexDescriptors[.Base]
        let mtkMesh = try! MTKMesh(mesh: mdlCapsule, device: Engine.Device)
        
        let vertexLayoutStride = (mtkMesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride
        for meshBuffer in mtkMesh.vertexBuffers {
            for i in 0..<mtkMesh.vertexCount {
                let colorPosition = (i * vertexLayoutStride) + float4.stride
                meshBuffer.buffer.contents().advanced(by: colorPosition).copyMemory(from: &_color, byteCount: float4.stride)
            }
        }
        
        super.init(mtkMesh: mtkMesh, mdlMesh: mdlCapsule)
    }
}

class IcosahedronMesh: Mesh {
    override init() {
        let icoRadius = sqrtf(3.0) / 12.0 * (3.0 + sqrtf(5.0))
        let mdlIcosahedron = MDLMesh.newIcosahedron(withRadius: icoRadius, 
                                                    inwardNormals: false,
                                                    allocator: Self.mtkMeshBufferAllocator)
        
        let vertDesc = MDLVertexDescriptor()
        let positionAttr = vertDesc.attribute(TFSVertexAttributePosition.rawValue)
        positionAttr.name = MDLVertexAttributePosition
        positionAttr.format = .float4
        positionAttr.offset = 0
        positionAttr.bufferIndex = TFSBufferIndexMeshPositions.index
        
        vertDesc.layout(TFSVertexAttributePosition.rawValue).stride = float4.stride
        
        mdlIcosahedron.vertexDescriptor = vertDesc
        
        let mtkIcosahedron = try! MTKMesh(mesh: mdlIcosahedron, device: Engine.Device)
        super.init(mtkMesh: mtkIcosahedron, mdlMesh: mdlIcosahedron, addTangentBases: false)
    }
}

class SkyboxMesh: Mesh {
    override init() {
        let sphereMDLMesh = MDLMesh.newEllipsoid(withRadii: float3(repeating: 150),  // 150
                                                 radialSegments: 20,
                                                 verticalSegments: 20,
                                                 geometryType: .triangles,
                                                 inwardNormals: false,
                                                 hemisphere: false,
                                                 allocator: Self.mtkMeshBufferAllocator)
        let sphereDescriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Skybox])
        sphereDescriptor.attribute(0).name = MDLVertexAttributePosition
        sphereDescriptor.attribute(1).name = MDLVertexAttributeNormal
        
        sphereMDLMesh.vertexDescriptor = sphereDescriptor
        let mtkMesh = try! MTKMesh(mesh: sphereMDLMesh, device: Engine.Device)
        super.init(mtkMesh: mtkMesh, mdlMesh: sphereMDLMesh, addTangentBases: false)
    }
}
