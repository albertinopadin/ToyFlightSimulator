//
//  UsdMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

class UsdMesh: Mesh {
    init(_ modelName: String) {
        super.init()
        
        guard let assetUrl = Bundle.main.url(forResource: modelName, withExtension: MeshExtension.OBJ.rawValue) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
        
        let descriptor = Mesh.createMdlVertexDescriptor()
        let asset = MDLAsset(url: assetUrl, vertexDescriptor: descriptor, bufferAllocator: bufferAllocator)
        
        asset.loadTextures()
        
        let assetChildren = asset.childObjects(of: MDLObject.self)
        print("[UsdMesh init] \(modelName) child count: \(assetChildren.count)")
        for child in assetChildren {
            print("[UsdMesh init] \(modelName) child name: \(child.name)")
            _childMeshes.append(contentsOf: UsdMesh.makeMeshes(object: child, vertexDescriptor: descriptor))
        }
        
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
            let childMeshes = UsdMesh.makeMeshes(object: child, vertexDescriptor: vertexDescriptor)
            meshes.append(contentsOf: childMeshes)
        }
        
        return meshes
    }
}
