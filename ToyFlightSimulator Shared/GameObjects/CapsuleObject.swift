//
//  Capsule.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/9/23.
//

class CapsuleObject: GameObject {
    init(materialProperties: MaterialProperties? = nil) {
        super.init(name: "Capsule", modelType: .Capsule)
        var capsuleMaterial = MaterialProperties()
        capsuleMaterial.setColor(WHITE_COLOR)
        self.useMaterial(capsuleMaterial)
    }
}
