//
//  Sidewinder.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

class Sidewinder: Missile {
    init() {
        super.init(name: "Sidewinder", 
                   modelType: .F18,
                   meshType: .F18_Sidewinder,
                   renderPipelineStateType: .OpaqueMaterial)
    }
    
    init(modelName: String, submeshName: String) {
        super.init(name: "Sidewinder", modelName: modelName, submeshName: submeshName)
    }
}
