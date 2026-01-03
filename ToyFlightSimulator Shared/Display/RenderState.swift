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
}
