//
//  DebugCamera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import simd

class DebugCamera: Camera {
    private var _moveSpeed: Float = 25.0
    private var _turnSpeed: Float = 0.4
    
    init() {
        super.init(name: "Debug", cameraType: .Debug, aspectRatio: Renderer.AspectRatio)
    }
    
    override func doUpdate() {
        if Keyboard.IsKeyPressed(.leftArrow) || Keyboard.IsKeyPressed(.a) {
            self.moveAlongVector(getRightVector(), distance: Float(GameTime.DeltaTime) * _moveSpeed)
        }

        if Keyboard.IsKeyPressed(.rightArrow) || Keyboard.IsKeyPressed(.d) {
            self.moveAlongVector(getRightVector(), distance: -Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.upArrow) {
            self.moveAlongVector(getUpVector(), distance: Float(GameTime.DeltaTime) * _moveSpeed)
        }

        if Keyboard.IsKeyPressed(.downArrow) {
            self.moveAlongVector(getUpVector(), distance: -Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.a) {
            self.moveAlongVector(getRightVector(), distance: -Float(GameTime.DeltaTime) * _moveSpeed)
        }

        if Keyboard.IsKeyPressed(.d) {
            self.moveAlongVector(getRightVector(), distance: Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        self.rotate(deltaAngle: -InputManager.ContinuousCommand(.Pitch) * Float(GameTime.DeltaTime) * _turnSpeed * 10.0,
                    axis: getRightVector())
        self.rotate(deltaAngle: -InputManager.ContinuousCommand(.Roll) * Float(GameTime.DeltaTime) * _turnSpeed * 15.0,
                    axis: getUpVector())
        
        self.moveAlongVector(getRightVector(),
                             distance: InputManager.ContinuousCommand(.MoveSide) * Float(GameTime.DeltaTime) * _moveSpeed)
        self.moveAlongVector(getFwdVector(),
                             distance: InputManager.ContinuousCommand(.MoveFwd) * Float(GameTime.DeltaTime) * _moveSpeed)
        
        
        if Mouse.IsMouseButtonPressed(button: .RIGHT) {
            self.rotate(deltaAngle: Mouse.GetDY() * Float(GameTime.DeltaTime) * _turnSpeed, axis: getRightVector())
            self.rotate(deltaAngle: Mouse.GetDX() * Float(GameTime.DeltaTime) * _turnSpeed, axis: getUpVector())
        }
        
        if Mouse.IsMouseButtonPressed(button: .CENTER) {
            self.moveAlongVector(getRightVector(), distance: -Mouse.GetDX() * Float(GameTime.DeltaTime) * _moveSpeed)
            self.moveAlongVector(getUpVector(), distance: Mouse.GetDY() * Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        self.moveZ(-Mouse.GetDWheel() * 0.1)
    }
    
    override func updateModelMatrix() {
        super.updateModelMatrix()
        viewMatrix = modelMatrix.inverse
    }
}
