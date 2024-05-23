//
//  ComputePipelineState.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/1/24.
//

import MetalKit

protocol ComputePipelineState {
    var computePipelineState: MTLComputePipelineState { get set }
}

extension ComputePipelineState {
    static func createComputePipelineState(function: MTLFunction) -> MTLComputePipelineState {
        do {
            return try Engine.Device.makeComputePipelineState(function: function)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    static func createComputePipelineState(functionName: String) -> MTLComputePipelineState {
        guard let kernelFunc = Engine.DefaultLibrary.makeFunction(name: functionName) else {
            fatalError("Unable to create \(functionName) compute kernel function.")
        }
        
        return Self.createComputePipelineState(function: kernelFunc)
    }
}
