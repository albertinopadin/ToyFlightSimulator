//
//  DebugCamera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import simd

class DebugCamera: Camera {
    private var _moveSpeed: Float = 10.0
    private var _turnSpeed: Float = 0.1
    
    init() {
        super.init(name: "Debug", cameraType: .Debug, aspectRatio: Renderer.AspectRatio)
    }
    
    override func doUpdate() {
        if Keyboard.IsKeyPressed(.leftArrow) || Keyboard.IsKeyPressed(.a) {
            self.moveX(-GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.rightArrow) || Keyboard.IsKeyPressed(.d) {
            self.moveX(GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.upArrow) {
            self.moveY(GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.downArrow) {
            self.moveY(-GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.w) {
            self.moveZ(-GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.s) {
            self.moveZ(GameTime.DeltaTime * _moveSpeed)
        }
        
        if Mouse.IsMouseButtonPressed(button: .RIGHT) {
            self.rotate3Axis(deltaX: -Mouse.GetDY() * GameTime.DeltaTime * _turnSpeed,
                             deltaY: -Mouse.GetDX() * GameTime.DeltaTime * _turnSpeed,
                             deltaZ: 0)
        }
        
        if Mouse.IsMouseButtonPressed(button: .CENTER) {
            self.moveX(-Mouse.GetDX() * GameTime.DeltaTime * _moveSpeed)
            self.moveY(Mouse.GetDY() * GameTime.DeltaTime * _moveSpeed)
        }
        
        self.moveZ(-Mouse.GetDWheel() * 0.1)
    }
}
