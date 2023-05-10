//
//  Sidewinder.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

class Sidewinder: Missile {
    init() {
        super.init(name: "Sidewinder", meshType: .F18_Sidewinder, renderPipelineStateType: .OpaqueMaterial)
    }
    
    init(modelName: String, submeshName: String) {
        super.init(name: "Sidewinder", modelName: modelName, submeshName: submeshName)
    }
}
