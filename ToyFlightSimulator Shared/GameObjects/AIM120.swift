//
//  AIM120.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/9/23.
//

class AIM120: Missile {
    init() {
        super.init(name: "AIM-120",  modelType: .F18, meshType: .F18_AIM120)
    }
    
    init(modelName: String, submeshName: String) {
        super.init(name: "AIM-120", modelName: modelName, submeshName: submeshName)
    }
}
