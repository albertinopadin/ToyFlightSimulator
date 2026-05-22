//
//  ShadowCascadeFitting.swift
//  ToyFlightSimulator
//
//  Pure math for Cascaded Shadow Maps: split the main camera's view frustum
//  into N depth slices, build a tightly-fit orthographic shadow camera per
//  slice, and snap each cascade's extents to texel boundaries to kill shimmer.
//
//  Standard CSM algorithm; see https://learnopengl.com/Guest-Articles/2021/CSM
//  and Microsoft PSSM whitepaper. Two adaptations for this project:
//    1. Metal NDC z ∈ [0, 1] (not [-1, 1] like OpenGL), so frustum-corner
//       unprojection uses NDC z ∈ {0, 1} directly.
//    2. The main camera's `Transform.perspectiveProjection` is reverse-Z, but
//       per-cascade orthos stay forward-Z so the existing shader's depth-
//       compare convention is preserved.
//

import simd

/// One fitted cascade: a ShadowCamera (view + ortho projection) plus the
/// view-space depth at which this cascade ends (its "split far").
struct FittedCascade {
    let camera: ShadowCamera
    let splitFar: Float
}

enum ShadowCascadeFitting {

    // MARK: - Public entry point

    /// Build N `FittedCascade`s, one per cascade, fitted to N depth-slices of
    /// the main camera's view frustum.
    ///
    /// - Parameters:
    ///   - cameraView: Main camera's view matrix.
    ///   - cameraFovYRadians: Main camera's vertical field of view.
    ///   - cameraAspect: Main camera's aspect ratio (width / height).
    ///   - cameraNear: Main camera's near plane.
    ///   - cameraFar: Main camera's far plane (= deepest cascade's far).
    ///   - lightDirection: World-space unit vector FROM surfaces TOWARD the sun.
    ///   - cascadeCount: Number of cascades (1...TFS_MAX_SHADOW_CASCADES).
    ///   - lambda: PSSM blend (0 = uniform, 1 = logarithmic). 0.5 = standard.
    ///   - shadowMapResolution: Per-cascade texture size in texels (square).
    ///     Used for texel-snapping (kills shimmer).
    ///   - zPaddingWorldUnits: Z-axis expansion (in world units) added to
    ///     each side of the per-cascade ortho box to include casters behind
    ///     the visible slice. Replaces the earlier multiplicative-padding
    ///     approach, which produced unpredictably huge depth ranges when the
    ///     AABB straddled 0 in light view z (e.g., near-corner z=0.5,
    ///     far-corner z=-50 → ×10 padding → [-515, +524] depth range,
    ///     leaving the F-22's narrow depth window indistinguishable in
    ///     32-bit float precision after the projective divide).
    static func fitCascades(cameraView: float4x4,
                            cameraFovYRadians: Float,
                            cameraAspect: Float,
                            cameraNear: Float,
                            cameraFar: Float,
                            lightDirection: float3,
                            cascadeCount: Int,
                            lambda: Float = 0.5,
                            shadowMapResolution: Int,
                            zPaddingWorldUnits: Float = 100) -> [FittedCascade] {

        let splitDepths = computeSplitDepths(near: cameraNear,
                                             far: cameraFar,
                                             count: cascadeCount,
                                             lambda: lambda)

        var result: [FittedCascade] = []
        result.reserveCapacity(cascadeCount)

        // cameraView's inverse maps view-space points (e.g., the slice's
        // bounding-sphere center on the view forward axis) into world space.
        let cameraInverse = cameraView.inverse

        for i in 0..<cascadeCount {
            let sliceNear = i == 0 ? cameraNear : splitDepths[i - 1]
            let sliceFar  = splitDepths[i]

            // Bounding sphere of this slice (rotation-invariant).
            let (sphereCenterWorld, radius) = boundingSphereForSlice(
                cameraInverse: cameraInverse,
                fovYRadians: cameraFovYRadians,
                aspect: cameraAspect,
                sliceNear: sliceNear,
                sliceFar: sliceFar
            )

            let cascade = fitOrthoToSphere(
                sphereCenter: sphereCenterWorld,
                radius: radius,
                lightDirection: lightDirection,
                shadowMapResolution: shadowMapResolution,
                zPaddingWorldUnits: zPaddingWorldUnits
            )
            
            print("[boundingSphereForSlice] center world for \n\(i)th cascade: \(sphereCenterWorld)")

            result.append(FittedCascade(camera: cascade, splitFar: sliceFar))
        }
        return result
    }

