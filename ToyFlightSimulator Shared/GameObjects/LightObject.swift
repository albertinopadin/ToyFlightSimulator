//
//  LightObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

//enum LightType: UInt32 {
//    case Ambient
//    case Directional
//    case Omni
//    case Point
//}

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
    
    private var _meshType: MeshType = .None
    
    // TODO: What RPS is appropriate for a LightObject ???
    init(name: String, lightType: LightType = Directional, renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        self.lightType = lightType
        super.init(name: name, meshType: .None, renderPipelineStateType: renderPipelineStateType)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }
    
    // TODO: What RPS is appropriate for a LightObject ???
    init(name: String,
         lightType: LightType = Directional,
         meshType: MeshType = .Sphere,
         renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        self.lightType = lightType
        self._meshType = meshType
        super.init(name: name, meshType: meshType, renderPipelineStateType: renderPipelineStateType)
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
        
//        print("[LightObject update]")
//        print("self.getPosition: \(self.getPosition())")
//        print("self.modelMatrix.columns.3.xyz: \(self.modelMatrix.columns.3.xyz)")
        
        self.lightData.position = self.getPosition()
//        self.lightData.eyeDirection = normalize(float4(-self.getPosition(), 1))
//        let shadowViewMatrix = Transform.look(eye: position, target: .zero, up: Y_AXIS)
//        let shadowViewMatrix = Transform.look(eye: position, target: self.lightData.eyeDirection.xyz * 10.0, up: Y_AXIS)
        let shadowViewMatrix = Transform.look(eye: self.getPosition(), target: .zero, up: Y_AXIS)
        self.lightData.shadowViewProjectionMatrix = projectionMatrix * shadowViewMatrix
    }
}

extension LightObject {
    public func setLightColor(_ color: SIMD3<Float>) {
        self.lightData.color = color
        if _meshType != .None {
            var material = ShaderMaterial()
            material.color = float4(color, 1.0)  // TODO: Why are we setting the material color alpha to zero?
            self.useMaterial(material)
        }
    }
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
    
    public func setLightRadius(_ radius: Float) { self.lightData.radius = radius }
    public func getLightRadius() -> Float { return self.lightData.radius }
}
