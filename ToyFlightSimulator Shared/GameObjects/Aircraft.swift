//
//  Aircraft.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/11/23.
//

import MetalKit

class Aircraft: GameObject {
    private var _camera: AttachedCamera?
    private static let _defaultCameraPositionOffset = float3(0, 2, 4)
    
    private var _moveSpeed: Float = 25.0
    private var _turnSpeed: Float = 4.0
    
    private var _lastPosition = float3(0, 0, 0)
    private var _lastRotation = float3(0, 0, 0)
    
    override init(name: String, meshType: MeshType, renderPipelineStateType: RenderPipelineStateType = .OpaqueMaterial) {
        super.init(name: name, meshType: meshType, renderPipelineStateType: renderPipelineStateType)
    }
    
    init(name: String,
         meshType: MeshType,
         renderPipelineStateType: RenderPipelineStateType,
         camera: AttachedCamera,
         cameraOffset: float3 = _defaultCameraPositionOffset,
         scale: Float = 1.0) {
        _camera = camera
        _camera?.setPosition(cameraOffset)
        _camera?.positionOffset = cameraOffset
        _camera?.setRotationX(Float(-15).toRadians)
        _camera?.setScale(1/scale)  // Set the inverse of parent scale to preserve view matrix
        super.init(name: name, meshType: meshType, renderPipelineStateType: renderPipelineStateType)
        modelMatrix.scale(axis: float3(repeating: scale))  // Scale model matrix only once, on init
        addChild(camera)
        
        // Results in gimbal lock and can't rotate on Z axis
//        self.setRotationY(Float(90).toRadians)
//        self.rotateY(Float(90).toRadians)
    }
    
    var xAxis: float3 {
        return normalize(modelMatrix.upperLeft3x3 * X_AXIS)
    }
    
    var yAxis: float3 {
        return normalize(modelMatrix.upperLeft3x3 * Y_AXIS)
    }
    
    var zAxis: float3 {
        return normalize(modelMatrix.upperLeft3x3 * Z_AXIS)
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

