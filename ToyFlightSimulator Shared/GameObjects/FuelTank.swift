//
//  FuelTank.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/4/23.
//

class FuelTank: Droppable {
    init() {
        super.init(name: "Fuel_Tank", modelType: .F18_FuelTank_Center, meshType: .F18_FuelTank_Center)
    }
    
    init(modelType: ModelType) {
        var meshType: SingleSMMeshType
        
        switch modelType {
            case .F18_FuelTank_Left:
                meshType = .F18_FuelTank_Left
            case .F18_FuelTank_Right:
                meshType = .F18_FuelTank_Right
            default:
                meshType = .F18_FuelTank_Center
        }
        
        super.init(name: "Fuel_Tank", modelType: modelType, meshType: meshType)
    }
}
