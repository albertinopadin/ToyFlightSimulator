//
//  Camera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import simd

enum CameraType {
    case Debug
    case F16Cam
}

class Camera: GameObject {
    var cameraType: CameraType!
    
    private var _viewMatrix = matrix_identity_float4x4
    var viewMatrix: matrix_float4x4 {
        get {
            return _viewMatrix
        }
        
        set {
            _viewMatrix = newValue
        }
    }
    
    var projectionMatrix: matrix_float4x4 {
        return matrix_identity_float4x4
    }
    
    init(name: String, cameraType: CameraType) {
        super.init(name: name, meshType: .None)
        self.cameraType = cameraType
    }
    
    override func updateModelMatrix() {
        super.updateModelMatrix()
        _viewMatrix = matrix_identity_float4x4
        _viewMatrix.rotate(angle: self.getRotationX(), axis: X_AXIS)
        _viewMatrix.rotate(angle: self.getRotationY(), axis: Y_AXIS)
        _viewMatrix.rotate(angle: self.getRotationZ(), axis: Z_AXIS)
        _viewMatrix.translate(direction: -self.getPosition())
    }
}
