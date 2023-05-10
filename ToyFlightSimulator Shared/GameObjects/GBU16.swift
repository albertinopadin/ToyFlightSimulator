//
//  GBU16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/2/23.
//

class GBU16: Droppable {
    init() {
        super.init(name: "GBU16_JDAM", meshType: .F18_GBU16, renderPipelineStateType: .OpaqueMaterial)
    }
    
    init(modelName: String, submeshName: String) {
        super.init(name: "GBU16_JDAM", modelName: modelName, submeshName: submeshName)
    }
}
