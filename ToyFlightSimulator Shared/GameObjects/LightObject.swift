//
//  LightObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

enum LightType: UInt32 {
    case Ambient
    case Directional
    case Omni
    case Point
}

class LightObject: GameObject {
    var type: LightType = .Directional
    var lightData = LightData()
//    let projectionMatrix: float4x4 = Transform.orthographicProjection(-100, 100, -100, 100, -100, 200)
//    let projectionMatrix: float4x4 = Transform.orthographicProjection(-10, 10, -10, 10, -10, 50)
//    let projectionMatrix: float4x4 = Transform.orthographicProjection(-1, 1, -1, 1, -1, 2)
    let projectionMatrix: float4x4 = Transform.orthographicProjection(-15, 15, -15, 15, -15, 200)
    var viewMatrix: float4x4 {
        Transform.look(eye: self.modelMatrix.columns.3.xyz, target: .zero, up: Y_AXIS)
    }
    
    // When calculating texture coordinates to sample from shadow map, flip the y/t coordinate and
    // convert from the [-1, 1] range of clip coordinates to [0, 1] range of
    // used for texture sampling
    let shadowScale = Transform.scaleMatrix(.init(0.5, -0.5, 1))
    let shadowTranslate = Transform.translationMatrix(.init(0.5, 0.5, 0))
    
    init(name: String) {
        super.init(name: name, meshType: .None)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }
    
    init(name: String, meshType: MeshType) {
        super.init(name: name, meshType: meshType)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }
    
    override func update() {
        self.lightData.type = self.type.rawValue
        self.lightData.viewProjectionMatrix = projectionMatrix * viewMatrix
        let position = self.modelMatrix.columns.3.xyz
        let shadowViewMatrix = Transform.look(eye: position, target: .zero, up: Y_AXIS)
        self.lightData.shadowViewProjectionMatrix = projectionMatrix * shadowViewMatrix
        self.lightData.eyeDirection = normalize(float4(-position, 0))
        self.lightData.position = position
        super.update()
    }
}

extension LightObject {
    public func setLightColor(_ color: SIMD3<Float>) { self.lightData.color = color }
    public func setLightColor(_ r: Float, _ g: Float, _ b: Float) { setLightColor(SIMD3<Float>(r, g, b)) }
    public func getLightColor() -> SIMD3<Float> { return self.lightData.color }
    
    public func setLightBrightness(_ brightness: Float) { self.lightData.brightness = brightness }
    public func getLightBrightness() -> Float { return self.lightData.brightness }
    
    public func setLightAmbientIntensity(_ intensity: Float) { self.lightData.ambientIntensity = intensity }
    public func getLightAmbientIntensity() -> Float { return self.lightData.ambientIntensity }
    
    public func setLightDiffuseIntensity(_ intensity: Float) { self.lightData.diffuseIntensity = intensity }
    public func getLightDiffuseIntensity() -> Float { return self.lightData.diffuseIntensity }
    
    public func setLightSpecularIntensity(_ intensity: Float) { self.lightData.specularIntensity = intensity }
    public func getLightSpecularIntensity() -> Float { return self.lightData.specularIntensity }
}
