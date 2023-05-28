//
//  Node.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class Node {
    private var _name: String = "Node"
    private var _id: String!
    
    private var _position = float3(0, 0, 0)
    private var _scale = float3(1, 1, 1)
//    private var _rotation = float3(0, 0, 0)
    private var _rotationMatrix = matrix_identity_float4x4
    
    var parentModelMatrix = matrix_identity_float4x4
    
    private var _modelMatrix = matrix_identity_float4x4
    
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
    }
    
    internal var _renderPipelineStateType: RenderPipelineStateType = .Opaque
    internal var _gBufferRenderPipelineStateType: RenderPipelineStateType = .GBufferGenerationBase
    
    var parent: Node? = nil
    var children: [Node] = []
    
    init(name: String) {
        self._name = name
        self._id = UUID().uuidString
    }
    
    func addChild(_ child: Node) {
        children.append(child)
        child.parent = self
    }
    
    func removeChild(_ child: Node) {
        children.removeAll(where: { $0.getID() == child.getID() })
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
    }
    
    func handleKeyPressedDebounced(keyCode: Keycodes, keyPressed: inout Bool, _ handleBlock: () -> Void) {
        if Keyboard.IsKeyPressed(keyCode) {
            if !keyPressed {
                keyPressed.toggle()
                handleBlock()
            }
        } else {
            if keyPressed {
                keyPressed.toggle()
            }
        }
    }
    
    func render(renderCommandEncoder: MTLRenderCommandEncoder,
                renderPipelineStateType: RenderPipelineStateType,
                applyMaterials: Bool = true) {
        if _renderPipelineStateType == renderPipelineStateType, let renderable = self as? Renderable {
            renderable.doRender(renderCommandEncoder, applyMaterials: applyMaterials, submeshesToRender: nil)
        }
        
        for child in children {
            child.render(renderCommandEncoder: renderCommandEncoder,
                         renderPipelineStateType: renderPipelineStateType,
                         applyMaterials: applyMaterials)
        }
    }
    
    func renderGBuffer(renderCommandEncoder: MTLRenderCommandEncoder, gBufferRPS: RenderPipelineStateType) {
        if _gBufferRenderPipelineStateType == gBufferRPS, _renderPipelineStateType != .Skybox,
            let renderable = self as? Renderable {
            renderable.doRender(renderCommandEncoder, applyMaterials: true, submeshesToRender: nil)
        }
        
        for child in children {
            child.renderGBuffer(renderCommandEncoder: renderCommandEncoder, gBufferRPS: gBufferRPS)
        }
    }
    
    func renderShadows(renderCommandEncoder: MTLRenderCommandEncoder) {
        if _renderPipelineStateType != .Skybox, let renderable = self as? Renderable {
            renderable.doRenderShadow(renderCommandEncoder, submeshesToRender: nil)
        }
        
        for child in children {
            child.renderShadows(renderCommandEncoder: renderCommandEncoder)
        }
    }
    
    func getFwdVector() -> float3 {
        let forward = modelMatrix.columns.2
        return normalize(float3(-forward.x, -forward.y, -forward.z))
    }
    
    func getUpVector() -> float3 {
        let up = modelMatrix.columns.1
        return normalize(float3(up.x, up.y, up.z))
    }

    func getRightVector() -> float3 {
        let right = modelMatrix.columns.0
        return normalize(float3(right.x, right.y, right.z))
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
    func setPosition(_ x: Float, _ y: Float, _ z: Float) { setPosition(float3(x, y, z)) }
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
//    func setRotation(angle: Float, axis: float3) {
//        // Maybe reset rotation matrix to identity here ???
//        _rotationMatrix = simd_float4x4(simd_quatf(angle: angle, axis: axis)) * matrix_identity_float4x4
//        updateModelMatrix()
//        afterRotation()
//    }
//    func setRotation(_ x: Float, _ y: Float, _ z: Float) { setRotation(float3(x, y, z)) }
//    func setRotationX(_ xRotation: Float) { setRotation(xRotation, getRotationY(), getRotationZ()) }
//    func setRotationX(_ xRotation: Float) { setRotation(angle: xRotation, axis: X_AXIS)}
//    func setRotationY(_ yRotation: Float) { setRotation(getRotationX(), yRotation, getRotationZ()) }
//    func setRotationY(_ yRotation: Float) { setRotation(angle: yRotation, axis: Y_AXIS)}
//    func setRotationZ(_ zRotation: Float) { setRotation(getRotationX(), getRotationY(), zRotation) }
//    func setRotationZ(_ zRotation: Float) { setRotation(angle: zRotation, axis: Z_AXIS)}
//    func rotate(_ x: Float, _ y: Float, _ z: Float){ setRotation(getRotationX() + x, getRotationY() + y, getRotationZ() + z) }
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
//    func getRotation() -> float3 { return self._rotation }
//    func getRotationX() -> Float { return self._rotation.x }
//    func getRotationY() -> Float { return self._rotation.y }
//    func getRotationZ() -> Float { return self._rotation.z }
    
//    func rotateOnAxis(_ axis: float3, degrees: Float) {
//        _modelMatrix.rotate(angle: degrees, axis: axis)
//        afterRotation()
//    }
    
    //Scaling
    func setScale(_ scale: float3) {
        self._scale = scale
        updateModelMatrix()
        afterScale()
    }
    func setScale(_ x: Float, _ y: Float, _ z: Float) { setScale(float3(x, y, z)) }
    func setScale(_ scale: Float) { setScale(float3(scale, scale, scale)) }
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
