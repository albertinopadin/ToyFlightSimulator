//
//  Cube.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/20/22.
//

class Cube: GameObject {
    init(materialProperties: MaterialProperties? = nil) {
        super.init(name: "Cube", modelType: .Cube, materialProperties: materialProperties)
    }
}
