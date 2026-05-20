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

    // Configuration for the per-frame shadow camera (Directional lights only).
    // Defaults chosen for FlightboxWithPhysics-scale scenes (1M ground, F-22 at
    // flight speeds). Override per-scene via setShadowRadius/setShadowLift.
    private var _shadowRadius: Float = 500
    private var _shadowLift:   Float = 2000

    // World-space depth slack used by the shader's shadow-compare epsilon.
    // 0.25 world units lets small features (F-22 rudders at scale 0.25 are
    // ~0.5 world units) self-shadow without acne on typical receivers.
    // Larger → safer against acne; smaller → finer self-shadow detail.
    private var _shadowWorldSlack: Float = 0.25

    // Shadow-coord transform from clip-space [-1,1] to UV [0,1] with Y flip.
    // Kept as a constant since legacy GBuffer.metal still consumes
    // `LightData.shadowTransformMatrix`. Tiled deferred path derives the
    // transform inline in CalculateShadow.
    let shadowScale = Transform.scaleMatrix(.init(0.5, -0.5, 1))
    let shadowTranslate = Transform.translationMatrix(.init(0.5, 0.5, 0))

    // Explicit world-space direction (from surfaces TOWARD the sun). If nil,
    // direction is derived from `getPosition()` for backward compatibility with
    // scenes that only call `setPosition` to aim the sun.
    private var _explicitDirection: float3?

    /// World-space unit vector from surfaces toward the sun.
    /// Explicit setter wins; otherwise derived from position (legacy behavior).
    var direction: float3 {
        if let d = _explicitDirection { return d }
        let p = self.getPosition()
        let lengthSq = simd_length_squared(p)
        return lengthSq > .ulpOfOne ? p / sqrt(lengthSq) : Y_AXIS
    }

    /// Override the world-space direction the light shines from. Pass a vector
    /// pointing FROM lit surfaces TO the sun (gets normalized internally).
    /// If never called, direction is inferred from `getPosition()`.
    func setLightDirection(_ dir: float3) {
        _explicitDirection = normalize(dir)
    }

    /// Half-extent of the orthographic shadow frustum, in world units. Smaller
    /// values give sharper shadows but a smaller covered area around the camera.
    func setShadowRadius(_ radius: Float) { _shadowRadius = radius }

    /// Distance to lift the shadow eye along the light direction. Must be
    /// larger than the tallest shadow caster's height above the focus point.
    func setShadowLift(_ lift: Float) { _shadowLift = lift }

    /// World-space slack used by the shader's depth-compare epsilon. Tune
    /// down to capture finer self-shadow detail; tune up if acne appears on
    /// flat receivers. Typical range: 0.05 – 1.0 world units.
    func setShadowWorldSlack(_ slack: Float) { _shadowWorldSlack = slack }

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
        self.lightData.type        = self.lightType
        self.lightData.modelMatrix = self.modelMatrix
        self.lightData.position    = self.getPosition()
        self.lightData.direction   = self.direction

        if self.lightType == Directional {
            updateShadowCamera()
        }
    }

    /// Build a per-frame ShadowCamera focused on the active main camera and
    /// stash its matrices in `lightData`. No-ops if no camera is active yet
    /// (matrices keep their last-good values, which is fine for the first
    /// frame before SceneManager.SetScene completes camera registration).
    private func updateShadowCamera() {
        guard let cam = CameraManager.CurrentCamera else { return }
        let shadowCamera = ShadowCamera(direction: self.direction,
                                        focus: cam.getWorldPosition(),
                                        radius: _shadowRadius,
                                        lift: _shadowLift)
        let svp = shadowCamera.viewProjectionMatrix
        lightData.shadowViewProjectionMatrix = svp
        lightData.viewProjectionMatrix       = svp

        // Ortho near = 1, far = 2*lift → range = 2*lift - 1. The shader uses
        // `shadowWorldSlack / shadowDepthRange` to derive an NDC-space epsilon
        // that's invariant to frustum scale.
        lightData.shadowDepthRange = 2 * _shadowLift - 1
        lightData.shadowWorldSlack = _shadowWorldSlack
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
