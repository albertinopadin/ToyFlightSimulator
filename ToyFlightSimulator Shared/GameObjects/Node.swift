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
    
    var parentModelMatrix = matrix_identity_float4x4 {
        didSet { _worldMatrixValid = false }
    }

    private var _modelMatrix = matrix_identity_float4x4
    private var _rotationMatrix = matrix_identity_float4x4

    /// N2: local T·R·S needs rebuilding. Setters only flag this; the rebuild
    /// happens lazily on the first modelMatrix read (multiple setter calls per
    /// frame — e.g. physics move + collision corrections — cost flag writes,
    /// not matrix multiplies).
    private var _localMatrixDirty: Bool = true

    /// N1: cached parent×local composition, so repeated modelMatrix reads
    /// (per-child propagation, modelConstants, direction vectors) don't redo
    /// the 4×4 multiply.
    private var _worldMatrix = matrix_identity_float4x4
    private var _worldMatrixValid: Bool = false
    /// Bumped whenever the cached world matrix is recomputed. Consumers that
    /// derive from the world matrix (Camera.viewMatrix) compare generations
    /// instead of recomputing per read.
    private(set) var worldMatrixGeneration: UInt64 = 0

    /// True when position, rotation, or scale has changed since last update.
    /// Starts true so the first frame computes the initial matrix.
    private var _transformDirty: Bool = true
    
    /// True when this node's world matrix changed (own transform or parent change).
    /// Read by GameObject to decide whether to recompute modelConstants.
    private(set) var worldMatrixDirty: Bool = true
    
    var parent: Node? = nil
    var children: [Node] = []
    
    var modelMatrix: matrix_float4x4 {
        set {
            // Caller supplies the LOCAL matrix directly (existing semantics);
            // the getter composes it with parentModelMatrix.
            _modelMatrix = newValue
            _localMatrixDirty = false
            _worldMatrixValid = false
        }

        get {
            if _localMatrixDirty {
                // Clear the flag BEFORE rebuilding so derived getters invoked
                // during the rebuild don't recurse.
                _localMatrixDirty = false
                updateModelMatrix()
                _worldMatrixValid = false
            }
            if !_worldMatrixValid {
                _worldMatrix = matrix_multiply(parentModelMatrix, _modelMatrix)
                _worldMatrixValid = true
                worldMatrixGeneration &+= 1
            }
            return _worldMatrix
        }
    }
    
    var rotationMatrix: matrix_float4x4 {
        get {
            return _rotationMatrix
        }
        
        set {
            // Public mutation must dirty-flag like every other transform
            // setter — a bare storage write leaves the cached local/world
            // matrices stale until some unrelated setter happens to run.
            updateModelMatrixAndMarkTransformDirty {
                _rotationMatrix = newValue
            }
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
    
    /// Rebuilds the LOCAL T·R·S matrix. Invoked lazily from the modelMatrix
    /// getter when a setter has flagged `_localMatrixDirty` (N2) — not called
    /// eagerly by the setters anymore.
    func updateModelMatrix() {
        _modelMatrix = Transform.translationMatrix(_position) * _rotationMatrix * Transform.scaleMatrix(_scale)
    }
    
    /// Marks this node and all descendants as needing matrix recomputation.
    func markTransformDirty() {
        guard !_transformDirty else { return }  // Already dirty - skip subtree walk
        
        _transformDirty = true
        
        for child in children {
            child.markTransformDirty()
        }
    }
    
    // Override these when needed:
    func afterTranslation() { }
    func afterRotation() { }
    func afterScale() { }
    
    /// Override this function instead of the update function
    func doUpdate() { }
    
    func update() {
        doUpdate()
        
        let needsUpdate = _transformDirty

        if needsUpdate {
            // The local matrix rebuild is lazy (first modelMatrix read); here we
            // only clear the traversal flag. When _transformDirty was set by a
            // parent propagation, the local matrix hasn't changed — only
            // parentModelMatrix was updated, which is handled in the child loop.
            _transformDirty = false
        }

        worldMatrixDirty = needsUpdate

        if needsUpdate && !children.isEmpty {
            // Hoisted: one cached world-matrix read for all children instead of
            // a recompute per child.
            let world = self.modelMatrix
            for child in children {
                child.parentModelMatrix = world
                child._transformDirty = true
                child.update()
            }
        } else {
            for child in children {
                child.update()
            }
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
    // TODO: Having compute function per "thing" is a hack
    func computeParticles(with commandEncoder: MTLComputeCommandEncoder, threadsPerGroup: MTLSize) {
        // TODO: Either generalize this or make specific functions for each type of compute type
        if let entity = self as? ParticleEmitterEntity {
            entity.computeUpdate(commandEncoder, threadsPerGroup: threadsPerGroup)
        }
        
        // TODO: Should batch up compute entities like we do with renderables to be more efficient
        //       instead of traversing scene heirarchy
        for child in children {
            child.computeParticles(with: commandEncoder, threadsPerGroup: threadsPerGroup)
        }
    }
    
    func computeTerrainTessellation(with commandEncoder: MTLComputeCommandEncoder) {
        if let entity = self as? Tessellatable {
            entity.computeUpdate(commandEncoder)
        }
        
        for child in children {
            child.computeTerrainTessellation(with: commandEncoder)
        }
    }
    // ---------------
    
    func getFwdVector() -> float3 {
        let forward = modelMatrix.columns.2
        return normalize([forward.x, forward.y, forward.z])
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
    
    @inline(__always)
    func updateModelMatrixAndMarkTransformDirty(_ body: () -> Void) {
        body()
        // N2: defer the T·R·S rebuild to the first modelMatrix read instead of
        // rebuilding eagerly on every setter call.
        _localMatrixDirty = true
        _worldMatrixValid = false
        markTransformDirty()
    }
    
    //Positioning and Movement
    func setPosition(_ position: float3) {
        updateModelMatrixAndMarkTransformDirty {
            self._position = position
        }
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

    /// World-space translation, accounting for parent-chain transforms.
    /// Use this (not `getPosition()`) whenever the consumer needs an absolute
    /// world location — `getPosition()` returns the *local* `_position` value
    /// set by `setPosition`, which for a parented node (e.g. an `AttachedCamera`
    /// child of an aircraft) is just the parent-relative offset.
    func getWorldPosition() -> float3 {
        let world = modelMatrix.columns.3
        return float3(world.x, world.y, world.z)
    }
    func getPositionZ() -> Float { return self._position.z }
    
    //Rotating
    func setRotation(angle: Float, axis: float3) {
        updateModelMatrixAndMarkTransformDirty {
            let normalizedAxis = simd_normalize(axis)
            _rotationMatrix = simd_float4x4(simd_quatf(angle: angle, axis: normalizedAxis))
        }
        afterRotation()
    }
    
    func setRotation(_ q: simd_quatf) {
        rotationMatrix = simd_float4x4(q)
        afterRotation()
    }
    
    func setRotationX(_ xRotation: Float) { setRotation(angle: xRotation, axis: getRightVector())}
    func setRotationY(_ yRotation: Float) { setRotation(angle: yRotation, axis: getUpVector())}
    func setRotationZ(_ zRotation: Float) { setRotation(angle: zRotation, axis: getFwdVector())}
    
    func rotate(deltaAngle: Float, axis: float3) {
        updateModelMatrixAndMarkTransformDirty {
            let normalizedAxis = simd_normalize(axis)
            _rotationMatrix = simd_float4x4(simd_quatf(angle: deltaAngle, axis: normalizedAxis)) * _rotationMatrix
        }
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
    
    /// All three Euler angles from a single decomposition. Prefer this over
    /// consecutive getRotationX/Y/Z calls (each runs the full decompose).
    func getRotationEulers() -> float3 { return Transform.decomposeToEulers(_rotationMatrix) }
    func getRotationX() -> Float { return getRotationEulers().x }
    func getRotationY() -> Float { return getRotationEulers().y }
    func getRotationZ() -> Float { return getRotationEulers().z }
    func getRotationMatrix() -> float4x4 { return _rotationMatrix }
    
    // Scaling
    func setScale(_ scale: float3) {
        updateModelMatrixAndMarkTransformDirty {
            self._scale = scale
        }
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
    
    /// Uniform-scale contract for physics colliders: spec dimensions are model
    /// units, world meters = model units × this. Debug-asserts the scale is
    /// actually uniform so a stray setScale(x,y,z) can't silently skew colliders.
    var uniformScale: Float {
        let s = getScale()
        assert(abs(s.x - s.y) <= 1e-4 * max(1, abs(s.x)) &&
               abs(s.x - s.z) <= 1e-4 * max(1, abs(s.x)),
               "Non-uniform scale \(s) on '\(getName())' breaks the collider units contract")
        return s.x
    }
}
