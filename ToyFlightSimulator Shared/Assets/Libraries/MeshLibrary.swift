//
//  MeshLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum MeshType {
    case None
    case Triangle_Custom
    case Quad_Custom
    case Cube_Custom
    case Sphere_Custom
    case Capsule_Custom
    
    case Sphere
    case Quad
    
    case SkySphere
    case Skybox
    
    case F16
    case F18
    
    case RC_F18
    case CGTrader_F35
    case Sketchfab_F35
    
    case Icosahedron
}

class MeshLibrary: Library<MeshType, Mesh> {
    private var _library: [MeshType: Mesh] = [:]
    
    override func makeLibrary() {
        _library.updateValue(NoMesh(), forKey: .None)
        _library.updateValue(TriangleMesh(), forKey: .Triangle_Custom)
        _library.updateValue(QuadMesh(), forKey: .Quad_Custom)
        _library.updateValue(CubeMesh(), forKey: .Cube_Custom)
        _library.updateValue(SphereMesh(), forKey: .Sphere_Custom)
        _library.updateValue(CapsuleMesh(), forKey: .Capsule_Custom)
        _library.updateValue(SkyboxMesh(), forKey: .Skybox)
        
        _library.updateValue(ObjMesh("sphere"), forKey: .Sphere)
        _library.updateValue(ObjMesh("quad"), forKey: .Quad)
        _library.updateValue(ObjMesh("skysphere"), forKey: .SkySphere)
        
        _library.updateValue(ObjMesh("f16r"), forKey: .F16)
        _library.updateValue(ObjMesh("FA-18F"), forKey: .F18)
        
        _library.updateValue(UsdMesh("FA-18F"), forKey: .RC_F18)
        _library.updateValue(UsdMesh("F35_JSF", fileExtension: .USDC), forKey: .CGTrader_F35)
//        _library.updateValue(UsdMesh("F-35A_Lightning_II"), forKey: .Sketchfab_F35)
        
        _library.updateValue(IcosahedronMesh(), forKey: .Icosahedron)
    }
    
    override subscript(type: MeshType) -> Mesh {
        return _library[type]!
    }
}

class NoMesh: Mesh { }

class TriangleMesh: Mesh {
    override func createMesh() {
        addVertex(position: float3( 0, 1,0), color: float4(1,0,0,1), textureCoordinate: float2(0.5,0.0), normal: float3(0,0,1))
        addVertex(position: float3(-1,-1,0), color: float4(0,1,0,1), textureCoordinate: float2(0.0,1.0), normal: float3(0,0,1))
        addVertex(position: float3( 1,-1,0), color: float4(0,0,1,1), textureCoordinate: float2(1.0,1.0), normal: float3(0,0,1))
    }
}

class QuadMesh: Mesh {
    override func createMesh() {
        addVertex(position: float3( 1, 1,0),
                  color: float4(1,0,0,1),
                  textureCoordinate: float2(1,0),
                  normal: float3(0,0,1)) //Top Right
        addVertex(position: float3(-1, 1,0),
                  color: float4(0,1,0,1),
                  textureCoordinate: float2(0,0),
                  normal: float3(0,0,1)) //Top Left
        addVertex(position: float3(-1,-1,0),
                  color: float4(0,0,1,1),
                  textureCoordinate: float2(0,1),
                  normal: float3(0,0,1)) //Bottom Left
        addVertex(position: float3( 1,-1,0),
                  color: float4(1,0,1,1),
                  textureCoordinate: float2(1,1),
                  normal: float3(0,0,1)) //Bottom Right
        
        addSubmesh(Submesh(indices: [
            0,1,2,
            0,2,3
        ]))
    }
}

class CubeMesh: Mesh {
    override func createMesh() {
        //Left
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0,-1.0, 1.0),
                  color: float4(0.0, 1.0, 0.5, 1.0),
                  textureCoordinate: float2(0,0),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(0.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(0,1),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,1),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(1.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(-1, 0, 0))
        
        //RIGHT
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 0.0, 0.5, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(0.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(0.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        
        //TOP
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 0.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(0.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(0,0),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(0.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(0,1),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,1),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(0.5, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(1.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 1, 0))
        
//        addSubmesh(Submesh(indices: [
//            0,1,2,
//            0,2,3
//        ]))
        
        //BOTTOM
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(0.5, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(0.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 1.0, 0.5, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3(-1.0,-1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        
        //BACK
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(0.5, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(0.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0,0.5,1.0,1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(0,0,-1))
        
        //FRONT
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3(-1.0,-1.0, 1.0),
                  color: float4(0.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(0,0),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(0.5, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(0,1),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 1.0, 0.5, 1.0),
                  textureCoordinate: float2(1,1),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0, 1))
    }
}

class SphereMesh: Mesh {
    private var _color: float4
    
    init(radius: Float = 1.0, color: float4 = BLUE_COLOR) {
        let diameter = radius * 2
        _color = color
        
        let allocator = MTKMeshBufferAllocator(device: Engine.Device)
        let mdlSphere = MDLMesh(sphereWithExtent: float3(diameter, diameter, diameter),
                                segments: SIMD2<UInt32>(100, 100),
                                inwardNormals: false,
                                geometryType: .triangles,
                                allocator: allocator)
        
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
        
        let allocator = MTKMeshBufferAllocator(device: Engine.Device)
        let mdlCapsule = MDLMesh(capsuleWithExtent: float3(radius, length, radius),
                                 cylinderSegments: vector_uint2(32, 32),
                                 hemisphereSegments: 32,
                                 inwardNormals: false,
                                 geometryType: .triangles,
                                 allocator: allocator)
        
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
        let allocator = MTKMeshBufferAllocator(device: Engine.Device)
        let mdlIcosahedron = MDLMesh.newIcosahedron(withRadius: icoRadius, inwardNormals: false, allocator: allocator)
        
        let vertDesc = MDLVertexDescriptor()
        let positionAttr = vertDesc.attribute(TFSVertexAttributePosition.rawValue)
        positionAttr.name = MDLVertexAttributePosition
        positionAttr.format = .float4
        positionAttr.offset = 0
        positionAttr.bufferIndex = Int(TFSBufferIndexMeshPositions.rawValue)
        
        vertDesc.layout(TFSVertexAttributePosition.rawValue).stride = float4.stride
        
        mdlIcosahedron.vertexDescriptor = vertDesc
        
        let mtkIcosahedron = try! MTKMesh(mesh: mdlIcosahedron, device: Engine.Device)
        super.init(mtkMesh: mtkIcosahedron, mdlMesh: mdlIcosahedron, addTangentBases: false)
    }
}

class SkyboxMesh: Mesh {
    override init() {
        let allocator = MTKMeshBufferAllocator(device: Engine.Device)
        let sphereMDLMesh = MDLMesh.newEllipsoid(withRadii: float3(repeating: 150),  // 150
                                                 radialSegments: 20,
                                                 verticalSegments: 20,
                                                 geometryType: .triangles,
                                                 inwardNormals: false,
                                                 hemisphere: false,
                                                 allocator: allocator)
        let sphereDescriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Skybox])
        sphereDescriptor.attribute(0).name = MDLVertexAttributePosition
        sphereDescriptor.attribute(1).name = MDLVertexAttributeNormal
        
        sphereMDLMesh.vertexDescriptor = sphereDescriptor
        let mtkMesh = try! MTKMesh(mesh: sphereMDLMesh, device: Engine.Device)
        super.init(mtkMesh: mtkMesh, mdlMesh: sphereMDLMesh, addTangentBases: false)
    }
}
