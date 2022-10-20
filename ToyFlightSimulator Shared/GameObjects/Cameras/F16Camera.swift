//
//  F16Camera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/2/22.
//

import simd

class F16Camera: Camera {
    private var _lastPosition = float3(0, 0, 0)
    private var _lastRotation = float3(0, 0, 0)
    
    private var _moveSpeed: Float = 4.0
    private var _turnSpeed: Float = 1.0
    
    private var _lastModelMatrix = matrix_identity_float4x4
    private var _lastViewMatrix = matrix_identity_float4x4
    private var _lastProjectionMatrix = matrix_identity_float4x4
    
    private var _projectionMatrix = matrix_identity_float4x4
    override var projectionMatrix: matrix_float4x4 {
        return _projectionMatrix
    }
    
    public var positionOffset: float3 = float3(0, 0, 0)
    
//    override var viewMatrix: matrix_float4x4 {
//        get {
////            return matrix_multiply(parentModelMatrix, super.viewMatrix)
//            super.viewMatrix.translate(direction: getPosition())
//            return super.viewMatrix
//        }
//
//        set {
//            super.viewMatrix = newValue
//        }
//    }
    
    init() {
        super.init(name: "F16Camera", cameraType: .F16Cam)
        _projectionMatrix = matrix_float4x4.perspective(degreesFov: 45.0,
                                                        aspectRatio: Renderer.AspectRatio,
                                                        near: 0.1,
                                                        far: 1000)
    }
    
    // Sort of works...
//    override func updateModelMatrix() {
//        super.updateModelMatrix()
//        let cPosition = modelMatrix.columns.3.xyz + positionOffset
//
//        print("[F16Cam] cPosition: \(cPosition)")
//        viewMatrix = matrix_identity_float4x4
////        viewMatrix.translate(direction: -cPosition)
//        viewMatrix.rotate(angle: getRotationX(), axis: X_AXIS)
//        viewMatrix.rotate(angle: getRotationY(), axis: Y_AXIS)
//        viewMatrix.rotate(angle: getRotationZ(), axis: Z_AXIS)
//
//        viewMatrix.translate(direction: -cPosition)
//    }

    override func updateModelMatrix() {
        super.updateModelMatrix()
        
        // Ehhh...
//        let cPosition = modelMatrix.columns.3.xyz + positionOffset
//        viewMatrix = matrix_multiply(viewMatrix, modelMatrix)
//        viewMatrix.translate(direction: -cPosition*2)
        
        // Mmm...
        let cPosition = modelMatrix.columns.3.xyz + positionOffset
        
//        let cRotations = modelMatrix.upperLeft3x3
//        let multMatrix = float4x4(columns: (
//            float4(cRotations.columns.0, 0),
//            float4(cRotations.columns.1, 0),
//            float4(cRotations.columns.2, 0),
//            float4(-cPosition, 1)
//        ))
        
//        let multMatrix = float4x4(columns: (
//            float4(1, 0, 0, 0),
//            float4(0, 1, 0, 0),
//            float4(0, 0, 1, 0),
//            float4(-cPosition, 1)
//        ))
//        viewMatrix = matrix_multiply(viewMatrix, multMatrix)
        
        viewMatrix.translate(direction: -cPosition)
    }
    
    override func doUpdate() {
        if _lastModelMatrix != self.modelMatrix {
            print("F16Camera model matrix changed: \(self.modelMatrix)")
            _lastModelMatrix = self.modelMatrix
        }
        
        if _lastViewMatrix != self.viewMatrix {
            print("F16Camera view matrix changed: \(self.viewMatrix)")
            _lastViewMatrix = self.viewMatrix
        }
        
        if _lastProjectionMatrix != self.projectionMatrix {
            print("F16Camera projection matrix changed: \(self.projectionMatrix)")
            _lastProjectionMatrix = self.projectionMatrix
        }
        
        if Mouse.IsMouseButtonPressed(button: .RIGHT) {
            self.rotate(Mouse.GetDY() * GameTime.DeltaTime * _turnSpeed,
                        Mouse.GetDX() * GameTime.DeltaTime * _turnSpeed,
                        0)
        }
        
        if Mouse.IsMouseButtonPressed(button: .CENTER) {
            self.moveX(-Mouse.GetDX() * GameTime.DeltaTime * _moveSpeed)
            self.moveY(Mouse.GetDY() * GameTime.DeltaTime * _moveSpeed)
        }
        
        self.moveZ(-Mouse.GetDWheel() * 0.1)
    }
}
