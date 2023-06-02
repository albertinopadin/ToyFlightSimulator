//
//  AttachedCamera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/2/22.
//

import simd

class AttachedCamera: Camera {
    private var _moveSpeed: Float = 4.0
    private var _turnSpeed: Float = 1.0
    
    public var positionOffset: float3 = float3(0, 0, 0)
    
    init() {
        super.init(name: "AttachedCamera", cameraType: .Attached, aspectRatio: Renderer.AspectRatio)
    }
    
    // To make a camera follow a node, invert the camera's model matrix:
    override func updateModelMatrix() {
        super.updateModelMatrix()
        viewMatrix = modelMatrix.inverse
    }
    
    override func doUpdate() {
        if Mouse.IsMouseButtonPressed(button: .RIGHT) {
            self.rotate3Axis(deltaX: Mouse.GetDY() * GameTime.DeltaTime * _turnSpeed,
                             deltaY: Mouse.GetDX() * GameTime.DeltaTime * _turnSpeed,
                             deltaZ: 0)
        }
        
        if Mouse.IsMouseButtonPressed(button: .CENTER) {
            self.moveX(-Mouse.GetDX() * GameTime.DeltaTime * _moveSpeed)
            self.moveY(Mouse.GetDY() * GameTime.DeltaTime * _moveSpeed)
        }
        
        self.moveZ(-Mouse.GetDWheel() * 0.1)
    }
}
