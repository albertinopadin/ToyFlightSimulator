//
//  UsdMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

class UsdMesh: Mesh {
    init(_ modelName: String, fileExtension: MeshExtension = .USDZ) {
        super.init()
        
        guard let assetUrl = Bundle.main.url(forResource: modelName, withExtension: fileExtension.rawValue) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
        
        let descriptor = Self.createMdlVertexDescriptor()
        let asset = MDLAsset(url: assetUrl, vertexDescriptor: descriptor, bufferAllocator: bufferAllocator)
        
        asset.loadTextures()
        
        for i in 0..<asset.count {
            let child = asset.object(at: i)
            print("[UsdMesh init] \(modelName) child name: \(child.name)")
            _childMeshes.append(contentsOf: Self.makeMeshes(object: child, vertexDescriptor: descriptor))
        }
        
        // Invert Z in meshes due to USD being right handed coord system:
        invertMeshZ()
        
        print("[UsdMesh init] Num child meshes for \(modelName): \(_childMeshes.count)")
    }
    
    private static func makeMeshes(object: MDLObject, vertexDescriptor: MDLVertexDescriptor) -> [Mesh] {
        var meshes = [Mesh]()
        
        print("[UsdMesh makeMeshes] object named \(object.name): \(object)")
        
        if let mesh = object as? MDLMesh {
            print("[UsdMesh makeMeshes] object named \(object.name) is MDLMesh")
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
        for mesh in _childMeshes {
            let vertexBuffer = mesh._vertexBuffer!
            let count = vertexBuffer.length / Vertex.stride
            var pointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: count)
            for _ in 0..<count {
                pointer.pointee.position.z = -pointer.pointee.position.z
                pointer = pointer.advanced(by: 1)
            }
        }
    }
}
