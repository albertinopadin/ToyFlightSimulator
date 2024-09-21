//
//  Quad.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

class Quad: GameObject {
    init(materialProperties: MaterialProperties? = nil) {
        super.init(name: "Quad", modelType: .Plane, materialProperties: materialProperties)
    }
}
