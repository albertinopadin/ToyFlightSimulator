//
//  GBU16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/2/23.
//

class GBU16: Droppable {
    init() {
        super.init(name: "GBU16_JDAM", modelType: .F18_GBU16_Right, meshType: .F18_GBU16_Right)
    }
    
    init(modelType: ModelType) {
        let meshType: SingleSMMeshType = modelType == .F18_GBU16_Left ? .F18_GBU16_Left : .F18_GBU16_Right
        super.init(name: "GBU16_JDAM", modelType: modelType, meshType: meshType)
    }
}
