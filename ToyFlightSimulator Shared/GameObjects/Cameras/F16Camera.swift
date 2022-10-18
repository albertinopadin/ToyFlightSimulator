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
    
//    override func updateModelMatrix() {
//        modelMatrix.translate(direction: getPosition() - _lastPosition)
//
//        modelMatrix.rotate(angle: getRotationX() - _lastRotation.x, axis: X_AXIS)
//        modelMatrix.rotate(angle: getRotationY() - _lastRotation.y, axis: Y_AXIS)
//        modelMatrix.rotate(angle: getRotationZ() - _lastRotation.z, axis: Z_AXIS)
//
//        _lastPosition = getPosition()
//        _lastRotation = getRotation()
//    }
    
//    override func updateModelMatrix() {
//        super.updateModelMatrix()
////        viewMatrix = matrix_multiply(viewMatrix, modelMatrix)
//        viewMatrix = matrix_multiply(viewMatrix, parentModelMatrix)
////        viewMatrix = modelMatrix
////        viewMatrix.translate(direction: -getPosition()*2)
//    }
    
    override func updateModelMatrix() {
        super.updateModelMatrix()
//        let cPosition = float3(modelMatrix.columns.0.w,
//                               modelMatrix.columns.1.w,
//                               modelMatrix.columns.2.w)
        
        
        let cPosition = modelMatrix.columns.3.xyz + positionOffset
        
//        print("[F16Cam] modelMatrix col 0: \(modelMatrix.columns.0)")
//        print("[F16Cam] modelMatrix col 1: \(modelMatrix.columns.1)")
//        print("[F16Cam] modelMatrix col 2: \(modelMatrix.columns.2)")
//        print("[F16Cam] modelMatrix col 3: \(modelMatrix.columns.3)")
        
        print("[F16Cam] cPosition: \(cPosition)")
        viewMatrix = matrix_identity_float4x4
        viewMatrix.translate(direction: -cPosition)
    }
    
//    override func updateModelMatrix() {
//        viewMatrix.translate(direction: getPosition() - _lastPosition)
//
//        viewMatrix.rotate(angle: getRotationX() - _lastRotation.x, axis: X_AXIS)
//        viewMatrix.rotate(angle: getRotationY() - _lastRotation.y, axis: Y_AXIS)
//        viewMatrix.rotate(angle: getRotationZ() - _lastRotation.z, axis: Z_AXIS)
//
////        modelMatrix.scale(axis: getScale())
//
//        _lastPosition = getPosition()
//        _lastRotation = getRotation()
//    }
    
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
        
        
//        if Keyboard.IsKeyPressed(.leftArrow) || Keyboard.IsKeyPressed(.a) {
//            self.moveX(-GameTime.DeltaTime * _moveSpeed)
//        }
//
//        if Keyboard.IsKeyPressed(.rightArrow) || Keyboard.IsKeyPressed(.d) {
//            self.moveX(GameTime.DeltaTime * _moveSpeed)
//        }
//
//        if Keyboard.IsKeyPressed(.upArrow) {
//            self.moveY(GameTime.DeltaTime * _moveSpeed)
//        }
//
//        if Keyboard.IsKeyPressed(.downArrow) {
//            self.moveY(-GameTime.DeltaTime * _moveSpeed)
//        }
//
//        if Keyboard.IsKeyPressed(.w) {
//            self.moveZ(-GameTime.DeltaTime * _moveSpeed)
//        }
//
//        if Keyboard.IsKeyPressed(.s) {
//            self.moveZ(GameTime.DeltaTime * _moveSpeed)
//        }
        
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
