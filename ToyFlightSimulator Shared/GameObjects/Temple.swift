//
//  Temple.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 1/31/24.
//

import MetalKit

//class Temple: GameObject {
//    let cameraOffset: float3 = float3(0, 10, 10)
//    init(scale: Float) {
//        super.init(name: "Temple", meshType: .Temple)
//        self.setScale(scale)
//    }
//}

// Inheriting from Aircraft for testing:
class Temple: Aircraft {
    init(scale: Float) {
        super.init(name: "Temple", modelType: .Temple, scale: scale)
    }
}
