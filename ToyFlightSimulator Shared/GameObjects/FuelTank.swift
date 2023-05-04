//
//  FuelTank.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/4/23.
//

class FuelTank: Droppable {
    init() {
        super.init(name: "Fuel Tank", meshType: .F18_FuelTank, renderPipelineStateType: .OpaqueMaterial)
    }
}