    // MARK: - Cascade split distances (PSSM / practical split scheme)

    /// Returns N "far" depths, one per cascade. Cascade i covers
    /// `[i == 0 ? near : depths[i-1], depths[i]]`. The last entry equals `far`
    /// exactly (forced after the powf computation to handle float drift).
    ///
    /// PSSM hybrid: lerp between uniform and logarithmic splits.
    static func computeSplitDepths(near: Float,
                                   far: Float,
                                   count: Int,
                                   lambda: Float) -> [Float] {
        var depths: [Float] = []
        depths.reserveCapacity(count)
        let range = far - near
        let ratio = far / max(near, 1e-4)
        for i in 1...count {
            let p = Float(i) / Float(count)
            let logSplit = near * powf(ratio, p)             // logarithmic
            let uniformSplit = near + range * p              // uniform
            let practical = lambda * logSplit + (1 - lambda) * uniformSplit
            depths.append(practical)
        }
        depths[count - 1] = far
        return depths
    }

    // MARK: - Bounding sphere of a frustum slice

    /// Compute the bounding sphere of the main camera's frustum slice between
    /// `sliceNear` and `sliceFar`. Returns (sphereCenterWorld, radius).
    ///
    /// Why a sphere instead of an AABB-of-corners:
    /// The sphere's radius depends ONLY on FOV/aspect/sliceNear/sliceFar —
    /// it's invariant to the camera's orientation. The cascade ortho box
    /// built from this sphere therefore has a stable size frame-to-frame
    /// regardless of how the player rotates, so the texel grid snaps to
    /// consistent world-space positions and shadows don't shimmer.
    ///
    /// Sphere geometry: the center sits on the view forward axis at the
    /// slice's midpoint. The radius reaches to the far-plane corners (which
    /// are farther from the midpoint than the near-plane corners). For
    /// typical slices the far corners are the worst case; we use the simple
    /// "center = midpoint, radius = far-corner distance" formula rather than
    /// the slightly tighter optimal sphere — the cost is at most ~20%
    /// excess area, negligible vs the rotation-stability gain.
    static func boundingSphereForSlice(cameraInverse: float4x4,
                                       fovYRadians: Float,
                                       aspect: Float,
                                       sliceNear: Float,
                                       sliceFar: Float) -> (centerWorld: float3, radius: Float) {
        let midZ = (sliceNear + sliceFar) * 0.5
        let halfRangeZ = (sliceFar - sliceNear) * 0.5

        // Far plane half-extents in (camera) view space.
        let tanHalfFov = tanf(fovYRadians * 0.5)
        let farHalfH = sliceFar * tanHalfFov
        let farHalfW = farHalfH * aspect

        // Bounding sphere radius in (camera) view space.
        let radiusView = sqrtf(halfRangeZ * halfRangeZ
                             + farHalfH * farHalfH
                             + farHalfW * farHalfW)

        // The camera may be parented to a scaled node — e.g., FlightboxWithPhysics
        // attaches its camera to an F-22 with scale=3.0, so the camera's
        // modelMatrix (= cameraInverse) ends up with scale 3. To keep the cascade
        // ortho in WORLD units (the same coordinate system as the light view), we
        // need both the sphere center and the radius in world units.
        //
        // The center is automatically correct: `cameraInverse * (0, 0, midZ, 1)`
        // bakes the scale into the translation, so the resulting world point is
        // `cameraWorld + worldForwardUnit * (midZ * cameraScale)` — the slice
        // midpoint in world space. The radius, however, is currently a pure
        // view-space length and needs the scale applied explicitly.
        let cameraScale = simd_length(simd_float3(cameraInverse.columns.0.x,
                                                  cameraInverse.columns.0.y,
                                                  cameraInverse.columns.0.z))
        let radius = radiusView * cameraScale

        let centerView = float4(0, 0, midZ, 1)
        let centerWorld4 = cameraInverse * centerView
        let centerWorld = float3(centerWorld4.x, centerWorld4.y, centerWorld4.z)

        return (centerWorld, radius)
    }

    // MARK: - Fit ortho box to a bounding sphere

