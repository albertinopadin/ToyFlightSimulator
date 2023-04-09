//
//  AIM120.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/9/23.
//

class AIM120: SubMeshGameObject {
    init() {
        super.init(name: "AIM-120", meshType: .F18_AIM120, renderPipelineStateType: .OpaqueMaterial)
    }
}
