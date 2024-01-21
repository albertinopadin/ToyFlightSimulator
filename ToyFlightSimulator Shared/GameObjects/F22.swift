//
//  F22.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/20/24.
//

class F22: Aircraft {
    private let _cameraPositionOffset = float3(0, 10, 40)
    static let NAME: String = "F-22"
    
    init(scale: Float = 1.0, shouldUpdate: Bool = true) {
        super.init(name: Self.NAME,
                   meshType: .Sketchfab_F22,
                   renderPipelineStateType: .OpaqueMaterial,
                   scale: scale,
                   shouldUpdate: shouldUpdate)
        rotateX(Float(90).toRadians)
        rotateZ(Float(90).toRadians)
    }
}
