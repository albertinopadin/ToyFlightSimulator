//
//  Triangle.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/21/22.
//

class Triangle: GameObject {
    init(materialProperties: MaterialProperties? = nil) {
        super.init(name: "Triangle", modelType: .Triangle, materialProperties: materialProperties)
    }
}
