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

    // CSM configuration. Defaults tuned for FlightboxWithPhysics-scale scenes
    // (1M ground, F-22 at flight speeds). Override per-scene via the setters.
    private var _cascadeCount:      Int   = 4         // 1...TFS_MAX_SHADOW_CASCADES
    // PSSM hybrid blend: 0 = uniform, 1 = logarithmic. 0.5 is the classic
    // Microsoft hybrid. The attached camera no longer inherits its parent's
    // scale (AttachedCamera strips it), so cascade 0 is sized in true world
    // units and 0.5 already keeps the jet in the sharp near cascade with smooth
    // near→mid transitions. Raise toward 0.8 for an even tighter near cascade.
    private var _cascadeLambda:     Float = 0.5
    private var _shadowMapRes:      Int   = 4096      // MUST match ShadowRendering.ShadowMapSize
    private var _shadowMaxDistance: Float = 500       // decouple shadow reach from cam.far
    private var _cascadeZPad:       Float = 100       // additive ortho z-padding (world units)
    private var _shadowWorldSlack:  Float = 0.25      // base slack; per-cascade scaled in shader

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
    func setLightDirection(_ dir: float3) { _explicitDirection = normalize(dir) }

    /// Number of cascades (clamped to 1...TFS_MAX_SHADOW_CASCADES).
    func setCascadeCount(_ n: Int)        { _cascadeCount = min(max(n, 1), Int(TFS_MAX_SHADOW_CASCADES)) }
    /// PSSM hybrid blend: 0 = uniform splits, 1 = logarithmic splits.
    func setCascadeLambda(_ l: Float)     { _cascadeLambda = simd_clamp(l, 0, 1) }
    /// Far distance the cascades cover, decoupled from the camera's far plane.
    func setShadowMaxDistance(_ d: Float) { _shadowMaxDistance = max(d, 1) }
    /// MUST be kept in sync with ShadowRendering.ShadowMapSize (drives texel snap).
    func setShadowMapResolution(_ r: Int) { _shadowMapRes = r }
    /// Additive ortho depth padding in world units.
    func setCascadeZPad(_ pad: Float)     { _cascadeZPad = max(pad, 0) }
    /// World-space depth slack for the shader's depth-compare epsilon. Tune down
    /// for finer self-shadow detail; up if acne appears on flat receivers.
    func setShadowWorldSlack(_ slack: Float) { _shadowWorldSlack = max(slack, 0) }

    private var _modelType: ModelType = .None

    init(name: String, lightType: LightType = Directional) {
        self.lightType = lightType
        super.init(name: name, modelType: .None)
    }

    init(name: String, lightType: LightType = Directional, modelType: ModelType = .Sphere) {
        self.lightType = lightType
        self._modelType = modelType
        super.init(name: name, modelType: modelType)
    }

    override func update() {
        super.update()
        self.lightData.type             = self.lightType
        self.lightData.modelMatrix      = self.modelMatrix
        self.lightData.position         = self.getPosition()
        self.lightData.direction        = self.direction
        self.lightData.shadowWorldSlack = _shadowWorldSlack

        if self.lightType == Directional {
            updateShadowCascades()
        }
    }

    /// Fit the cascades against the active main camera and stash their matrices
    /// in `lightData`. No-ops if no camera is active yet (matrices keep their
    /// last-good values, which is fine before SceneManager.SetScene registers
    /// the camera — the renderer also needs a current camera to draw).
    private func updateShadowCascades() {
        guard let cam = CameraManager.CurrentCamera else { return }

        // Derive vertical FOV and aspect from the live camera. fieldOfView is
        // stored in degrees; aspect is read off the projection matrix
        // (columns.1.y = 1/tan(fovY/2); columns.0.x = that / aspect) so it always
        // matches what the camera is actually rendering with, reverse-Z or not.
        let fovY = cam.fieldOfView.toRadians
        let proj = cam.projectionMatrix
        let xs = proj.columns.0.x
        let ys = proj.columns.1.y
        let aspect = (xs != 0) ? (ys / xs) : Renderer.AspectRatio

        let snapshot = ShadowCascadeFitting.CameraSnapshot(
            viewMatrix: cam.viewMatrix,
            near:       cam.near,
            far:        cam.far,
            fovY:       fovY,
            aspect:     aspect)

        let fit = ShadowCascadeFitting.fitCascades(
            camera:              snapshot,
            lightDirection:      self.direction,
            shadowMapResolution: _shadowMapRes,
            cascadeCount:        _cascadeCount,
            lambda:              _cascadeLambda,
            shadowMaxDistance:   _shadowMaxDistance,
            zPaddingWorldUnits:  _cascadeZPad)

        // Split-far depths are in view-space (scaled) units; convert to world
        // units for shader consumption (the fragment computes fragViewSpaceDepth
        // in world units via distance(worldPos, cameraPos)). Same scale
        // extraction as in boundingSphereForSlice.
        let c0 = cam.viewMatrix.inverse.columns.0
        let cameraScale = simd_length(simd_float3(c0.x, c0.y, c0.z))

        lightData.cascadeCount = UInt32(_cascadeCount)
        writeCascadeMatrices(into: &lightData.cascadeViewProjectionMatrices,
                             from: fit.cascades.map { $0.viewProjectionMatrix })
        writeCascadeFloats(into: &lightData.cascadeSplitDepths,
                           from: fit.splitFars.map { $0 * cameraScale })
        writeCascadeFloats(into: &lightData.cascadeDepthRanges,
                           from: fit.cascades.map { $0.depthRange })
    }
}

// MARK: - Cascade tuple-array writers
//
// LightData's C arrays import into Swift as homogeneous tuples;
// `withUnsafeMutablePointer` + `withMemoryRebound` gives indexed access.

private func writeCascadeMatrices(into tuple: inout (float4x4, float4x4, float4x4, float4x4),
                                  from src: [float4x4]) {
    withUnsafeMutablePointer(to: &tuple) { tuplePtr in
        tuplePtr.withMemoryRebound(to: float4x4.self,
                                   capacity: Int(TFS_MAX_SHADOW_CASCADES)) { ptr in
            for i in 0..<min(src.count, Int(TFS_MAX_SHADOW_CASCADES)) {
                ptr[i] = src[i]
            }
        }
    }
}

private func writeCascadeFloats(into tuple: inout (Float, Float, Float, Float),
                                from src: [Float]) {
    withUnsafeMutablePointer(to: &tuple) { tuplePtr in
        tuplePtr.withMemoryRebound(to: Float.self,
                                   capacity: Int(TFS_MAX_SHADOW_CASCADES)) { ptr in
            for i in 0..<min(src.count, Int(TFS_MAX_SHADOW_CASCADES)) {
                ptr[i] = src[i]
            }
        }
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
