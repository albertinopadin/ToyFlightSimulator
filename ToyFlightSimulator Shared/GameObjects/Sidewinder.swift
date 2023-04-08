//
//  Sidewinder.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

class Sidewinder: SubMeshGameObject {
    init() {
        super.init(name: "Sidewinder", meshType: .F18_Sidewinder, renderPipelineStateType: .OpaqueMaterial)
    }
}
