//
//  F16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/29/22.
//

class F16: GameObject {
    init() {
        super.init(name: "F-16", meshType: .F16)
        useBaseColorTexture(.F16)
    }
}
