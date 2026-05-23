//
//  ShadowCascadeFitting.swift
//  ToyFlightSimulator
//
//  Cascaded Shadow Map fitting: PSSM split scheme, rotation-invariant
//  bounding-sphere fit, and world-space texel snap. See
//  plans/claude/cascaded_shadow_maps.md for the design rationale and the
//  external references each step is validated against.
//

import simd

enum ShadowCascadeFitting {

    /// Minimal value-type snapshot of what `fitCascades` reads from the camera.
    /// Avoids coupling the Shadows folder to the `Camera` class.
    struct CameraSnapshot {
        let viewMatrix: float4x4
        let near:       Float
        let far:        Float
        let fovY:       Float   // vertical field of view, radians
        let aspect:     Float   // width / height
    }

    struct CascadeFit {
        let cascades:  [ShadowCamera]
        let splitFars: [Float]   // per-cascade far depth, view-space (scaled) units
    }

    // MARK: - PSSM "Practical Split Scheme" (Microsoft / Engel ShaderX5)
    //
    // splitFar_i = uniform_i * (1 - λ) + log_i * λ
    //   uniform_i = near + (far - near) * (i + 1) / N
    //   log_i     = near * (far / near) ^ ((i + 1) / N)
    //
    // λ=0 → uniform (wastes near, good far); λ=1 → logarithmic (degenerate near 0
    // when `near` is very small); λ=0.5 hits the sweet spot for typical scenes.
    // Returns N split *far* depths; split 0's near is the camera near.
    static func computeSplits(near: Float, far: Float,
                              cascadeCount: Int, lambda: Float) -> [Float] {
        precondition(cascadeCount >= 1)
        precondition(near > 0 && far > near)
        let n = Float(cascadeCount)
        var splits: [Float] = []
        splits.reserveCapacity(cascadeCount)
        for i in 0..<cascadeCount {
            let p = Float(i + 1) / n
            let uniform = near + (far - near) * p
            let log     = near * powf(far / near, p)
            splits.append(uniform * (1 - lambda) + log * lambda)
        }
        return splits
    }

    // MARK: - Bounding sphere of a frustum slice
    //
    // Why a sphere, not an AABB of the 8 frustum corners: the sphere's radius
    // depends only on FOV/aspect/slice-near/slice-far — *not* on the camera's
    // rotation. As the camera spins, AABB extents change because the corners
    // rotate through the AABB; a sphere is rotation-invariant. Without this,
    // texel snap can't hold a stable edge (Valient / Killzone 2).
    //
    // Center is the slice midpoint along the camera's forward axis, transformed
    // to world by the inverse view matrix. Radius is computed in view space then
    // scaled by the camera's world scale: the AttachedCamera is parented to a
    // scale-N aircraft, so view-space units are 1/N of world units.
    static func boundingSphereForSlice(cameraInverse: float4x4,
                                       fovYRadians: Float,
                                       aspect: Float,
                                       sliceNear: Float,
                                       sliceFar: Float)
                                       -> (centerWorld: float3, radius: Float) {
        let midZ       = (sliceNear + sliceFar) * 0.5
        let halfRangeZ = (sliceFar  - sliceNear) * 0.5
        let tanHalfFov = tanf(fovYRadians * 0.5)
        let farHalfH   = sliceFar * tanHalfFov
        let farHalfW   = farHalfH * aspect

        let radiusView = sqrtf(halfRangeZ * halfRangeZ
                             + farHalfH   * farHalfH
                             + farHalfW   * farHalfW)

        // Inverse-view columns are the world-space camera basis vectors; their
        // length equals the accumulated parent-chain scale.
        let c0 = cameraInverse.columns.0
        let cameraScale = simd_length(simd_float3(c0.x, c0.y, c0.z))
        let radius = radiusView * cameraScale

        let centerWorld4 = cameraInverse * float4(0, 0, midZ, 1)
        return (float3(centerWorld4.x, centerWorld4.y, centerWorld4.z), radius)
    }

