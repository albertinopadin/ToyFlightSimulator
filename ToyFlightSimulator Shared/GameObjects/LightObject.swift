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

    // === Cascade configuration (Directional lights only) ===
    // Defaults chosen for FlightboxWithPhysics-scale scenes (1M ground, F-22
    // at flight speeds). Override per-scene via the setCascade* methods.
    private var _cascadeCount: Int    = 4    // 1..TFS_MAX_SHADOW_CASCADES
    private var _cascadeLambda: Float = 0.5  // PSSM blend: 0=uniform, 1=log
    private var _shadowMapRes: Int    = 4096 // per-cascade resolution (must match ShadowRendering.ShadowMapSize)
    private var _cascadeZPad: Float   = 100  // z-axis ortho padding in world units (additive)

    // Max distance (world units) cascades will cover. Decoupled from the
    // camera's far plane — flight-sim cameras have far = 1,000,000 to draw
    // the sky/horizon, but shadow casters realistically sit within ~500
    // world units of the camera. Without this cap, the cascade-PSSM splits
    // (e.g. lambda=0.5 with near=0.01, far=1e6) produce a cascade-0 that
    // covers 125,000 world units — making each shadow texel ~480 world
    // units wide, far larger than any aircraft.
    private var _shadowMaxDistance: Float = 500

    // World-space depth slack the shader allows before a fragment shadows
    // itself. For cascades, this is scaled per-cascade by cascade extent —
    // distant cascades have wider texels and need proportionally more slack.
    private var _baseWorldSlack: Float = 0.25

    // Legacy radius/lift kept for the cascadeCount==1 fast path that
    // preserves the single-cascade sun-follow plan's behavior verbatim.
    private var _shadowRadius: Float = 500
    private var _shadowLift:   Float = 2000

    // Shadow-coord transform from clip-space [-1,1] to UV [0,1] with Y flip.
    // Kept as a constant since legacy GBuffer.metal still consumes
    // `LightData.shadowTransformMatrix`. Tiled deferred path derives the
    // transform inline in CalculateShadow.
    let shadowScale = Transform.scaleMatrix(.init(0.5, -0.5, 1))
    let shadowTranslate = Transform.translationMatrix(.init(0.5, 0.5, 0))

    // Explicit world-space direction (from surfaces TOWARD the sun). If nil,
    // direction is derived from `getPosition()` for backward compatibility
    // with scenes that only call `setPosition` to aim the sun.
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

    /// Half-extent of the orthographic shadow frustum (cascadeCount==1 only),
    /// in world units. Smaller values give sharper shadows but a smaller
    /// covered area around the camera. Ignored when cascadeCount > 1.
    func setShadowRadius(_ radius: Float) { _shadowRadius = radius }

    /// Distance to lift the shadow eye along the light direction
    /// (cascadeCount==1 only). Must be larger than the tallest shadow caster's
    /// height above the focus point. Ignored when cascadeCount > 1.
    func setShadowLift(_ lift: Float) { _shadowLift = lift }

    /// World-space slack used by the shader's depth-compare epsilon. For
    /// cascades, this is cascade-0's slack; deeper cascades get a proportional
    /// scaling. Tune down for finer self-shadow detail; tune up if acne
    /// appears on flat receivers. Typical range: 0.05 – 1.0 world units.
    func setShadowWorldSlack(_ slack: Float) { _baseWorldSlack = slack }

    /// Number of CSM cascades (1...TFS_MAX_SHADOW_CASCADES). Setting to 1
    /// activates the legacy single-cascade sun-follow fast path (bit-identical
    /// to pre-CSM behavior).
    func setCascadeCount(_ n: Int) {
        _cascadeCount = max(1, min(n, Int(TFS_MAX_SHADOW_CASCADES)))
    }

    /// PSSM cascade-split blend factor (0 = uniform splits, 1 = logarithmic).
    /// Higher values concentrate more detail near the camera. 0.5 is the
    /// standard Microsoft recommendation; 0.7 for outdoor scenes wanting
    /// extra near-field detail.
    func setCascadeLambda(_ lambda: Float) { _cascadeLambda = lambda }

    /// Per-cascade shadow map resolution (square). 2048 is the default;
    /// bumping to 4096 quadruples per-cascade memory for 2× per-axis sharpness.
    func setShadowMapResolution(_ res: Int) { _shadowMapRes = res }

    /// Z-axis ortho padding multiplier for each cascade. Default 10× expands
    /// the cascade's depth range to include casters between the sun and the
    /// visible slice.
    func setCascadeZPadding(_ pad: Float) { _cascadeZPad = pad }

    /// Maximum world-space distance from the camera that cascades will cover.
    /// Receivers beyond this distance fall back to "fully lit" (cascade
    /// fallthrough in `Lighting::CalculateShadow`). Default 500 world units,
    /// tuned for flight-sim scenes where the camera's far plane is 1,000,000
    /// (to draw sky/horizon) but realistic shadow casters sit within ~500
    /// units of the camera.
    func setShadowMaxDistance(_ d: Float) { _shadowMaxDistance = d }

    private var _modelType: ModelType = .None

    init(name: String, lightType: LightType = Directional) {
        self.lightType = lightType
        super.init(name: name, modelType: .None)
        self.lightData.shadowTransformMatrix = shadowTranslate * shadowScale
    }

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
            updateShadowCascades()
        }
    }

    /// Build N FittedCascades against the active main camera and stash their
    /// matrices + per-cascade metadata into `lightData`. Single-cascade path
    /// (cascadeCount==1) is preserved as a fast path that uses the existing
    /// sun-follow ShadowCamera initializer — output is bit-identical to the
    /// pre-CSM implementation.
    private func updateShadowCascades() {
        guard let cam = CameraManager.CurrentCamera else { return }

        if _cascadeCount == 1 {
            // Legacy single-cascade fast path: bit-identical to pre-CSM behavior.
            let shadowCamera = ShadowCamera(direction: self.direction,
                                            focus: cam.getWorldPosition(),
                                            radius: _shadowRadius,
                                            lift: _shadowLift)
            let svp = shadowCamera.viewProjectionMatrix

            // Populate cascade-0 slot for the cascade-aware shader path.
            var oneMatrix = [svp]
            writeCascadeMatrices(into: &lightData.cascadeViewProjectionMatrices,
                                 from: oneMatrix)
            writeCascadeFloats(into: &lightData.cascadeSplitDepths,
                               from: [cam.far])
            writeCascadeFloats(into: &lightData.cascadeDepthRange,
                               from: [shadowCamera.depthRange])
            writeCascadeFloats(into: &lightData.cascadeWorldSlack,
                               from: [_baseWorldSlack])
            lightData.cascadeCount = 1
            _ = oneMatrix // silence unused-write warning paths

            // Legacy aliases for GBuffer.metal's sample_compare path.
            lightData.shadowViewProjectionMatrix = svp
            lightData.viewProjectionMatrix       = svp
            lightData.shadowDepthRange           = shadowCamera.depthRange
            lightData.shadowWorldSlack           = _baseWorldSlack
            return
        }

        // Multi-cascade path.
        let aspect: Float = {
            let sx = Renderer.ScreenSize.x
            let sy = Renderer.ScreenSize.y
            return (sx > 0 && sy > 0) ? Float(sx) / Float(sy) : 1
        }()

        // Cap shadow far at _shadowMaxDistance so cascade slices stay tight
        // even when the camera's actual far plane is millions of units away
        // (flight-sim sky/horizon rendering).
        let shadowFar = min(cam.far, _shadowMaxDistance)

        let cascades = ShadowCascadeFitting.fitCascades(
            cameraView: cam.viewMatrix,
            cameraFovYRadians: cam.fieldOfView.toRadians,
            cameraAspect: aspect,
            cameraNear: cam.near,
            cameraFar: shadowFar,
            lightDirection: self.direction,
            cascadeCount: _cascadeCount,
            lambda: _cascadeLambda,
            shadowMapResolution: _shadowMapRes,
            zPaddingWorldUnits: _cascadeZPad
        )

        #if DEBUG
        debugLogCascades(cascades: cascades, cameraView: cam.viewMatrix)
        #endif

        // Reference cascade-0 extent for per-cascade slack scaling.
        let referenceRadius = max(cascades[0].camera.orthoHalfExtentX, 1e-4)

        let vpMatrices: [matrix_float4x4] = cascades.map { $0.camera.viewProjectionMatrix }
        let splitDepths: [Float]          = cascades.map { $0.splitFar }
        let depthRanges: [Float]          = cascades.map { $0.camera.depthRange }
        let worldSlacks: [Float]          = cascades.map { cascade in
            _baseWorldSlack * (cascade.camera.orthoHalfExtentX / referenceRadius)
        }

        writeCascadeMatrices(into: &lightData.cascadeViewProjectionMatrices, from: vpMatrices)
        writeCascadeFloats  (into: &lightData.cascadeSplitDepths,            from: splitDepths)
        writeCascadeFloats  (into: &lightData.cascadeDepthRange,             from: depthRanges)
        writeCascadeFloats  (into: &lightData.cascadeWorldSlack,             from: worldSlacks)
        lightData.cascadeCount = UInt32(cascades.count)

        // Legacy aliases mirror cascade 0 for the GBuffer.metal sample_compare
        // path (until that path is refactored cascade-aware).
        let cascade0VP = cascades[0].camera.viewProjectionMatrix
        lightData.shadowViewProjectionMatrix = cascade0VP
        lightData.viewProjectionMatrix       = cascade0VP
        lightData.shadowDepthRange           = cascades[0].camera.depthRange
        lightData.shadowWorldSlack           = worldSlacks[0]
    }

    // MARK: - Debug logging

    private var _lastDebugLogTime: TimeInterval = 0

    /// Print cascade-0 matrix + per-cascade depth ranges/splits once per second.
    /// Compare these against expected values to diagnose cascade fitting bugs.
    private func debugLogCascades(cascades: [FittedCascade], cameraView: float4x4) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - _lastDebugLogTime > 1.0 else { return }
        _lastDebugLogTime = now

        let c0 = cascades[0]
        let vp = c0.camera.viewProjectionMatrix

        let cameraInverse = cameraView.inverse
        let camPosWorld   = cameraInverse.columns.3
        // Camera forward axis in world space = cameraInverse rotation applied to view-space +Z.
        let camForward    = (cameraInverse * float4(0, 0, 1, 0)).xyz
        // Sphere center for cascade 0 (where the cascade ortho is anchored).
        let sphereCenter4 = cameraInverse * float4(0, 0, (0.01 + 62.6) * 0.5, 1)
        let sphereCenter  = float3(sphereCenter4.x, sphereCenter4.y, sphereCenter4.z)

        // Probe: where does the CAMERA's world position land in cascade 0?
        // This should always be near (0, 0, ~0.5) — the camera is at the
        // back-edge of the cascade slice (sphere center is forward of camera).
        let camClip = vp * float4(camPosWorld.x, camPosWorld.y, camPosWorld.z, 1)
        let camNDC  = camClip.xyz / camClip.w

        // Probe: ground point directly below the camera (where the F-22's
        // shadow lives). Should be inside cascade 0 (uv in [-1, 1]) at all times.
        let groundClip = vp * float4(camPosWorld.x, 0, camPosWorld.z, 1)
        let groundNDC  = groundClip.xyz / groundClip.w

        print(String(format: """
        [CSM Debug] cam=(%.1f, %.1f, %.1f) fwd=(%.3f, %.3f, %.3f) lightDir=(%.3f, %.3f, %.3f)
          Sphere0 center world: (%.1f, %.1f, %.1f)
          Cascade splits (view-z): %@
          Cascade depth ranges:     %@
          Cascade halfExtentX:      %@
          C0 NDC of camera:    uv=(%.3f, %.3f) z=%.4f
          C0 NDC of ground-under-cam: uv=(%.3f, %.3f) z=%.4f
        """,
                     camPosWorld.x, camPosWorld.y, camPosWorld.z,
                     camForward.x, camForward.y, camForward.z,
                     direction.x, direction.y, direction.z,
                     sphereCenter.x, sphereCenter.y, sphereCenter.z,
                     cascades.map { String(format: "%.1f", $0.splitFar) }.joined(separator: ", "),
                     cascades.map { String(format: "%.1f", $0.camera.depthRange) }.joined(separator: ", "),
                     cascades.map { String(format: "%.1f", $0.camera.orthoHalfExtentX) }.joined(separator: ", "),
                     camNDC.x, camNDC.y, camNDC.z,
                     groundNDC.x, groundNDC.y, groundNDC.z))
    }

    // MARK: - Homogeneous-tuple bridging helpers
    //
    // C-imported `T arr[N]` arrives in Swift as a tuple `(T, T, T, T)` with
    // no integer subscript at runtime. The pointer-rebind trick is the
    // standard escape hatch (also used in Apple's Metal samples for
    // point-light arrays). If TFS_MAX_SHADOW_CASCADES ever changes, both the
    // tuple types (auto-generated by the C importer) and the `capacity`
    // arguments below must be updated together.

    /// Write up to `TFS_MAX_SHADOW_CASCADES` (= 4) matrices into a homogeneous
    /// 4-element tuple imported from C. The tuple's arity matches the cascade
    /// cap in `TFSCommon.h`.
    private func writeCascadeMatrices(
        into tuple: inout (matrix_float4x4, matrix_float4x4, matrix_float4x4, matrix_float4x4),
        from source: [matrix_float4x4]
    ) {
        withUnsafeMutablePointer(to: &tuple) { tuplePtr in
            tuplePtr.withMemoryRebound(to: matrix_float4x4.self, capacity: 4) { matPtr in
                for i in 0..<min(source.count, 4) {
                    matPtr[i] = source[i]
                }
            }
        }
    }

    /// Same pattern as `writeCascadeMatrices` but for `Float` tuples used by
    /// the per-cascade split-depth, depth-range, and world-slack arrays. The
    /// 4-element arity again mirrors `TFS_MAX_SHADOW_CASCADES`.
    private func writeCascadeFloats(
        into tuple: inout (Float, Float, Float, Float),
        from source: [Float]
    ) {
        withUnsafeMutablePointer(to: &tuple) { tuplePtr in
            tuplePtr.withMemoryRebound(to: Float.self, capacity: 4) { fPtr in
                for i in 0..<min(source.count, 4) { fPtr[i] = source[i] }
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
