//
//  ObjMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

class ObjModel: Model {
    init(_ modelName: String) {
        guard let assetUrl = Bundle.main.url(forResource: modelName, withExtension: ModelExtension.OBJ.rawValue) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        let descriptor = Mesh.createMdlVertexDescriptor()
    
        let asset = MDLAsset(url: assetUrl,
                             vertexDescriptor: descriptor,
                             bufferAllocator: Mesh.mtkMeshBufferAllocator,
                             preserveTopology: false,
                             error: nil)
        
        print("[ObjModel init] Created asset: \(asset)")
        asset.loadTextures()
        print("[ObjModel init] Loaded asset textures")
        
        var objMeshes: [Mesh] = []
        
        for i in 0..<asset.count {
            let child = asset.object(at: i)
            print("[ObjModel init] \(modelName) child name: \(child.name)")
            objMeshes.append(contentsOf: ObjModel.makeMeshes(object: child, vertexDescriptor: descriptor))
        }
        
//        invertMeshZ()
        
        super.init(meshes: objMeshes)
    }
    
    private static func makeMeshes(object: MDLObject, vertexDescriptor: MDLVertexDescriptor) -> [Mesh] {
        var meshes = [Mesh]()
        
        print("[ObjModel makeMeshes] object named \(object.name): \(object)")
        
        if let mesh = object as? MDLMesh {
            print("[ObjModel makeMeshes] object named \(object.name) is MDLMesh")
            let newMesh = Mesh(mdlMesh: mesh, vertexDescriptor: vertexDescriptor)
            meshes.append(newMesh)
        }
        
        for child in object.children.objects {
            let childMeshes = ObjModel.makeMeshes(object: child, vertexDescriptor: vertexDescriptor)
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
