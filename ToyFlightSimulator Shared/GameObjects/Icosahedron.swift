//
//  Icosahedron.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/7/23.
//

class Icosahedron: GameObject {
    init(materialProperties: MaterialProperties? = nil) {
        super.init(name: "Icosahedron", modelType: .Icosahedron, materialProperties: materialProperties)
    }
}
