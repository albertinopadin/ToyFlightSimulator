//
//  ComputePipelineStateLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/1/24.
//

import MetalKit

enum ComputePipelineStateType {
    case Particle
    case Tesselation
}

final class ComputePipelineStateLibrary: Library<ComputePipelineStateType, MTLComputePipelineState>, @unchecked Sendable {
    private var _library: [ComputePipelineStateType: ComputePipelineState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(ParticleComputePipelineState(), forKey: .Particle)
        _library.updateValue(TesselationComputePipelineState(), forKey: .Tesselation)
    }
    
    override subscript(type: ComputePipelineStateType) -> MTLComputePipelineState {
        return _library[type]!.computePipelineState
    }
}
