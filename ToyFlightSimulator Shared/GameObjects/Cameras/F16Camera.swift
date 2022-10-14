//
//  F16Camera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/2/22.
//

import simd

class F16Camera: Camera {
//    private var _lastPosition = float3(0, 0, 0)
//    private var _lastRotation = float3(0, 0, 0)
    
    private var _moveSpeed: Float = 4.0
    private var _turnSpeed: Float = 1.0
    
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
    
    override func doUpdate() {
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
