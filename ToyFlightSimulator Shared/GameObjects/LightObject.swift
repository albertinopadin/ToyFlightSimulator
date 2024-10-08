//
//  LightObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

class LightObject: GameObject {
    var lightType: LightType
    var lightData = LightData()
    // TODO: What should the light projection matrix be ???
//    let projectionMatrix: float4x4 = Transform.orthographicProjection(-100, 100, -100, 100, -100, 100)
    let projectionMatrix: float4x4 = Transform.orthographicProjection(-100, 100, -100, 100, 0.01, 1000)
    var viewMatrix: float4x4 {
//        Transform.look(eye: self.modelMatrix.columns.3.xyz, target: .zero, up: Y_AXIS)
        Transform.look(eye: self.getPosition(), target: .zero, up: Y_AXIS)
    }
    
    // When calculating texture coordinates to sample from shadow map, flip the y/t coordinate and
    // convert from the [-1, 1] range of clip coordinates to [0, 1] range of
    // used for texture sampling
    let shadowScale = Transform.scaleMatrix(.init(0.5, -0.5, 1))
    let shadowTranslate = Transform.translationMatrix(.init(0.5, 0.5, 0))
    
    private var _modelType: ModelType = .None
    
    // TODO: What RPS is appropriate for a LightObject ???
    init(name: String, lightType: LightType = Directional) {
        self.lightType = lightType
        super.init(name: name, modelType: .None)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }
    
    // TODO: What RPS is appropriate for a LightObject ???
    init(name: String, lightType: LightType = Directional, modelType: ModelType = .Sphere) {
        self.lightType = lightType
        self._modelType = modelType
        super.init(name: name, modelType: modelType)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }
    
    override func update() {
        super.update()
        self.lightData.type = self.lightType
        self.lightData.modelMatrix = self.modelMatrix
        self.lightData.viewProjectionMatrix = projectionMatrix * viewMatrix
//        let position = self.modelMatrix.columns.3.xyz
//        self.lightData.position = position
//        self.lightData.eyeDirection = normalize(float4(-position, 1))
        
        self.lightData.position = self.getPosition()
//        self.lightData.eyeDirection = normalize(float4(-self.getPosition(), 1))
//        let shadowViewMatrix = Transform.look(eye: position, target: .zero, up: Y_AXIS)
//        let shadowViewMatrix = Transform.look(eye: position, target: self.lightData.eyeDirection.xyz * 10.0, up: Y_AXIS)
        let shadowViewMatrix = Transform.look(eye: self.getPosition(), target: .zero, up: Y_AXIS)
        self.lightData.shadowViewProjectionMatrix = projectionMatrix * shadowViewMatrix
    }
}

extension LightObject {
    public func setLightColor(_ color: float3) {
        self.lightData.color = color
        if _modelType != .None {
            self.setColor(float4(color, 1.0))
        }
    }
    public func setLightColor(_ r: Float, _ g: Float, _ b: Float) { setLightColor([r, g, b]) }
    public func getLightColor() -> SIMD3<Float> { return self.lightData.color }
    
    public func setLightBrightness(_ brightness: Float) { self.lightData.brightness = brightness }
    public func getLightBrightness() -> Float { return self.lightData.brightness }
    
    public func setLightAmbientIntensity(_ intensity: Float) { self.lightData.ambientIntensity = intensity }
    public func getLightAmbientIntensity() -> Float { return self.lightData.ambientIntensity }
    
    public func setLightDiffuseIntensity(_ intensity: Float) { self.lightData.diffuseIntensity = intensity }
    public func getLightDiffuseIntensity() -> Float { return self.lightData.diffuseIntensity }
    
    public func setLightSpecularIntensity(_ intensity: Float) { self.lightData.specularIntensity = intensity }
    public func getLightSpecularIntensity() -> Float { return self.lightData.specularIntensity }
    
    public func setLightRadius(_ radius: Float) { self.lightData.radius = radius }
    public func getLightRadius() -> Float { return self.lightData.radius }
}
