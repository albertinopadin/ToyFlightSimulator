//
//  Capsule.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/9/23.
//

class CapsuleObject: GameObject {
    init() {
        super.init(name: "Capsule", modelType: .Capsule)
        var material = MaterialProperties()
        material.setColor(WHITE_COLOR)
        useMaterial(material)
    }
}
