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
    
    var parentModelMatrix = matrix_identity_float4x4
    var ignoreParentScale: Bool = false
    
    private var _modelMatrix = matrix_identity_float4x4
    private var _rotationMatrix = matrix_identity_float4x4
    
    internal var _renderPipelineStateType: RenderPipelineStateType = .Opaque
    internal var _gBufferRenderPipelineStateType: RenderPipelineStateType = .GBufferGenerationBase
    
    var parent: Node? = nil
    var children: [Node] = []
    
    var modelMatrix: matrix_float4x4 {
        set {
            _modelMatrix = newValue
        }
        
        get {
            // TODO: having a condition here is probably bad for performance...
            if ignoreParentScale, let parentScale = parent?.getScale() {
                let unscaledParentModelMatrix = parentModelMatrix * Transform.scaleMatrix(float3(x: 1/parentScale.x,
                                                                                                 y: 1/parentScale.y,
                                                                                                 z: 1/parentScale.z))
                return matrix_multiply(unscaledParentModelMatrix, _modelMatrix)
            }
            return matrix_multiply(parentModelMatrix, _modelMatrix)
        }
    }
    
    var normalMatrix: matrix_float3x3 {
        get {
            return Transform.normalMatrix(from: self.modelMatrix)
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
    
    func shouldRender(with renderPipelineStateType: RenderPipelineStateType) -> Bool {
        if self is PointLightObject {
            return (renderPipelineStateType == .LightMask || renderPipelineStateType == .PointLight) && 
                   (_renderPipelineStateType == .LightMask || _renderPipelineStateType == .PointLight)
        } else {
            return _renderPipelineStateType == renderPipelineStateType
        }
    }
    
//    func render(renderCommandEncoder: MTLRenderCommandEncoder,
//                renderPipelineStateType: RenderPipelineStateType,
//                applyMaterials: Bool = true) {
////        if renderPipelineStateType == .LightMask {
//////            print("[Node render] got rps for point light")
////            print("[Node render] got rps for mask light")
////            print("[Node render] self rps: \(_renderPipelineStateType)")
////        }
//        
////        if self is Icosahedron && renderPipelineStateType == .Icosahedron {
////            print("[Node render] In icosahedron render")
////            print("Given RPS: \(renderPipelineStateType)")
////            print("Internal RPS: \(_renderPipelineStateType)")
////        }
//        
//        if shouldRender(with: renderPipelineStateType), let renderable = self as? Renderable {
////            if renderPipelineStateType == .LightMask {
////                print("[Node render] calling doRender for light mask")
////            }
////            if self is Icosahedron {
////                print("[Node render] rendering icosahedron, given rps: \(renderPipelineStateType)")
////            }
//            renderable.doRender(renderCommandEncoder, applyMaterials: applyMaterials, submeshesToRender: nil)
//        }
//        
//        for child in children {
//            child.render(renderCommandEncoder: renderCommandEncoder,
//                         renderPipelineStateType: renderPipelineStateType,
//                         applyMaterials: applyMaterials)
//        }
//    }
    
//    // TODO: Smells off to manually set these conditions...
    func shouldRenderGBuffer(gBufferRPS: RenderPipelineStateType) -> Bool {
        return _gBufferRenderPipelineStateType == gBufferRPS &&
               _renderPipelineStateType != .Skybox &&
               !(self is LightObject) && !(self is Icosahedron)
    }
    
//    func renderGBuffer(renderCommandEncoder: MTLRenderCommandEncoder, gBufferRPS: RenderPipelineStateType) {
//        if shouldRenderGBuffer(gBufferRPS: gBufferRPS), let renderable = self as? Renderable {
//            renderable.doRender(renderCommandEncoder, applyMaterials: true, submeshesToRender: nil)
//        }
//        
//        for child in children {
//            child.renderGBuffer(renderCommandEncoder: renderCommandEncoder, gBufferRPS: gBufferRPS)
//        }
//    }
    
    // TODO: Smells off to manually set these conditions...
    func shouldRenderShadows() -> Bool {
        return _renderPipelineStateType != .Skybox && !(self is LightObject) && !(self is Icosahedron)
    }
    
    func renderShadows(renderCommandEncoder: MTLRenderCommandEncoder) {
        if shouldRenderShadows(), let renderable = self as? Renderable {
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
