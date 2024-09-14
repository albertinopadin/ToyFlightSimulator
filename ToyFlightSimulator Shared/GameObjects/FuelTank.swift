//
//  FuelTank.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/4/23.
//

class FuelTank: Droppable {
    init() {
        super.init(name: "Fuel_Tank",
                   modelType: .F18,
                   meshType: .F18_FuelTank,
                   renderPipelineStateType: .OpaqueMaterial)
    }
    
    init(modelName: String, submeshName: String) {
        super.init(name: "Fuel_Tank", modelName: modelName, submeshName: submeshName)
    }
}
