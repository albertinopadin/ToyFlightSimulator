//
//  GameMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/27/22.
//

import Metal
import MetalKit


func createMDLVertexDescriptor() -> MDLVertexDescriptor {
//    let mdlVD = MDLVertexDescriptor()
//    mdlVD.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
//                                             format: .float3,
//                                             offset: 0,
//                                             bufferIndex: 0)
//    mdlVD.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
//                                             format: .float3,
//                                             offset: 12,
//                                             bufferIndex: 0)
//    mdlVD.layouts[0] = MDLVertexBufferLayout(stride: 24)
//    return mdlVD
    
    var gameVertexDescriptor = GameVertexDescriptor()
    gameVertexDescriptor.addAttribute(name: MDLVertexAttributePosition, format: .float3)
    gameVertexDescriptor.addAttribute(name: MDLVertexAttributeNormal, format: .float3)
    return gameVertexDescriptor.mdlVertexDescriptor
}

func makeCubeMesh(size: Float,
                  device: MTLDevice,
                  vertexDescriptor: MDLVertexDescriptor,
                  allocator: MTKMeshBufferAllocator) -> MTKMesh {
    let mdlBoxMesh = MDLMesh(boxWithExtent: SIMD3<Float>(size, size, size),
                             segments: SIMD3<UInt32>(1, 1, 1),
                             inwardNormals: false,
                             geometryType: .triangles,
                             allocator: allocator)
    mdlBoxMesh.vertexDescriptor = vertexDescriptor
    let boxMesh = try! MTKMesh(mesh: mdlBoxMesh, device: device)
    return boxMesh
}

func makeSphereMesh(size: Float,
                    device: MTLDevice,
                    vertexDescriptor: MDLVertexDescriptor,
                    allocator: MTKMeshBufferAllocator) -> MTKMesh {
    let mdlSphere = MDLMesh(sphereWithExtent: SIMD3<Float>(size, size, size),
                            segments: SIMD2<UInt32>(64, 64),
                            inwardNormals: false,
                            geometryType: .triangles,
                            allocator: allocator)
    mdlSphere.vertexDescriptor = vertexDescriptor
    let sphereMesh = try! MTKMesh(mesh: mdlSphere, device: device)
    return sphereMesh
}
