//
//  RenderState.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/3/26.
//

import Metal

final class RenderState {
    nonisolated(unsafe)
    public static var CurrentPipelineStateType: RenderPipelineStateType = .TiledMSAAGBuffer

    nonisolated(unsafe)
    public static var PreviousPipelineStateType: RenderPipelineStateType = .TiledMSAAGBuffer

    /// Back to the process-start defaults. Called from SceneManager.TeardownScene
    /// so a renderer switch can't leak the previous renderer's last-bound
    /// pipeline types into the next renderer's first frame (a stale *Animated
    /// Current would trigger a bogus restore before any tracked bind runs).
    public static func Reset() {
        CurrentPipelineStateType = .TiledMSAAGBuffer
        PreviousPipelineStateType = .TiledMSAAGBuffer
    }
}
