//
//  ParticleEmitterObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/18/24.
//
import MetalKit

class ParticleEmitterObject: GameObject, ParticleEmitterEntity {
    let emitter: ParticleEmitter
    
    public var shouldEmit: Bool = true
    
    init(name: String, emitter: ParticleEmitter, modelType: ModelType = .None) {
        self.emitter = emitter
        super.init(name: name, modelType: modelType)
    }
    
    override func update() {
        super.update()
        
        if shouldEmit {
            emitter.emit()
        }
    }
    
    func computeUpdate(_ computeEncoder: any MTLComputeCommandEncoder, threadsPerGroup: MTLSize) {
        if shouldEmit && emitter.currentParticles > 0 {
            let threadsPerGrid = MTLSize(width: emitter.particleCount, height: 1, depth: 1)
            computeEncoder.setBuffer(emitter.particleBuffer, offset: 0, index: 0)
            computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        }
    }
}

