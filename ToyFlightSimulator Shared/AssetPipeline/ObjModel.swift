//
//  ObjMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

final class ObjModel: Model {
    init(_ modelName: String, basisTransform: float4x4? = nil) {
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
        
        let mdlMeshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
        
        let objMeshes = Self.GetMeshes(asset: asset,
                                       mdlMeshes: mdlMeshes,
                                       descriptor: descriptor,
                                       basisTransform: basisTransform)
        
        super.init(name: modelName, meshes: objMeshes)
    }
}
