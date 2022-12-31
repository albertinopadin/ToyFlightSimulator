//
//  F16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/29/22.
//

class F16: GameObject {
    private var _camera: F16Camera?
    private let _camPositionOffset = float3(0, 2, 4)
    
    private var _moveSpeed: Float = 4.0
    private var _turnSpeed: Float = 2.0
    
    private var _lastPosition = float3(0, 0, 0)
    private var _lastRotation = float3(0, 0, 0)
    
    init() {
        super.init(name: "F-16", meshType: .F16, renderPipelineStateType: .OpaqueMaterial)
    }
    
    init(camera: F16Camera) {
        _camera = camera
        _camera?.setPosition(_camPositionOffset)
        _camera?.positionOffset = _camPositionOffset
        _camera?.setRotationX(Float(-15).toRadians)
        super.init(name: "F-16", meshType: .F16, renderPipelineStateType: .OpaqueMaterial)
        addChild(camera)
        
        // Results in gimbal lock and can't rotate on Z axis
//        self.setRotationY(Float(90).toRadians)
//        self.rotateY(Float(90).toRadians)
    }
    
    var xAxis: float3 {
        return normalize(modelMatrix.upperLeft3x3 * float3(1, 0, 0))
    }
    
    var yAxis: float3 {
        return normalize(modelMatrix.upperLeft3x3 * float3(0, 1, 0))
    }
    
    var zAxis: float3 {
        return normalize(modelMatrix.upperLeft3x3 * float3(0, 0, 1))
    }
    
    // TODO: Need to get 'z' axis from existing modelMatrix
    func getFwdVector() -> float3 {
        let fwd = normalize(self.modelMatrix.upperLeft3x3 * float3(0, 0, 1))
        print("fwd vector: \(fwd)")
        return fwd
    }
    
    func moveAlongVector(_ vector: float3, distance: Float) {
        let to = vector * distance
        self.move(to)
    }
    
    var mostRecentTranslation: float3 {
        return getPosition() - _lastPosition
    }
    
    
    // TODO: Understand *why* this works to correctly rotate about axes but not for translation
    override func updateModelMatrix() {
//        modelMatrix = matrix_identity_float4x4
//        modelMatrix.translate(direction: getPosition())
        modelMatrix.translate(direction: getPosition() - _lastPosition)

        modelMatrix.rotate(angle: getRotationX() - _lastRotation.x, axis: X_AXIS)
        modelMatrix.rotate(angle: getRotationY() - _lastRotation.y, axis: Y_AXIS)
        modelMatrix.rotate(angle: getRotationZ() - _lastRotation.z, axis: Z_AXIS)

//        modelMatrix.scale(axis: getScale())

        _lastPosition = getPosition()
        _lastRotation = getRotation()
    }
    
    override func doUpdate() {
        if Keyboard.IsKeyPressed(.leftArrow) {
            self.rotateZ(GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.rightArrow) {
            self.rotateZ(-GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.upArrow) {
            self.rotateX(-GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.downArrow) {
            self.rotateX(GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.q) {
            self.rotateY(GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.e) {
            self.rotateY(-GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.a) {
            self.moveX(-GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.d) {
            self.moveX(GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.w) {
            self.moveZ(-GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.s) {
            self.moveZ(GameTime.DeltaTime * _moveSpeed)
        }
    }
}
