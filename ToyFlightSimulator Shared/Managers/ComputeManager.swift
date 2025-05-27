//
//  ComputeManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/19/25.
//

import MetalKit

final class ComputeManager {
    public static func ComputeParticles(with computeEncoder: MTLComputeCommandEncoder, threadsPerGroup: MTLSize) {
        // TODO: this sucks, refactor!
        SceneManager.CurrentScene?.computeParticles(with: computeEncoder, threadsPerGroup: threadsPerGroup)
    }
    
    public static func ComputeTerrainTessellation(with computeEncoder: MTLComputeCommandEncoder) {
        SceneManager.CurrentScene?.computeTerrainTessellation(with: computeEncoder)
    }
}
