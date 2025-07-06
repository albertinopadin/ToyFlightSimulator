//
//  UsdMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

class UsdModel: Model {
    var meshIndices: [String: Int] = [:]  // Map mesh names to their indices
    init(_ modelName: String, fileExtension: ModelExtension = .USDZ) {
        guard let assetUrl = Bundle.main.url(forResource: modelName, withExtension: fileExtension.rawValue) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        let descriptor = Mesh.createMdlVertexDescriptor()
        let asset = MDLAsset(url: assetUrl,
                             vertexDescriptor: descriptor,
                             bufferAllocator: Mesh.mtkMeshBufferAllocator)
        
        asset.loadTextures()
        
        var usdMeshes: [Mesh] = []
        
        for i in 0..<asset.count {
            let child = asset.object(at: i)
            print("[UsdModel init] \(modelName) child name: \(child.name)")
            let newMeshes = Self.makeMeshes(object: child, vertexDescriptor: descriptor)
            
            // Track mesh indices by name
            for mesh in newMeshes {
                meshIndices[mesh.name] = usdMeshes.count
                usdMeshes.append(mesh)
            }
        }
        
        // Invert Z in meshes due to USD being right handed coord system:
//        invertMeshZ()  // Not needed for F-22
        
        super.init(name: modelName, meshes: usdMeshes)
        
        print("[UsdModel init] Num meshes for \(modelName): \(meshes.count)")
        print("[UsdModel init] Mesh indices: \(meshIndices)")
    }
    
    private static func makeMeshes(object: MDLObject, vertexDescriptor: MDLVertexDescriptor) -> [Mesh] {
        var meshes = [Mesh]()
        
        print("[UsdModel makeMeshes] object named \(object.name): \(object)")
        
        if let mesh = object as? MDLMesh {
            print("[UsdModel makeMeshes] object named \(object.name) is MDLMesh")
            print("[UsdModel makeMeshes] submesh count: \(mesh.submeshes?.count ?? 0)")
            
            // Log submesh names if available
            if let submeshes = mesh.submeshes as? [MDLSubmesh] {
                for (index, submesh) in submeshes.enumerated() {
                    print("[UsdModel makeMeshes] Submesh \(index): \(submesh.name)")
                }
            }
            
            let newMesh = Mesh(mdlMesh: mesh, vertexDescriptor: vertexDescriptor)
            meshes.append(newMesh)
        }
        
        for child in object.children.objects {
            let childMeshes = Self.makeMeshes(object: child, vertexDescriptor: vertexDescriptor)
            meshes.append(contentsOf: childMeshes)
        }
        
        return meshes
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
