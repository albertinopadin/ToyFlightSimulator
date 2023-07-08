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
    
    case Sphere
    case Quad
    
    case SkySphere
    case Skybox
    
    case F16
    case F18
}

class MeshLibrary: Library<MeshType, Mesh> {
    private var _library: [MeshType: Mesh] = [:]
    
    override func makeLibrary() {
        _library.updateValue(NoMesh(), forKey: .None)
        _library.updateValue(TriangleMesh(), forKey: .Triangle_Custom)
        _library.updateValue(QuadMesh(), forKey: .Quad_Custom)
        _library.updateValue(CubeMesh(), forKey: .Cube_Custom)
        _library.updateValue(SphereMesh(), forKey: .Sphere_Custom)
        _library.updateValue(SkyboxMesh(), forKey: .Skybox)
        
        _library.updateValue(Mesh(modelName: "sphere"), forKey: .Sphere)
        _library.updateValue(Mesh(modelName: "quad"), forKey: .Quad)
        _library.updateValue(Mesh(modelName: "skysphere"), forKey: .SkySphere)
        
        _library.updateValue(Mesh(modelName: "f16r"), forKey: .F16)
        _library.updateValue(Mesh(modelName: "FA-18F", ext: "obj"), forKey: .F18)
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

class Icosahedron: Mesh {
    
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
