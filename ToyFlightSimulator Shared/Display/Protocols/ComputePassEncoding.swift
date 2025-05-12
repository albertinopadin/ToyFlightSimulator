//
//  ComputePassEncoding.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

import MetalKit

protocol ComputePassEncoding {}

extension ComputePassEncoding {
    func encodeComputePass(into commandBuffer: MTLCommandBuffer,
                           label: String,
                           _ encodingBlock: (MTLComputeCommandEncoder) -> Void) {
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Failed to make compute command encoder.")
        }
        
        computeEncoder.label = label
        encodingBlock(computeEncoder)
        computeEncoder.endEncoding()
    }
}
