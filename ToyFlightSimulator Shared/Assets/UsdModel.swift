//
//  UsdMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

final class UsdModel: Model {
    init(_ modelName: String, fileExtension: ModelExtension = .USDZ, transform: float4x4? = nil) {
        guard let assetUrl = Bundle.main.url(forResource: modelName, withExtension: fileExtension.rawValue) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        let descriptor = Mesh.createMdlVertexDescriptor()
        let asset = MDLAsset(url: assetUrl,
                             vertexDescriptor: descriptor,
                             bufferAllocator: Mesh.mtkMeshBufferAllocator)
        
        asset.loadTextures()
        
        print("[UsdModel init] asset has \(asset.count) top level objects.")
        
        let usdMeshes: [Mesh] = Self.GetMeshes(asset: asset, descriptor: descriptor)
        
        // Invert Z in meshes due to USD being right handed coord system:
//        invertMeshZ()  // Not needed for F-22
        
        super.init(name: modelName, meshes: usdMeshes)
        
        if let transform {
            transformMeshesBasis(transform: transform)
        }
        
        print("[UsdModel init] Num meshes for \(modelName): \(meshes.count)")
    }
    
    private static func GetMeshes(asset: MDLAsset, descriptor: MDLVertexDescriptor) -> [Mesh] {
        let mdlMeshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
        return mdlMeshes.map { Mesh(mdlMesh: $0, vertexDescriptor: descriptor) }
    }
    
    // TODO:
//    private func loadSkeleton(asset: MDLAsset) {
//        let skeletons = asset.childObjects(of: MDLSkeleton.self) as? [MDLSkeleton] ?? []
//        print("[Model loadSkeleton] num skeletons: \(skeletons.count)")
//        skeleton = Skeleton(mdlSkeleton: skeletons.first)
//    }
    
    // TODO: Parallelize this:
    private func transformMeshesBasis(transform: float4x4) {
        for mesh in meshes {
            let vertexBuffer = mesh.vertexBuffer!
            let count = vertexBuffer.length / Vertex.stride
            var pointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: count)
            for _ in 0..<count {
                pointer.pointee.position = simd_mul(float4(pointer.pointee.position, 1), transform).xyz
                pointer.pointee.normal = simd_mul(float4(pointer.pointee.normal, 1), transform).xyz
                pointer.pointee.tangent = simd_mul(float4(pointer.pointee.tangent, 1), transform).xyz
                pointer.pointee.bitangent = simd_mul(float4(pointer.pointee.bitangent, 1), transform).xyz
                pointer = pointer.advanced(by: 1)
            }
        }
    }
    
    private func invertMeshZ() {
        for mesh in meshes {
            let vertexBuffer = mesh.vertexBuffer!
            let count = vertexBuffer.length / Vertex.stride
            var pointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: count)
            for _ in 0..<count {
                pointer.pointee.position.z = -pointer.pointee.position.z
                pointer = pointer.advanced(by: 1)
            }
        }
    }
}
