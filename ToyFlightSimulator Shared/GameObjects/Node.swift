//
//  Node.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class Node: ClickSelectable {
    var hasFocus: Bool = false
    
    private var _name: String = "Node"
    private var _id: String!
    
    private var _position: float3 = [0, 0, 0]
    private var _scale: float3 = [1, 1, 1]
    
    var parentModelMatrix = matrix_identity_float4x4
    
    private var _modelMatrix = matrix_identity_float4x4
    private var _rotationMatrix = matrix_identity_float4x4
    
    var parent: Node? = nil
    var children: [Node] = []
    
    var modelMatrix: matrix_float4x4 {
        set {
            _modelMatrix = newValue
        }
        
        get {
            return matrix_multiply(parentModelMatrix, _modelMatrix)
        }
    }
    
    var rotationMatrix: matrix_float4x4 {
        get {
            return _rotationMatrix
        }
        
        set {
            _rotationMatrix = newValue
        }
    }
    
    init(name: String) {
        self._name = name
        self._id = UUID().uuidString
    }
    
    func addChild(_ child: Node) {
        children.append(child)
        child.parent = self
    }
    
    func removeChild(_ child: Node) {
        child.parent = nil
        children.removeAll(where: { $0.getID() == child.getID() })
    }
    
    func removeAllChildren() {
        children.forEach { $0.parent = nil }
        children.removeAll()
    }
    
    func updateModelMatrix() {
        _modelMatrix = Transform.translationMatrix(_position) * _rotationMatrix * Transform.scaleMatrix(_scale)
    }
    
    // Override these when needed:
    func afterTranslation() { }
    func afterRotation() { }
    func afterScale() { }
    
    /// Override this function instead of the update function
    func doUpdate() { }
    
    func update() {
        doUpdate()
        
        for child in children {
            child.parentModelMatrix = self.modelMatrix
            child.update()
        }
        
        // TODO: A more efficient approach might be to get the click location in the scene and
        //       then figure out what object has focus, instead of every node checking itself
        // WEIRD: This only fires for the Attached Camera node...
//        InputManager.handleMouseClickDebounced(command: .ClickSelect) {
//            print("[Node update] Node name: \(getName()), position: \(getPosition())")
//            if clickedOnNode() {
//                let childHasFocus = children.reduce(false) { $0 || $1.hasFocus }
//                if !childHasFocus {
//                    hasFocus = true
//                }
//            }
//        }
    }
    
    func getNormalizedDeviceCoordinatePosition(viewMatrix: matrix_float4x4, projectionMatrix: matrix_float4x4) -> float4 {
        let worldPosition = modelMatrix.columns.3
        let clipSpacePosition = projectionMatrix * viewMatrix * worldPosition
        return clipSpacePosition / clipSpacePosition.w
    }
    
    func clickedOnNode(mousePosition: float2, viewMatrix: matrix_float4x4, projectionMatrix: matrix_float4x4) -> Bool {
        let normalizedDeviceCoordPosition = getNormalizedDeviceCoordinatePosition(viewMatrix: viewMatrix,
                                                                                  projectionMatrix: projectionMatrix)
        
        let posX = normalizedDeviceCoordPosition.x
        let posY = normalizedDeviceCoordPosition.y
        
        let minBoundX = posX - 0.1
        let maxBoundX = posX + 0.1
        let minBoundY = posY - 0.1
        let maxBoundY = posY + 0.1
        
//        print("[Node clickedOnNode] Node name: \(getName()), NDC position: \(normalizedDeviceCoordPosition)")
//        print("[Node clickedOnNode] mouse X: \(mousePosition.x), mouse Y: \(mousePosition.y)")
        
        return mousePosition.x >= minBoundX && mousePosition.x <= maxBoundX &&
               mousePosition.y >= minBoundY && mousePosition.y <= maxBoundY
    }
    
    // ---------------
    func compute(with commandEncoder: MTLComputeCommandEncoder, threadsPerGroup: MTLSize) {
        // TODO: Either generalize this or make specific functions for each type of compute type
        if let entity = self as? ParticleEmitterEntity {
            entity.computeUpdate(commandEncoder, threadsPerGroup: threadsPerGroup)
        }
        
        for child in children {
            child.compute(with: commandEncoder, threadsPerGroup: threadsPerGroup)
        }
    }
    // ---------------
    
    func getFwdVector() -> float3 {
        let forward = modelMatrix.columns.2
        return normalize([-forward.x, -forward.y, -forward.z])
    }
    
    func getUpVector() -> float3 {
        let up = modelMatrix.columns.1
        return normalize([up.x, up.y, up.z])
    }

    func getRightVector() -> float3 {
        let right = modelMatrix.columns.0
        return normalize([right.x, right.y, right.z])
    }
    
    func moveAlongVector(_ vector: float3, distance: Float) {
        let to = normalize(vector) * distance
        self.move(to)
    }
    
    //Naming
    func setName(_ name: String){ self._name = name }
    func getName()->String{ return _name }
    func getID()->String { return _id }
    
    //Positioning and Movement
    func setPosition(_ position: float3) {
        self._position = position
        updateModelMatrix()
        afterTranslation()
    }
    func setPosition(_ x: Float, _ y: Float, _ z: Float) { setPosition([x, y, z]) }
    func setPositionX(_ xPosition: Float) { setPosition(xPosition, getPositionY(), getPositionZ()) }
    func setPositionY(_ yPosition: Float) { setPosition(getPositionX(), yPosition, getPositionZ()) }
    func setPositionZ(_ zPosition: Float) { setPosition(getPositionX(), getPositionY(), zPosition) }
    func move(_ x: Float, _ y: Float, _ z: Float) { setPosition(getPositionX() + x, getPositionY() + y, getPositionZ() + z) }
    func move(_ deltaPosition: float3) { setPosition(getPosition() + deltaPosition) }
    func moveX(_ delta: Float) { move(delta, 0, 0) }
    func moveY(_ delta: Float) { move(0, delta, 0) }
    func moveZ(_ delta: Float) { move(0, 0, delta) }
    func getPosition() -> float3 { return self._position }
    func getPositionX() -> Float { return self._position.x }
    func getPositionY() -> Float { return self._position.y }
    func getPositionZ() -> Float { return self._position.z }
    
    //Rotating
    func setRotation(angle: Float, axis: float3) {
        let normalizedAxis = simd_normalize(axis)
        _rotationMatrix = simd_float4x4(simd_quatf(angle: angle, axis: normalizedAxis))
        updateModelMatrix()
        afterRotation()
    }
    
    func setRotationX(_ xRotation: Float) { setRotation(angle: xRotation, axis: getRightVector())}
    func setRotationY(_ yRotation: Float) { setRotation(angle: yRotation, axis: getUpVector())}
    func setRotationZ(_ zRotation: Float) { setRotation(angle: zRotation, axis: getFwdVector())}
    
    func rotate(deltaAngle: Float, axis: float3) {
        let normalizedAxis = simd_normalize(axis)
        _rotationMatrix = simd_float4x4(simd_quatf(angle: deltaAngle, axis: normalizedAxis)) * _rotationMatrix
        updateModelMatrix()
        afterRotation()
    }
