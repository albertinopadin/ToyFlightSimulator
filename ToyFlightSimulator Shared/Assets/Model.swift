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
    public var parent: GameObject?
    
    init(mesh: Mesh) {
        meshes.append(mesh)
        meshes.forEach { $0.parentModel = self }
    }
    
    init(meshes: [Mesh]) {
        self.meshes = meshes
        meshes.forEach { $0.parentModel = self }
    }
}
