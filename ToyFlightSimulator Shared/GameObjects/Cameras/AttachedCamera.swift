//
//  AttachedCamera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/2/22.
//

import simd

class AttachedCamera: Camera {
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
    
    init() {
        super.init(name: "AttachedCamera", cameraType: .Attached)
        _projectionMatrix = matrix_float4x4.perspective(degreesFov: 45.0,
                                                        aspectRatio: Renderer.AspectRatio,
                                                        near: 0.1,
                                                        far: 1000)
    }
    
    // To make a camera follow a node, invert the camera's model matrix:
    override func updateModelMatrix() {
        super.updateModelMatrix()
        viewMatrix = simd_inverse(modelMatrix)
    }
    
    override func doUpdate() {
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
