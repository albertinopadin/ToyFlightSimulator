//
//  LightObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

class LightObject: GameObject {
    var lightData = LightData()
    
    init(name: String) {
        super.init(name: name, meshType: .None)
    }
    
    init(name: String, meshType: MeshType) {
        super.init(name: name, meshType: meshType)
    }
    
    override func update() {
        self.lightData.position = self.getPosition()
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
