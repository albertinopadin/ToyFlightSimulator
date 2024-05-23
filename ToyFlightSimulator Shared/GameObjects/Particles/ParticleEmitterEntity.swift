//
//  ParticleEmitterEntity.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/27/24.
//

import MetalKit

protocol ParticleEmitterEntity: GameObject {
    var emitter: ParticleEmitter { get }
    
    func computeUpdate(_ computeEncoder: MTLComputeCommandEncoder, threadsPerGroup: MTLSize)
}
