//
//  ObjMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

final class ObjModel: Model {
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
        
//        invertMeshZ()
        
        let mdlMeshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
        
        let objMeshes = Self.GetMeshes(asset: asset, mdlMeshes: mdlMeshes, descriptor: descriptor)
        
        super.init(name: modelName, meshes: objMeshes)
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