    /// Build a `ShadowCamera` whose orthographic frustum tightly contains the
    /// world-space sphere `(sphereCenter, radius)` from the light's view.
    ///
    /// **Stable texel-snap (kills shadow swimming):**
    /// The naive approach is to build lightView with `eye = sphereCenter + lightDir`
    /// and then snap the sphere center's projection in light view to a texel grid.
    /// That doesn't work — the sphere center *always* projects to lv = (0, 0, 1)
    /// in that lightView (because eye is at center + lightDir), so the snap is
    /// a no-op. Meanwhile, every world point's lv coords change continuously
    /// with the camera, producing sub-texel-precision shadow shifts → swim.
    ///
    /// Correct approach: snap `sphereCenter` in WORLD space to a grid aligned
    /// with light-view's xy basis axes, BEFORE building lightView. Then the
    /// `eye = snappedSphereCenter + lightDir` only moves in integer-texel
    /// increments as the camera moves, so the cascade view-projection matrix
    /// only changes in integer-texel increments. A fixed world point maps to
    /// the SAME shadow map texel until the camera crosses a full-texel boundary.
    static func fitOrthoToSphere(sphereCenter: float3,
                                 radius: Float,
                                 lightDirection: float3,
                                 shadowMapResolution: Int,
                                 zPaddingWorldUnits: Float) -> ShadowCamera {
        // Light-view basis axes expressed in WORLD coordinates. These depend
        // only on lightDirection + up, not on the camera position. Computing
        // them here (rather than via Transform.look) gives us the axes for
        // the snap projection.
        //
        // light forward (= -lightDir, the direction light propagates in world)
        let lightLen = simd_length(lightDirection)
        let zWorld = lightLen > .ulpOfOne ? -lightDirection / lightLen : float3(0, -1, 0)
        // light right = normalize(cross(up, forward))
        let xUnnorm = simd_cross(Y_AXIS, zWorld)
        let xWorld: float3
        if simd_length_squared(xUnnorm) > 1e-12 {
            xWorld = simd_normalize(xUnnorm)
        } else {
            // Degenerate: sun straight up. Fall back to world +X.
            xWorld = float3(1, 0, 0)
        }
        // light up = cross(forward, right)
        let yWorld = simd_cross(zWorld, xWorld)

        // World-space texel-snap. The texel grid in light view is at multiples
        // of `texelSize`. By snapping sphereCenter's projection onto xWorld /
        // yWorld to that grid, we ensure the resulting `eye` only translates
        // in integer-texel steps. The cascade VP therefore only changes in
        // integer-texel steps between frames.
        let texelSize = (2 * radius) / Float(shadowMapResolution)
        let centerProjX = simd_dot(xWorld, sphereCenter)
        let centerProjY = simd_dot(yWorld, sphereCenter)
        let snappedProjX = floor(centerProjX / texelSize) * texelSize
        let snappedProjY = floor(centerProjY / texelSize) * texelSize
        // The shift to apply, expressed in world space. shiftX/shiftY are in
        // [-texelSize, 0] (floor rounds down). The shift is along the
        // (orthogonal) xWorld/yWorld axes, so it doesn't disturb the sphere
        // center's position along zWorld (the light-depth direction).
        let shiftWorld = (snappedProjX - centerProjX) * xWorld
                       + (snappedProjY - centerProjY) * yWorld
        let snappedSphereCenter = sphereCenter + shiftWorld

        // Build lightView with eye at the snapped center + lightDir. Because
        // snappedSphereCenter only moves in integer-texel increments, this
        // lightView only translates in integer-texel increments.
        let lightView = Transform.look(eye: snappedSphereCenter + lightDirection,
                                       target: snappedSphereCenter,
                                       up: Y_AXIS)

        // In this lightView, the snapped sphere center is at lv ≈ (0, 0, 1)
        // by construction. The cascade ortho is therefore symmetric ±radius
        // around 0 in xy, and ±radius around 1 in z (plus padding for casters
        // above the visible slice).
        let minX = -radius
        let maxX =  radius
        let minY = -radius
        let maxY =  radius
        let minZ = 1.0 - radius - zPaddingWorldUnits
        let maxZ = 1.0 + radius + zPaddingWorldUnits

        return ShadowCamera(lightView: lightView,
                            orthoMinX: minX, orthoMaxX: maxX,
                            orthoMinY: minY, orthoMaxY: maxY,
                            orthoNearZ: minZ, orthoFarZ: maxZ)
    }
}
