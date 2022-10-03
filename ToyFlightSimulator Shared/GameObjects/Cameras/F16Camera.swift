//
//  F16Camera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/2/22.
//

import simd

class F16Camera: Camera {
    private var _projectionMatrix = matrix_identity_float4x4
    override var projectionMatrix: matrix_float4x4 {
        return _projectionMatrix
    }
    
    init() {
        super.init(name: "F16Camera", cameraType: .F16Cam)
        _projectionMatrix = matrix_float4x4.perspective(degreesFov: 45.0,
                                                        aspectRatio: Renderer.AspectRatio,
                                                        near: 0.1,
                                                        far: 1000)
    }
}
