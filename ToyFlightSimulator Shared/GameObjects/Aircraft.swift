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
    
    private var _X: float3!
    private var _Y: float3!
    private var _Z: float3!
    
    private var _lastFwdVector: float3 = float3(0, 0, 0)
    
    private var _moveSpeed: Float = 25.0
    private var _turnSpeed: Float = 4.0
    
    override init(name: String, meshType: MeshType, renderPipelineStateType: RenderPipelineStateType = .OpaqueMaterial) {
        super.init(name: name, meshType: meshType, renderPipelineStateType: renderPipelineStateType)
//        initAxes()
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
//        _camera?.setRotationX(Float(-15).toRadians)
        _camera?.rotateX(Float(-15).toRadians)
        _camera?.setScale(1/scale)  // Set the inverse of parent scale to preserve view matrix
        super.init(name: name, meshType: meshType, renderPipelineStateType: renderPipelineStateType)
        print("[Aircraft init] name: \(name), scale: \(scale)")
//        modelMatrix.scale(axis: float3(repeating: scale))  // Scale model matrix only once, on init
        addChild(camera)
        
        // Results in gimbal lock and can't rotate on Z axis
//        self.setRotationY(Float(90).toRadians)
//        self.rotateY(Float(90).toRadians)
        
//        initAxes()
    }
    
    // TODO: Testing:
//    func initAxes() {
//        _X = getRightVector()
//        _Y = getUpVector()
//        _Z = getFwdVector()
//    }
    
//    var xAxis: float3 {
//        return normalize(modelMatrix.upperLeft3x3 * X_AXIS)
//    }
//
//    var yAxis: float3 {
//        return normalize(modelMatrix.upperLeft3x3 * Y_AXIS)
//    }
//
//    var zAxis: float3 {
//        return normalize(modelMatrix.upperLeft3x3 * Z_AXIS)
//    }
    
//    func getFwdVector() -> float3 {
//        let forward = modelMatrix.columns.2
//        return normalize(float3(-forward.x, -forward.y, -forward.z))
//    }
//    
//    func getUpVector() -> float3 {
//        let up = modelMatrix.columns.1
//        return normalize(float3(up.x, up.y, up.z))
//    }
//
//    func getRightVector() -> float3 {
//        let right = modelMatrix.columns.0
//        return normalize(float3(right.x, right.y, right.z))
//    }

    func moveAlongVector(_ vector: float3, distance: Float) {
        let to = vector * distance
        self.move(to)
    }
    
    
    func getFwdVectorTranslatedToOrigin() -> float3 {
        let originMM = modelMatrix * Transform.translationMatrix(-self.getPosition())
        let forward = originMM.columns.2
        return normalize(float3(-forward.x, -forward.y, -forward.z))
    }

    func getUpVectorTranslatedToOrigin() -> float3 {
        let originMM = modelMatrix * Transform.translationMatrix(-self.getPosition())
        let up = originMM.columns.1
        return normalize(float3(up.x, up.y, up.z))
    }

    func getRightVectorTranslatedToOrigin() -> float3 {
        let originMM = modelMatrix * Transform.translationMatrix(-self.getPosition())
        let right = originMM.columns.0
        return normalize(float3(right.x, right.y, right.z))
    }
    
    
//    func rotateOnAxis(_ axis: float3, rotation: Float) {
//        // TODO
//        // I think in order to do this while keeping track of the rotations per axis,
//        // need to figure out a way to deconstruct a rotation around an arbitrary axis
//        // into rotations in the X, Y, and Z axes.
//    }
    
    // Adapted from ChatGPT-4:
    func decomposeToEulers(_ rotationMatrix: matrix_float4x4) -> float3 {
        let _v = rotationMatrix.columns.0.x * rotationMatrix.columns.0.x + rotationMatrix.columns.1.x * rotationMatrix.columns.1.x
        let sy = sqrt(_v)
        let isSingular = sy < 1e-6
        var x, y, z: Float
        if !isSingular {
            x = atan2(rotationMatrix.columns.2.y, rotationMatrix.columns.2.z)
            y = atan2(-rotationMatrix.columns.2.x, sy)
            z = atan2(rotationMatrix.columns.1.x, rotationMatrix.columns.0.x)
        } else {
            x = atan2(-rotationMatrix.columns.1.z, rotationMatrix.columns.1.y)
            y = atan2(-rotationMatrix.columns.2.x, sy)
            z = 0
        }
//        return float3(x: x, y: y, z: z)  // Right-handed coordinate system
//        return float3(x: -x, y: -y, z: z)  // Left-handed coordinate system
        return float3(x: -x, y: -y, z: z)
    }
    
    func getRotationMatrix(angle: Float, axis: float3) -> simd_float4x4 {
        let quaternion = simd_quatf(angle: angle, axis: axis)
        return simd_float4x4(quaternion)
    }
    
    // From Google Bard:
