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
            self.moveAlongVector(getRightVector(), distance: GameTime.DeltaTime * _moveSpeed)
        }

        if Keyboard.IsKeyPressed(.rightArrow) || Keyboard.IsKeyPressed(.d) {
            self.moveAlongVector(getRightVector(), distance: -GameTime.DeltaTime * _moveSpeed)
        }
        
//        self.moveAlongVector(getRightVector(),
//                             distance: InputManager.ContinuousCommand(.MoveSide) * GameTime.DeltaTime * _moveSpeed)
        
        if Keyboard.IsKeyPressed(.upArrow) {
            self.moveAlongVector(getUpVector(), distance: GameTime.DeltaTime * _moveSpeed)
        }

        if Keyboard.IsKeyPressed(.downArrow) {
            self.moveAlongVector(getUpVector(), distance: -GameTime.DeltaTime * _moveSpeed)
        }
        
//        self.moveAlongVector(getUpVector(), distance: InputManager.ContinuousCommand(.Pitch) * GameTime.DeltaTime * _moveSpeed)
        
        if Keyboard.IsKeyPressed(.w) {
            self.moveAlongVector(getFwdVector(), distance: -GameTime.DeltaTime * _moveSpeed)
        }

        if Keyboard.IsKeyPressed(.s) {
            self.moveAlongVector(getFwdVector(), distance: GameTime.DeltaTime * _moveSpeed)
        }
        
//        self.moveAlongVector(getFwdVector(), distance: InputManager.ContinuousCommand(.MoveFwd) * GameTime.DeltaTime * _moveSpeed)
        
        self.rotateY(-InputManager.ContinuousCommand(.Yaw) * GameTime.DeltaTime * _turnSpeed * 8.0)
//        self.rotate(deltaAngle: -InputManager.ContinuousCommand(.Yaw) * GameTime.DeltaTime * _turnSpeed * 8.0,
//                    axis: getUpVector())
        
//        let deltaMove = GameTime.DeltaTime * _moveSpeed
//        let deltaTurn = GameTime.DeltaTime * _turnSpeed * 8.0
//
//        self.rotateZ(deltaTurn * InputManager.ContinuousCommand(.Roll))
//
//        self.rotateX(deltaTurn * InputManager.ContinuousCommand(.Pitch))
//
//        self.rotateY(deltaTurn * InputManager.ContinuousCommand(.Yaw))
//
//        moveAlongVector(getFwdVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveFwd))
//
//        moveAlongVector(getRightVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
        
        
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
