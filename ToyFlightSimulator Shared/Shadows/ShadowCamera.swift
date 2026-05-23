//
//  ShadowCamera.swift
//  ToyFlightSimulator
//

import MetalKit

/// Per-frame "synthesis camera" used to render a directional light's shadow map.
/// Generalized to either single-cascade sun-follow (legacy) or per-cascade CSM.
/// The cascade-fit initializer accepts the lightView and ortho bounds already
/// computed by `ShadowCascadeFitting`.
struct ShadowCamera {
    let viewMatrix:       float4x4
    let projectionMatrix: float4x4

    /// Far − near of the ortho frustum, in world units. Used by the shader's
    /// depth-compare epsilon: NDC epsilon = worldSlack / depthRange.
    let depthRange:       Float

    var viewProjectionMatrix: float4x4 { projectionMatrix * viewMatrix }

    /// Legacy single-cascade sun-follow constructor. The shadow eye is lifted
    /// `lift` units along `direction` from `focus`, looking back at `focus`.
    /// `up = Y_AXIS` matches all other camera/light conventions; degenerate when
    /// `direction` is exactly parallel to Y_AXIS (callers avoid pointing the sun
    /// straight up). Forward-Z ortho (see TiledDeferredDepthStencils.swift:10-13).
    init(direction: float3, focus: float3, radius: Float, lift: Float) {
        let eye = focus + direction * lift
        self.viewMatrix = Transform.look(eye: eye, target: focus, up: Y_AXIS)
        let near: Float = 1
        let far:  Float = 2 * lift
        self.projectionMatrix = Transform.orthographicProjection(-radius, radius,
                                                                 -radius, radius,
                                                                 near, far)
        self.depthRange = far - near
    }

    /// Cascade-fit constructor (CSM). `lightView` and the ortho bounds come from
    /// `ShadowCascadeFitting.fitCascades`.
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
