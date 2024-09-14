//
//  Model.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/13/24.
//

import MetalKit

enum ModelExtension: String {
    case OBJ = "obj"
    case USDC = "usdc"
    case USDZ = "usdz"
}

class Model {
    public var meshes: [Mesh] = []
    
    init() {
        meshes.append(Mesh())
    }
    
    init(mesh: Mesh) {
        meshes.append(mesh)
    }
    
    func draw(_ renderEncoder: MTLRenderCommandEncoder,
              material: MaterialProperties? = nil,
              applyMaterials: Bool = true,
              baseColorTextureType: TextureType = .None,
              normalMapTextureType: TextureType = .None,
              specularTextureType: TextureType = .None,
              submeshesToDisplay: [String: Bool]? = nil) {
        for mesh in meshes {
            mesh.drawPrimitives(renderEncoder,
                                 material: material,
                                 applyMaterials: applyMaterials,
                                 baseColorTextureType: baseColorTextureType,
                                 normalMapTextureType: normalMapTextureType,
                                 specularTextureType: specularTextureType,
                                 submeshesToDisplay: submeshesToDisplay)
        }
    }
    
    func drawShadow(_ renderEncoder: MTLRenderCommandEncoder, submeshesToDisplay: [String: Bool]? = nil) {
        for mesh in meshes {
            mesh.drawShadowPrimitives(renderEncoder, submeshesToDisplay: submeshesToDisplay)
        }
    }
}
