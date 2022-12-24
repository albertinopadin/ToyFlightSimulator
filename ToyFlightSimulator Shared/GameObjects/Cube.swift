//
//  Cube.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/20/22.
//

class Cube: GameObject {
    init() {
        super.init(name: "Cube", meshType: .Cube_Custom)
//        useBaseColorTexture(.BaseColorRender_0)
        useBaseColorTexture(.None)
    }
}
