//
//  Icosahedron.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/7/23.
//

class Icosahedron: GameObject {
    override var objectType: GameObjectType { .icosahedrons }

    init() {
        super.init(name: "Icosahedron", modelType: .Icosahedron)
    }
}
