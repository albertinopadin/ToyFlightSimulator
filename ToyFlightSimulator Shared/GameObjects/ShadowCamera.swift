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
/// Sun-follow construction: each frame, compute against the main camera so the
/// shadow coverage tracks the player. See `LightObject.update()`.
struct ShadowCamera {
    /// Unit vector from the focus point toward the sun. The shadow camera is
    /// positioned `lift` units along this direction from `focus`.
    let direction: float3

    /// World-space point the shadow camera looks at. Typically the main camera's
    /// position (or the camera position projected onto the ground plane).
    let focus: float3

    /// Half-extent of the orthographic box (covers `2 * radius` per side).
    /// Larger values cover more ground at the cost of shadow texel density.
    let radius: Float

    /// Distance from `focus` along `direction` to place the shadow eye. Must be
    /// large enough that all shadow casters between the camera and the sun fit
    /// between the camera's `near` and `far`.
    let lift: Float

    var eye: float3 { focus + direction * lift }

    var viewMatrix: float4x4 {
        // `up = Y_AXIS` matches all other camera/light conventions in the codebase.
        // Degenerate when `direction` is exactly parallel to Y_AXIS; callers should
        // avoid pointing the sun straight up. With a flight-sim "sun roughly
        // overhead but tilted" placement this is never an issue in practice.
        Transform.look(eye: eye, target: focus, up: Y_AXIS)
    }

    var projectionMatrix: float4x4 {
        // Forward-Z ortho (see TiledDeferredDepthStencils.swift:10-13 comment for
        // why the shadow path is intentionally not reverse-Z).
        Transform.orthographicProjection(-radius, radius, -radius, radius, 1, 2 * lift)
    }

    var viewProjectionMatrix: float4x4 { projectionMatrix * viewMatrix }
}
