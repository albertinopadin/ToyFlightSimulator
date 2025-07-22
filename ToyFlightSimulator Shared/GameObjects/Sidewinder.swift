//
//  Sidewinder.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

class Sidewinder: Missile {
    init() {
        super.init(name: "Sidewinder",  modelType: .F18_Sidewinder_Right, meshType: .F18_Sidewinder_Right)
    }
    
    init(modelType: ModelType) {
        let meshType: SingleSMMeshType = modelType == .F18_Sidewinder_Right ? .F18_Sidewinder_Right : .F18_Sidewinder_Left
        super.init(name: "AIM9_Sidewinder", modelType: modelType, meshType: meshType)
    }
}
