//
//  LightObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

enum LightType: UInt32 {
    case ambient
    case directional
    case omni
}

class LightObject: GameObject {
    let shadowMapSize = 2048
    var type = LightType.directional
    var lightData = LightData()
    var shadowTexture: MTLTexture
    
    var projectionMatrix = matrix_identity_float4x4
    var viewMatrix = matrix_identity_float4x4
    var translation = float3(0,0,0)
    
    init(name: String) {
        let shadowTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                               width: shadowMapSize,
                                                                               height: shadowMapSize,
                                                                               mipmapped: false)
        shadowTextureDescriptor.storageMode = .private
        shadowTextureDescriptor.usage = [.renderTarget, .shaderRead]
        shadowTexture = Engine.Device.makeTexture(descriptor: shadowTextureDescriptor)!
        super.init(name: name, meshType: .None)
    }
    
    init(name: String, meshType: MeshType) {
        let shadowTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                               width: shadowMapSize,
                                                                               height: shadowMapSize,
                                                                               mipmapped: false)
        shadowTextureDescriptor.storageMode = .private
        shadowTextureDescriptor.usage = [.renderTarget, .shaderRead]
        shadowTexture = Engine.Device.makeTexture(descriptor: shadowTextureDescriptor)!
        super.init(name: name, meshType: meshType)
    }
    
    override func update() {
        projectionMatrix = matrix_float4x4.orthographic(left: -20.0,
                                                        right: 20.0,
                                                        bottom: -20.0,
                                                        top: 20.0,
                                                        near: -100,
                                                        far: 200)
        viewMatrix = matrix_float4x4.lookAt(eye: -self.getPosition(), center: [0,0,0], up: [0,1,0])
        lightData.lightSpaceMatrix = matrix_multiply(projectionMatrix, viewMatrix)
//        lightData.translation = translation
        lightData.translation = self.getPosition()
        lightData.color = self.getLightColor()
    }
    
//    override func update() {
//        let shadowViewMatrix = self.modelMatrix.inverse
//        let shadowProjectionMatrix = self.projectionMatrix
//        let shadowViewProjectionMatrix = shadowProjectionMatrix * shadowViewMatrix
//        self.lightData.viewProjectionMatrix = shadowViewProjectionMatrix
//        self.lightData.position = self.getPosition()
//        super.update()
//    }
    
    // Warren Moore / 30 Days of Metal:
//    var direction: SIMD3<Float> {
//        return -modelMatrix.columns.2.xyz
//    }
//
//    // Seems to control how big the area lit up is:
//    var projectionMatrix: float4x4 {
//        return simd_float4x4(orthographicProjectionWithLeft: -1.5, top: 1.5, right: 1.5, bottom: -1.5, near: 0, far: 1000)
//    }
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