    // MARK: - Per-cascade fit (sphere + world-space snap)
    static func fitCascades(camera: CameraSnapshot,
                            lightDirection: float3,
                            shadowMapResolution: Int,
                            cascadeCount: Int,
                            lambda: Float,
                            shadowMaxDistance: Float,
                            zPaddingWorldUnits: Float) -> CascadeFit {
        precondition(cascadeCount >= 1)

        // Cap the cascade-fitting far. The flight-sim camera has `far` in the
        // millions to render the horizon; running PSSM over [near, far] collapses
        // cascade 0 to hundreds of thousands of world units wide. Decouple shadow
        // reach from sky reach.
        let near = camera.near
        let far  = min(camera.far, shadowMaxDistance)
        let splitFars = computeSplits(near: near, far: far,
                                      cascadeCount: cascadeCount, lambda: lambda)

        let cameraInverse = camera.viewMatrix.inverse

        // World-space light basis. Stable across frames: depends only on the
        // (constant) light direction and global up. The light looks toward the
        // focus along -direction. Degenerate when the light is exactly overhead;
        // fall back to world +X for the basis x-axis.
        let zWorld = -lightDirection
        var xCandidate = simd_cross(Y_AXIS, zWorld)
        if simd_length_squared(xCandidate) < 1e-6 {
            xCandidate = simd_cross(float3(1, 0, 0), zWorld)
        }
        let xWorld = simd_normalize(xCandidate)
        let yWorld = simd_cross(zWorld, xWorld)

        var cascades: [ShadowCamera] = []
        cascades.reserveCapacity(cascadeCount)

        var prevFar = near
        for i in 0..<cascadeCount {
            let sliceFar = splitFars[i]
            let (sphereCenter, radius) = boundingSphereForSlice(
                cameraInverse: cameraInverse,
                fovYRadians:   camera.fovY,
                aspect:        camera.aspect,
                sliceNear:     prevFar,
                sliceFar:      sliceFar)
            prevFar = sliceFar

            // World-space texel snap. Project the sphere center onto the light
            // basis axes, snap those scalar projections to integer multiples of
            // the texel size, reapply as a world-space shift. The snap MUST be in
            // world space — doing it in light view evaluates to a no-op because
            // the snap's frame of reference is itself derived from the value being
            // snapped.
            let texelSize = (2 * radius) / Float(shadowMapResolution)
            let projX = simd_dot(xWorld, sphereCenter)
            let projY = simd_dot(yWorld, sphereCenter)
            let snappedProjX = floor(projX / texelSize) * texelSize
            let snappedProjY = floor(projY / texelSize) * texelSize
            let shift = (snappedProjX - projX) * xWorld
                      + (snappedProjY - projY) * yWorld
            let snappedCenter = sphereCenter + shift

            // Light view: eye at center + direction (looking down toward
            // surfaces), target the snapped center.
            let eye = snappedCenter + lightDirection * radius
            let lightView = Transform.look(eye: eye, target: snappedCenter, up: Y_AXIS)

            // Ortho extents: [-radius, +radius] on X/Y. Additive z-padding so
            // casters slightly outside the sphere still fit. Additive (not the
            // LearnOpenGL multiplicative zMult=10 trick) so it stays bounded when
            // the depth range straddles 0.
            let halfExtent = radius
            let nearZ: Float = -zPaddingWorldUnits
            let farZ:  Float = 2 * radius + zPaddingWorldUnits

            cascades.append(ShadowCamera(
                lightView:  lightView,
                orthoMinX: -halfExtent, orthoMaxX: halfExtent,
                orthoMinY: -halfExtent, orthoMaxY: halfExtent,
                orthoNearZ: nearZ,      orthoFarZ: farZ))
        }

        return CascadeFit(cascades: cascades, splitFars: splitFars)
    }
}
