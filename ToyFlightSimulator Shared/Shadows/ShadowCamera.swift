//
//  ShadowCamera.swift
//  ToyFlightSimulator
//

import MetalKit

/// Per-frame "synthesis camera" used to render a directional light's shadow map.
/// Decoupled from the LightObject's own pose: the LightObject defines a direction
/// (pointing from surfaces toward the sun); the ShadowCamera is positioned to
/// keep the visible region inside a finite orthographic frustum.
///
/// Two construction paths:
/// 1. Legacy single-cascade sun-follow: `init(direction:focus:radius:lift:)`
///    produces a symmetric ortho box around `focus`. Used when LightObject's
///    cascade count is 1.
/// 2. CSM per-cascade fit: `init(lightView:orthoMinX:...:orthoFarZ:)` takes a
///    precomputed light-view matrix and an axis-aligned ortho box (typically
///    from `ShadowCascadeFitting.fitOrthoToCorners`). Used per-cascade when
///    LightObject's cascade count > 1.
struct ShadowCamera {
    let viewMatrix: float4x4
    let projectionMatrix: float4x4

    /// World-units depth range of the ortho projection (`far − near`). Used by
    /// the shader to derive an NDC-space depth-compare epsilon from a world-
    /// space slack: `ndcEpsilon = worldSlack / depthRange`.
    let depthRange: Float

    /// Half-width of the orthographic projection on the X axis, in world units.
    /// Useful for proportionally scaling per-cascade shader knobs (e.g.
    /// depth-compare slack) across cascades of different sizes.
    var orthoHalfExtentX: Float {
        // For our ortho matrix, col0.x = 2 / (right - left), so
        // half-extent = 1 / col0.x.
        return 1 / projectionMatrix.columns.0.x
    }

    var viewProjectionMatrix: float4x4 { projectionMatrix * viewMatrix }

    /// Legacy single-cascade convenience initializer. Symmetric ortho centered
    /// on `focus`, lifted along `direction` by `lift` world units.
    ///
    /// `up = Y_AXIS` matches all other camera/light conventions in the codebase.
    /// Degenerate when `direction` is exactly parallel to Y_AXIS; callers should
    /// avoid pointing the sun straight up.
    init(direction: float3, focus: float3, radius: Float, lift: Float) {
        let eye = focus + direction * lift
        self.viewMatrix = Transform.look(eye: eye, target: focus, up: Y_AXIS)
        // Forward-Z ortho (see TiledDeferredDepthStencils.swift:10-13 comment
        // for why the shadow path is intentionally not reverse-Z).
        self.projectionMatrix = Transform.orthographicProjection(-radius, radius,
                                                                 -radius, radius,
                                                                 1, 2 * lift)
        self.depthRange = 2 * lift - 1
    }

    /// CSM cascade-fit initializer. Takes a precomputed light-view matrix and
    /// an axis-aligned ortho box. The box's X/Y extents are typically derived
    /// from the AABB of the main camera's sub-frustum corners (in light view
    /// space); the Z extents are padded to capture shadow casters behind the
    /// visible slice. See `ShadowCascadeFitting.fitOrthoToCorners`.
    init(lightView: float4x4,
         orthoMinX: Float, orthoMaxX: Float,
         orthoMinY: Float, orthoMaxY: Float,
         orthoNearZ: Float, orthoFarZ: Float) {
        self.viewMatrix = lightView
        self.projectionMatrix = Transform.orthographicProjection(orthoMinX, orthoMaxX,
                                                                 orthoMinY, orthoMaxY,
                                                                 orthoNearZ, orthoFarZ)
        self.depthRange = orthoFarZ - orthoNearZ
    }
}
