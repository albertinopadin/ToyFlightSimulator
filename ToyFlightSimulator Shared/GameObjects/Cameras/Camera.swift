//
//  Camera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import simd

enum CameraType {
    case Debug
    case Attached
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
        _viewMatrix = matrix_multiply(_viewMatrix, rotationMatrix)
        _viewMatrix.translate(direction: -self.getPosition())
    }
}
