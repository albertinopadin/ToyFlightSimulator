//
//  F16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/29/22.
//

class F16: GameObject {
    private var _camera: DebugCamera?
    private let _camPositionOffset = float3(0, 2, 4)
    
    private var _moveSpeed: Float = 4.0
    private var _turnSpeed: Float = 1.0
    
    
//    let invertYLook = false
//    let eyeSpeed: Float = 6
//    let radiansPerLookPoint: Float = 0.017
//    let maximumPitchRadians = (Float.pi / 2) * 0.99
//
//    let pointOfView: Node
//
//    var eye = float3(0, 0, 0)
//    private var look = float3(0, 0, -1)
//    private var up = float3(0, 1, 0)
    
    init() {
        super.init(name: "F-16", meshType: .F16)
    }
    
    init(camera: DebugCamera) {
        _camera = camera
        _camera?.setPosition(_camPositionOffset)
        _camera?.setRotationX(Float(25).toRadians)
        super.init(name: "F-16", meshType: .F16)
        self.setRotationY(Float(90).toRadians)
    }
    
    func getFwdVector(pointingDelta: float2, moveDelta: float2) -> float3 {
//        let right = normalize(cross(look, up))
//        var forward = look
//
//        let deltaX = moveDelta[0], deltaZ = moveDelta[1]
//        let movementDir = SIMD3<Float>(deltaX * right.x + deltaZ * forward.x,
//                                       deltaX * right.y + deltaZ * forward.y,
//                                       deltaX * right.z + deltaZ * forward.z)
//        eye += movementDir * eyeSpeed * timestep
//
//        let yaw = -lookDelta.x * radiansPerLookPoint
//        let yawRotation = simd_quaternion(yaw, up)
//
//        let angleToUp: Float = acos(dot(look, up))
//        let angleToDown: Float = acos(dot(look, -up))
//        let maxPitch = max(0.0, angleToUp - (.pi / 2 - maximumPitchRadians))
//        let minPitch = max(0.0, angleToDown - (.pi / 2 - maximumPitchRadians))
//        var pitch = lookDelta.y * radiansPerLookPoint
//        if (invertYLook) { pitch *= -1.0 }
//        pitch = max(-minPitch, min(pitch, maxPitch))
//        let pitchRotation = simd_quaternion(pitch, right)
//
//        let rotation = pitchRotation * yawRotation
//        forward = rotation.rotate(forward)
//
//        look = normalize(forward)
//
//        pointOfView.transform = float4x4(lookAt: eye + look,
//                                         from: eye,
//                                         up: up)
        return float3(0, 0, 0)
    }
    
    func moveAlongVector(_ vector: float3, distance: Float) {
        
    }
    
    // TODO: Figure out how to move 'forwards' in direction jet is pointed.
    override func doUpdate() {
        if let _camera {
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
            
            if (Mouse.IsMouseButtonPressed(button: .LEFT)) {
                self.rotateX(-Mouse.GetDY() * GameTime.DeltaTime)
                self.rotateY(-Mouse.GetDX() * GameTime.DeltaTime)
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
            
            _camera.setPosition(self.getPosition() + _camPositionOffset)
//            _camera.setRotation(self.getRotation())  <- not rotating correctly
        }
    }
}