//    func rotateX(_ delta: Float){ rotate(deltaAngle: delta, axis: X_AXIS) }
//    func rotateY(_ delta: Float){ rotate(deltaAngle: delta, axis: Y_AXIS) }
//    func rotateZ(_ delta: Float){ rotate(deltaAngle: delta, axis: Z_AXIS) }
    func rotateX(_ delta: Float){ rotate(deltaAngle: delta, axis: getRightVector()) }
    func rotateY(_ delta: Float){ rotate(deltaAngle: delta, axis: getUpVector()) }
    func rotateZ(_ delta: Float){ rotate(deltaAngle: delta, axis: getFwdVector()) }
    
    func rotate3Axis(deltaX: Float, deltaY: Float, deltaZ: Float) {
        rotateX(deltaX)
        rotateY(deltaY)
        rotateZ(deltaZ)
    }
    
    func getRotationX() -> Float { return Transform.decomposeToEulers(_rotationMatrix).x }
    func getRotationY() -> Float { return Transform.decomposeToEulers(_rotationMatrix).y }
    func getRotationZ() -> Float { return Transform.decomposeToEulers(_rotationMatrix).z }
    
    //Scaling
    func setScale(_ scale: float3) {
        self._scale = scale
        updateModelMatrix()
        afterScale()
    }
    func setScale(_ x: Float, _ y: Float, _ z: Float) { setScale([x, y, z]) }
    func setScale(_ scale: Float) { setScale([scale, scale, scale]) }
    func setScaleX(_ scaleX: Float) { setScale(scaleX, getScaleY(), getScaleZ()) }
    func setScaleY(_ scaleY: Float) { setScale(getScaleX(), scaleY, getScaleZ()) }
    func setScaleZ(_ scaleZ: Float) { setScale(getScaleX(), getScaleY(), scaleZ) }
    func scale(_ x: Float, _ y: Float, _ z: Float) { setScale(getScaleX() + x, getScaleY() + y, getScaleZ() + z) }
    func scaleX(_ delta: Float) { scale(delta, 0, 0) }
    func scaleY(_ delta: Float) { scale(0, delta, 0) }
    func scaleZ(_ delta: Float) { scale(0, 0, delta) }
    func getScale() -> float3 { return self._scale }
    func getScaleX() -> Float { return self._scale.x }
    func getScaleY() -> Float { return self._scale.y }
    func getScaleZ() -> Float { return self._scale.z }
}
