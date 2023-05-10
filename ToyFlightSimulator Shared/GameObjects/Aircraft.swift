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
        print("[Aircraft init] name: \(name), scale: \(scale)")
//        modelMatrix.scale(axis: float3(repeating: scale))  // Scale model matrix only once, on init
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
        let fwd = -normalize(modelMatrix.upperLeft3x3 * float3(0, 0, 1))
        print("fwd vector: \(fwd)")
        return fwd
    }
    
    func getUpVector() -> float3 {
        return normalize(modelMatrix.upperLeft3x3 * float3(0, 1, 0))
    }

    func getRightVector() -> float3 {
        return normalize(modelMatrix.upperLeft3x3 * float3(1, 0, 0))
    }
    
    func moveAlongVector(_ vector: float3, distance: Float) {
        let to = vector * distance
        self.move(to)
    }
    
    func rotateOnAxis(_ axis: float3, rotation: Float) {
        // TODO
        // I think in order to do this while keeping track of the rotations per axis,
        // need to figure out a way to deconstruct a rotation around an arbitrary axis
        // into rotations in the X, Y, and Z axes.
    }
    
    override func doUpdate() {
        if Keyboard.IsKeyPressed(.leftArrow) {
            self.rotateZ(GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getFwdVector(), rotation: GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.rightArrow) {
            self.rotateZ(-GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getFwdVector(), rotation: -GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.upArrow) {
            // TODO: Rotate along RIGHT vector
            self.rotateX(-GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getRightVector(), rotation: -GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.downArrow) {
            // TODO: Rotate along RIGHT vector
            self.rotateX(GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getRightVector(), rotation: GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.q) {
            // TODO: Rotate along UP vector
            self.rotateY(GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getUpVector(), rotation: GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.e) {
            // TODO: Rotate along UP vector
            self.rotateY(-GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getUpVector(), rotation: -GameTime.DeltaTime * _turnSpeed)
        }
        
        if Keyboard.IsKeyPressed(.a) {
            moveAlongVector(getRightVector(), distance: -GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.d) {
            moveAlongVector(getRightVector(), distance: GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.w) {
            moveAlongVector(getFwdVector(), distance: GameTime.DeltaTime * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.s) {
            moveAlongVector(getFwdVector(), distance: -GameTime.DeltaTime * _moveSpeed)
        }
    }
}

