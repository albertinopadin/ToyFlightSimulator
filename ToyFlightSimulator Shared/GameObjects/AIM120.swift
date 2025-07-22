//
//  AIM120.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/9/23.
//

class AIM120: Missile {
    init() {
        super.init(name: "AIM-120",  modelType: .F18_AIM120_Right, meshType: .F18_AIM120_Right)
    }
    
    init(modelType: ModelType) {
        let meshType: SingleSMMeshType = modelType == .F18_AIM120_Left ? .F18_AIM120_Left : .F18_AIM120_Right
        super.init(name: "AIM120_Slammer", modelType: modelType, meshType: meshType)
    }
}
