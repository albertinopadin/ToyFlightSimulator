//
//  F35.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/21/23.
//

class F35: Aircraft {
    static let NAME: String = "F-35"
    
    override var cameraOffset: float3 {
        [0, 10, 24]
    }
    
    init(scale: Float = 1.0, shouldUpdate: Bool = true) {
        super.init(name: Self.NAME, modelType: .Sketchfab_F35, scale: scale, shouldUpdate: shouldUpdate)
//        rotateY(Float(180).toRadians)
        rotateX(Float(90).toRadians)
        rotateY(Float(180).toRadians)
    }
}
