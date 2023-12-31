//
//  Icosahedron.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/7/23.
//

class Icosahedron: GameObject {
    init() {
        super.init(name: "Icosahedron", meshType: .Icosahedron, renderPipelineStateType: .Icosahedron)
    }
}
