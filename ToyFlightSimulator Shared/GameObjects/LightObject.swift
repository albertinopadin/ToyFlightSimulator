//
//  LightObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/22.
//

import MetalKit

class LightObject: GameObject {
    // Lights live in LightManager, not in SceneManager's batched collections.
    override var objectType: GameObjectType { .none }
    
    // A directional light with no explicit direction derives it from its position,
    // so moving the node would turn the light. With an explicit direction (setLightDirection)
    // it is an ordinary node. A point light always is: its position is where it shines from.
    override var shiftsWithFloatingOrigin: Bool {
        lightType != Directional || _explicitDirection != nil
    }

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
    
    private var _cascadeSnapPhases: [double2] = []     // per cascade: where the texel grid sits along the light's
                                                       // X and Y axes, meters, each in [0, texel size)
    private var _cascadeTexelSizes: [Float] = []       // per cascade: texel size the last fit used, meters

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
    /// Side effect on a directional light: from this call on the node's position no longer aims
    /// the light, so the node shifts with the floating origin (`shiftsWithFloatingOrigin`) and a
    /// later `setPosition` changes nothing in the lighting. A point light ignores the direction.
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
        // The shadow cascades are not fitted here: GameScene.update() fits them after the whole
        // traversal (fitShadowCascades). At this point a camera parented to a node that comes
        // later in the scene's direct children still has last tick's world matrix.
    }
    
    /// What `ShadowCascadeFitting.fitCascades` needs from a camera, copied out as a value.
    /// Take it after the scene traversal (`GameScene.update()` does, after `super.update()`):
    /// a parented camera receives its parent's world matrix only when the parent updates, so
    /// earlier in the tick its view matrix can still be last tick's.
    static func shadowCameraSnapshot(of camera: Camera) -> ShadowCascadeFitting.CameraSnapshot {
        // Derive vertical FOV and aspect from the live camera. fieldOfView is
        // stored in degrees; aspect is read off the projection matrix
        // (columns.1.y = 1/tan(fovY/2); columns.0.x = that / aspect) so it always
        // matches what the camera is actually rendering with, reverse-Z or not.
        let fovY = camera.fieldOfView.toRadians
        let proj = camera.projectionMatrix
        let xs = proj.columns.0.x
        let ys = proj.columns.1.y
        let aspect = (xs != 0) ? (ys / xs) : Renderer.AspectRatio

        return ShadowCascadeFitting.CameraSnapshot(viewMatrix: camera.viewMatrix,
                                                   near:       camera.near,
                                                   far:        camera.far,
                                                   fovY:       fovY,
                                                   aspect:     aspect)
    }
    
    /// Fits this light's shadow cascades to `cameraSnapshot` and writes the result into
    /// `lightData`: cascade count, view-projection matrices, split depths and depth ranges. It
    /// also records the texel sizes the fit used, which `shiftShadowSnapPhases` needs. Does
    /// nothing for a point light. The camera is a parameter, not `CameraManager.CurrentCamera`,
    /// so the caller decides which camera state is fitted and a test can pass any snapshot.
    ///
    /// Order within a tick: `GameScene.update()` calls this after the traversal, and
    /// `SceneManager.updateFloatingOrigin` runs after that. The fit must come first. On a shift
    /// tick it then pairs the camera and the snap phases from before the shift, and the next
    /// tick's fit pairs the shifted camera with the shifted phases.
    public func fitShadowCascades(to cameraSnapshot: ShadowCascadeFitting.CameraSnapshot) {
        guard self.lightType == Directional else { return }
        
        let fit = ShadowCascadeFitting.fitCascades(camera:              cameraSnapshot,
                                                   lightDirection:      self.direction,
                                                   shadowMapResolution: _shadowMapRes,
                                                   cascadeCount:        _cascadeCount,
                                                   lambda:              _cascadeLambda,
                                                   shadowMaxDistance:   _shadowMaxDistance,
                                                   zPaddingWorldUnits:  _cascadeZPad,
                                                   cascadeSnapPhases:   _cascadeSnapPhases)
        
        _cascadeTexelSizes = fit.texelSizes

        // Split-far depths are in view-space (scaled) units; convert to world
        // units for shader consumption (the fragment computes fragViewSpaceDepth
        // in world units via distance(worldPos, cameraPos)). Same scale
        // extraction as in boundingSphereForSlice.
        let c0 = cameraSnapshot.viewMatrix.inverse.columns.0
        let cameraScale = simd_length(simd_float3(c0.x, c0.y, c0.z))

        lightData.cascadeCount = UInt32(_cascadeCount)
        writeCascadeMatrices(into: &lightData.cascadeViewProjectionMatrices,
                             from: fit.cascades.map { $0.viewProjectionMatrix })
        writeCascadeFloats(into: &lightData.cascadeSplitDepths,
                           from: fit.splitFars.map { $0 * cameraScale })
        writeCascadeFloats(into: &lightData.cascadeDepthRanges,
                           from: fit.cascades.map { $0.depthRange })
    }
    
    public func shiftShadowSnapPhases(by shiftOffset: float3) {
        guard lightType == Directional && !_cascadeTexelSizes.isEmpty /* no fit has run yet */ else { return }
        _cascadeSnapPhases = ShadowCascadeFitting.snapPhasesAfterOriginShift(cascadeSnapPhases: _cascadeSnapPhases,
                                                                             texelSizes: _cascadeTexelSizes,
                                                                             lightDirection: self.direction,
                                                                             shiftOffset: shiftOffset)
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

    /// Sets the falloff radius AND scales the node so the icosahedron volume mesh contains
    /// the radius-sized sphere of influence. `update()` copies the node's modelMatrix into
    /// `lightData.modelMatrix`, which every volume vertex path consumes (PointLights.metal
    /// light_mask_vertex / deferred_point_lighting_vertex, TiledDeferredPointLight.metal) —
    /// the mesh-size calibration lives here, next to the asset it describes, not in MSL.
    /// This setter owns the node scale for point lights; don't also call setScale on them.
    public func setLightRadius(_ radius: Float) {
        self.lightData.radius = radius
        if lightType == Point {
            self.setScale(radius / IcosahedronMesh.inscribedRadius)
        }
    }
    public func getLightRadius() -> Float { return self.lightData.radius }
}