//    func decomposeToEulers(_ matrix: matrix_float4x4) -> float3 {
//        // Get the rotation angle from the matrix.
//        let angle = atan2(matrix[2, 1], matrix[2, 2])
//
//        // Create a vector representing the rotation axis.
//        let axis = normalize(float3(matrix[0, 2], matrix[1, 2], matrix[2, 2]))
//
//        // Return a SIMD3<Float> representing the decomposed rotations around the X, Y, and Z axes.
//        return float3(angle * axis[0], angle * axis[1], angle * axis[2])
//    }
    
    override func doUpdate() {
//        super.doUpdate()
        
        let deltaMove = GameTime.DeltaTime * _moveSpeed
        let deltaTurn = GameTime.DeltaTime * _turnSpeed
        
//        let fwd = getFwdVector()
//        if _lastFwdVector != fwd {
//            print("Fwd vector changed; last: \(_lastFwdVector), current: \(fwd)")
//            _lastFwdVector = fwd
//        }
        
//        if Keyboard.IsKeyPressed(.p) {
//            print("Pressed P")
//        }
        
//        let currentRotation = decomposeToEulers(modelMatrix)
//        if currentRotation != self.getRotation() {
//            print("ROTATIONS NOT EQUAL")
//            print("Current: \(currentRotation)")
//            print("self: \(self.getRotation())")
//        }
        
        if Keyboard.IsKeyPressed(.leftArrow) {
//            self.rotateZ(GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getFwdVector(), rotation: GameTime.DeltaTime * _turnSpeed)
            
//            let rotation = -GameTime.DeltaTime * _turnSpeed
//            self.rotateZ(rotation)
//            rotateOnAxis(getFwdVector(), degrees: rotation)
            
//            let axisRotation = matrix_float4x4(rotateAbout: fwd, byAngle: -GameTime.DeltaTime * _turnSpeed)
//            let axisRotation = matrix_float4x4(rotateAbout: _Z, byAngle: -GameTime.DeltaTime * _turnSpeed)
            
//            let axisRotation = Transform.rotationMatrix(radians: deltaTurn, axis: getFwdVectorTranslatedToOrigin())
//            let axisRotation = getRotationMatrix(angle: deltaTurn, axis: getFwdVector())
//            var axisRotation = getRotationMatrix(angle: deltaTurn, axis: getFwdVectorTranslatedToOrigin())
//            axisRotation = axisRotation * Transform.translationMatrix(self.getPosition())
//            self.setRotation(self.getRotation() + decomposeToEulers(axisRotation))
//            modelMatrix = matrix_multiply(axisRotation, modelMatrix)
//            self.rotate(deltaAngle: deltaTurn, axis: getFwdVector())
            self.rotateZ(-deltaTurn)
            
//            self.modelMatrix.rotate(angle: -deltaTurn, axis: getFwdVector())
        }
        
        if Keyboard.IsKeyPressed(.rightArrow) {
//            self.rotateZ(-GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getFwdVector(), rotation: -GameTime.DeltaTime * _turnSpeed)
            
//            let rotation = GameTime.DeltaTime * _turnSpeed
//            self.rotateZ(rotation)
//            rotateOnAxis(getFwdVector(), degrees: rotation)
            
//            let axisRotation = matrix_float4x4(rotateAbout: fwd, byAngle: GameTime.DeltaTime * _turnSpeed)
//            let axisRotation = matrix_float4x4(rotateAbout: _Z, byAngle: GameTime.DeltaTime * _turnSpeed)
            
//            let axisRotation = Transform.rotationMatrix(radians: -deltaTurn, axis: getFwdVectorTranslatedToOrigin())
//            var axisRotation = getRotationMatrix(angle: -deltaTurn, axis: getFwdVectorTranslatedToOrigin())
//            axisRotation = axisRotation * Transform.translationMatrix(self.getPosition())
//            self.setRotation(self.getRotation() + decomposeToEulers(axisRotation))
//            modelMatrix = matrix_multiply(axisRotation, modelMatrix)
//            self.rotate(deltaAngle: -deltaTurn, axis: getFwdVector())
            self.rotateZ(deltaTurn)
            
//            self.modelMatrix.rotate(angle: deltaTurn, axis: getFwdVector())
        }
        
        if Keyboard.IsKeyPressed(.upArrow) {
            // TODO: Rotate along RIGHT vector
//            self.rotateX(-GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getRightVector(), rotation: -GameTime.DeltaTime * _turnSpeed)
            
//            let rotation = -GameTime.DeltaTime * _turnSpeed
//            self.rotateX(rotation)
//            rotateOnAxis(getRightVector(), degrees: rotation)
            
//            let axisRotation = matrix_float4x4(rotateAbout: getRightVector(), byAngle: -GameTime.DeltaTime * _turnSpeed)
//            let axisRotation = matrix_float4x4(rotateAbout: _X, byAngle: -GameTime.DeltaTime * _turnSpeed)
            
//            let axisRotation = Transform.rotationMatrix(radians: -deltaTurn, axis: getRightVectorTranslatedToOrigin())
//            var axisRotation = getRotationMatrix(angle: -deltaTurn, axis: getRightVectorTranslatedToOrigin())
//            axisRotation = axisRotation * Transform.translationMatrix(self.getPosition())
//            self.setRotation(self.getRotation() + decomposeToEulers(axisRotation))
//            modelMatrix = matrix_multiply(axisRotation, modelMatrix)
//            self.rotate(deltaAngle: -deltaTurn, axis: getRightVector())
            self.rotateX(-deltaTurn)
//            self.modelMatrix.rotate(angle: -deltaTurn, axis: getRightVector())
        }
        
        if Keyboard.IsKeyPressed(.downArrow) {
            // TODO: Rotate along RIGHT vector
//            self.rotateX(GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getRightVector(), rotation: GameTime.DeltaTime * _turnSpeed)
            
//            let rotation = GameTime.DeltaTime * _turnSpeed
//            self.rotateX(rotation)
//            rotateOnAxis(getRightVector(), degrees: rotation)
            
//            let axisRotation = matrix_float4x4(rotateAbout: getRightVector(), byAngle: GameTime.DeltaTime * _turnSpeed)
//            let axisRotation = matrix_float4x4(rotateAbout: _X, byAngle: GameTime.DeltaTime * _turnSpeed)
            
//            let axisRotation = Transform.rotationMatrix(radians: deltaTurn, axis: getRightVectorTranslatedToOrigin())
//            var axisRotation = getRotationMatrix(angle: deltaTurn, axis: getRightVectorTranslatedToOrigin())
//            axisRotation = axisRotation * Transform.translationMatrix(self.getPosition())
//            self.setRotation(self.getRotation() + decomposeToEulers(axisRotation))
//            modelMatrix = matrix_multiply(axisRotation, modelMatrix)
//            self.rotate(deltaAngle: deltaTurn, axis: getRightVector())
            self.rotateX(deltaTurn)
//            self.modelMatrix.rotate(angle: deltaTurn, axis: getRightVector())
        }
        
        if Keyboard.IsKeyPressed(.q) {
            // TODO: Rotate along UP vector
//            self.rotateY(GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getUpVector(), rotation: GameTime.DeltaTime * _turnSpeed)
            
//            let rotation = GameTime.DeltaTime * _turnSpeed
//            self.rotateY(rotation)
//            rotateOnAxis(getUpVector(), degrees: rotation)
            
            
//            let axisRotation = matrix_float4x4(rotateAbout: getUpVector(), byAngle: GameTime.DeltaTime * _turnSpeed)
//            let axisRotation = matrix_float4x4(rotateAbout: _Y, byAngle: GameTime.DeltaTime * _turnSpeed)
            
//            let axisRotation = Transform.rotationMatrix(radians: deltaTurn, axis: getUpVectorTranslatedToOrigin())
//            var axisRotation = getRotationMatrix(angle: deltaTurn, axis: getUpVectorTranslatedToOrigin())
//            axisRotation = axisRotation * Transform.translationMatrix(self.getPosition())
//            self.setRotation(self.getRotation() + decomposeToEulers(axisRotation))
//            modelMatrix = matrix_multiply(axisRotation, modelMatrix)
//            self.rotate(deltaAngle: deltaTurn, axis: getUpVector())
            self.rotateY(deltaTurn)
//            self.modelMatrix.rotate(angle: deltaTurn, axis: getUpVector())
        }
        
        if Keyboard.IsKeyPressed(.e) {
            // TODO: Rotate along UP vector
//            self.rotateY(-GameTime.DeltaTime * _turnSpeed)
//            rotateOnAxis(getUpVector(), rotation: -GameTime.DeltaTime * _turnSpeed)
            
//            let rotation = -GameTime.DeltaTime * _turnSpeed
//            self.rotateY(rotation)
//            rotateOnAxis(getUpVector(), degrees: rotation)
            
//            let axisRotation = matrix_float4x4(rotateAbout: getUpVector(), byAngle: -GameTime.DeltaTime * _turnSpeed)
//            let axisRotation = matrix_float4x4(rotateAbout: _Y, byAngle: -GameTime.DeltaTime * _turnSpeed)
            
//            let axisRotation = Transform.rotationMatrix(radians: -deltaTurn, axis: getUpVectorTranslatedToOrigin())
//            var axisRotation = getRotationMatrix(angle: -deltaTurn, axis: getUpVectorTranslatedToOrigin())
//            axisRotation = axisRotation * Transform.translationMatrix(self.getPosition())
//            self.setRotation(self.getRotation() + decomposeToEulers(axisRotation))
//            modelMatrix = matrix_multiply(axisRotation, modelMatrix)
//            self.rotate(deltaAngle: -deltaTurn, axis: getUpVector())
            self.rotateY(-deltaTurn)
//            self.modelMatrix.rotate(angle: -deltaTurn, axis: getUpVector())
        }
        
        if Keyboard.IsKeyPressed(.a) {
//            self.moveX(-GameTime.DeltaTime * _moveSpeed)
//            moveAlongVector(getRightVector(), distance: -GameTime.DeltaTime * _moveSpeed)
            moveAlongVector(getRightVector(), distance: -deltaMove)
        }
        
        if Keyboard.IsKeyPressed(.d) {
//            self.moveX(GameTime.DeltaTime * _moveSpeed)
//            moveAlongVector(getRightVector(), distance: GameTime.DeltaTime * _moveSpeed)
            moveAlongVector(getRightVector(), distance: deltaMove)
        }
        
        if Keyboard.IsKeyPressed(.w) {
//            self.moveZ(-GameTime.DeltaTime * _moveSpeed)
//            moveAlongVector(getFwdVector(), distance: GameTime.DeltaTime * _moveSpeed)
//            moveAlongVector(fwd, distance: GameTime.DeltaTime * _moveSpeed)
            moveAlongVector(getFwdVector(), distance: deltaMove)
        }
        
        if Keyboard.IsKeyPressed(.s) {
//            self.moveZ(GameTime.DeltaTime * _moveSpeed)
//            moveAlongVector(getFwdVector(), distance: -GameTime.DeltaTime * _moveSpeed)
//            moveAlongVector(fwd, distance: -GameTime.DeltaTime * _moveSpeed)
            moveAlongVector(getFwdVector(), distance: -deltaMove)
        }
    }
}

