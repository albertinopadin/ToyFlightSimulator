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
    private static let NAME: String = "AttachedCamera"
    
    public var positionOffset: float3 = [0, 0, 0]
    
    init() {
        super.init(name: AttachedCamera.NAME, cameraType: .Attached, aspectRatio: Renderer.AspectRatio)
        self.ignoreParentScale = true
    }
    
    init(fieldOfView: Float = 45.0, near: Float = 0.1, far: Float = 1000) {
        super.init(name: AttachedCamera.NAME,
                   cameraType: .Attached,
                   aspectRatio: Renderer.AspectRatio,
                   fieldOfView: fieldOfView,
                   near: near,
                   far: far)
    }
    
    // To make a camera follow a node, invert the camera's model matrix:
    override func updateModelMatrix() {
        super.updateModelMatrix()
        viewMatrix = modelMatrix.inverse
    }
    
    override func doUpdate() {
        if Mouse.IsMouseButtonPressed(button: .RIGHT) {
            self.rotate3Axis(deltaX: Mouse.GetDY() * Float(GameTime.DeltaTime) * _turnSpeed,
                             deltaY: Mouse.GetDX() * Float(GameTime.DeltaTime) * _turnSpeed,
                             deltaZ: 0)
        }
        
        if Mouse.IsMouseButtonPressed(button: .CENTER) {
            self.moveX(-Mouse.GetDX() * Float(GameTime.DeltaTime) * _moveSpeed)
            self.moveY(Mouse.GetDY() * Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        self.moveZ(-Mouse.GetDWheel() * 0.1)
    }
}
