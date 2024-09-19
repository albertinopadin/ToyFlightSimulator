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

class Model: Hashable {
    public let id: String
    public let name: String
    public var meshes: [Mesh] = []
    public var parent: GameObject?
    
    static func == (lhs: Model, rhs: Model) -> Bool {
        return lhs.id == rhs.id
    }
    
    init(name: String, meshes: [Mesh]) {
        self.id = UUID().uuidString
        self.name = name
        self.meshes = meshes
        meshes.forEach { $0.parentModel = self }
    }
    
    convenience init(name: String, mesh: Mesh) {
        self.init(name: name, meshes: [mesh])
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}
