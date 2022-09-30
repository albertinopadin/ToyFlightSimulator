//
//  DebugCamera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import simd

class DebugCamera: Camera {
    private var _projectionMatrix = matrix_identity_float4x4
    override var projectionMatrix: matrix_float4x4 {
        return _projectionMatrix
    }
    
    private var _moveSpeed: Float = 4.0
    private var _turnSpeed: Float = 1.0
    
    init() {
        super.init(name: "Debug", cameraType: .Debug)
        print("Renderer.AspectRatio: \(Renderer.AspectRatio)")
        _projectionMatrix = matrix_float4x4.perspective(degreesFov: 45.0,
                                                        aspectRatio: Renderer.AspectRatio,
                                                        near: 0.1,
                                                        far: 1000)
    }
    
    override func doUpdate() {
//        _projectionMatrix = matrix_float4x4.perspective(degreesFov: 45.0,
//                                                        aspectRatio: Renderer.AspectRatio,
//                                                        near: 0.1,
//                                                        far: 1000)
        
        if (Keyboard.IsKeyPressed(.leftArrow)) {
            self.moveX(-GameTime.DeltaTime * _moveSpeed)
        }
        
        if (Keyboard.IsKeyPressed(.rightArrow)) {
            self.moveX(GameTime.DeltaTime * _moveSpeed)
        }
        
        if (Keyboard.IsKeyPressed(.upArrow)) {
            self.moveY(GameTime.DeltaTime * _moveSpeed)
        }
        
        if (Keyboard.IsKeyPressed(.downArrow)) {
            self.moveY(-GameTime.DeltaTime * _moveSpeed)
        }
        
        if (Mouse.IsMouseButtonPressed(button: .RIGHT)) {
            self.rotate(Mouse.GetDY() * GameTime.DeltaTime * _turnSpeed,
                        Mouse.GetDX() * GameTime.DeltaTime * _turnSpeed,
                        0)
        }
        
        if (Mouse.IsMouseButtonPressed(button: .CENTER)) {
            self.moveX(-Mouse.GetDX() * GameTime.DeltaTime * _moveSpeed)
            self.moveY(Mouse.GetDY() * GameTime.DeltaTime * _moveSpeed)
        }
        
        self.moveZ(-Mouse.GetDWheel() * 0.1)
    }
}
