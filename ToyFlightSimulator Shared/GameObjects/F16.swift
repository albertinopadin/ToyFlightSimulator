//
//  F16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/29/22.
//

import MetalKit

class F16: Aircraft {
    override var cameraOffset: float3 {
        [0, 13, -33]
    }
    
    init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: "F-16", modelType: .F16, scale: scale, shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
    }
}
