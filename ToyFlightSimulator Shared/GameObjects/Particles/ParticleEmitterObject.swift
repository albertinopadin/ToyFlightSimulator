//
//  ParticleEmitterObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/18/24.
//
import MetalKit

class ParticleEmitterObject: GameObject, ParticleEmitterEntity {
    override var objectType: GameObjectType { .particles }

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
            // Dispatch only the born prefix: emit() fills slots contiguously from 0
            // and expiry recycles in place, so [0, currentParticles) is exactly the
            // set of ever-born slots (the count never shrinks while emitting; only
            // reset() zeroes it). Never-emitted slots are never touched by the GPU —
            // no reliance on the buffer's zero-fill, no wasted threads.
            // currentParticles is read under the same handshake guarantee as dt
            // below; a stale-low read would only skip a spawn's first compute frame.
            let threadsPerGrid = MTLSize(width: emitter.currentParticles, height: 1, depth: 1)
            computeEncoder.setBuffer(emitter.particleBuffer, offset: 0, index: 0)
            // Frame delta in seconds (C11). Reading this on the render thread is
            // safe: encoding starts only after this frame's render↔update
            // handshake (updateDoneSemaphore), so the update thread has already
            // written this tick's value and is parked until the next frame.
            var dt = Float(GameTime.DeltaTime)
            computeEncoder.setBytes(&dt, length: Float.size, index: 1)
            computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        }
    }
}

