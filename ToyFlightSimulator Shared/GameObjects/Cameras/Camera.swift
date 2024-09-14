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
    var fieldOfView: Float!
    var near: Float!
    var far: Float!
    
    var cameraType: CameraType!
    var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    private var _viewMatrix = matrix_identity_float4x4
    var viewMatrix: matrix_float4x4 {
        get {
            return _viewMatrix
        }
        
        set {
            _viewMatrix = newValue
        }
    }
    
    init(name: String,
         cameraType: CameraType,
         aspectRatio: Float,
         fieldOfView: Float = 45.0,
         near: Float = 0.1,
         far: Float = 1000) {
        super.init(name: name, modelType: .None)
        self.cameraType = cameraType
        self.fieldOfView = fieldOfView
        self.near = near
        self.far = far
        
        self.projectionMatrix = matrix_float4x4.perspective(degreesFov: fieldOfView,
                                                            aspectRatio: aspectRatio,
                                                            near: near,
                                                            far: far)
    }
    
    func setAspectRatio(_ aspectRatio: Float) {
        projectionMatrix = matrix_float4x4.perspective(degreesFov: fieldOfView,
                                                       aspectRatio: aspectRatio,
                                                       near: near,
                                                       far: far)
    }
    
    override func updateModelMatrix() {
        super.updateModelMatrix()
        _viewMatrix = matrix_identity_float4x4
        _viewMatrix = matrix_multiply(_viewMatrix, rotationMatrix)
        _viewMatrix.translate(direction: -self.getPosition())
    }
}
