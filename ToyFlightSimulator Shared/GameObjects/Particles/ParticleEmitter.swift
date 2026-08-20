//
//  ParticleEmitter.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/14/24.
//

import MetalKit

struct ParticleDescriptor {
    var position: float3 = [0, 0, 0]
    var positionXRange: ClosedRange<Float> = 0...0
    var positionYRange: ClosedRange<Float> = 0...0
    var positionZRange: ClosedRange<Float> = 0...0
    var direction: float3 = [0, 1, 0]
    var directionRange: ClosedRange<Float> = 0...0
    var speed: Float = 0
    var speedRange: ClosedRange<Float> = 0...0
    var pointSize: Float = 80
    var pointSizeRange: ClosedRange<Float> = 0...0
    var startScale: Float = 0
    var startScaleRange: ClosedRange<Float> = 1...1
    var endScale: Float = 0
    var endScaleRange: ClosedRange<Float>?
    var life: Float = 0
    var lifeRange: ClosedRange<Float> = 1...1
    var color: float4 = [0, 0, 0, 1]
}

final class ParticleEmitter: @unchecked Sendable {
    static let FIRE_COLOR = float4(1.0, 0.392, 0.1, 0.5)
    
    var position: float3  = [0, 0, 0] {
        didSet {
            self.particleDescriptor.position = self.position
        }
    }
    
    var currentParticles: Int = 0
    var particleCount: Int = 0
    var birthRate: Int
    var birthDelay: Int = 0
    private var birthTimer: Int = 0
    private var loggedPoolSaturation = false
    
    var particleTexture: MTLTexture?
    var particleBuffer: MTLBuffer?
    var particleDescriptor: ParticleDescriptor
    var blending: Bool = false
    
    init(_ descriptor: ParticleDescriptor,
         texture: String? = nil,
         particleCount: Int,
         birthRate: Int,
         birthDelay: Int,
         blending: Bool = false) {
        self.particleDescriptor = descriptor
        self.position = particleDescriptor.position
        self.birthRate = birthRate
        self.birthDelay = birthDelay
        self.birthTimer = birthDelay
        self.blending = blending
        self.particleCount = particleCount
        
        let bufferSize = Particle.stride(particleCount)
        self.particleBuffer = Engine.Device.makeBuffer(length: bufferSize)
        
        if let texture {
            self.particleTexture = TextureLoader.LoadTexture(name: texture)
        }
    }
    
    static func fire(descriptor: ParticleDescriptor) -> ParticleEmitter {
        return ParticleEmitter(descriptor,
                               texture: "fire",
                               particleCount: 1200,
                               birthRate: 5,
                               birthDelay: 0,
                               blending: true)
    }
    
    static func fire(size: CGSize, position: float3 = [0, 0, 0]) -> ParticleEmitter {
        var descriptor = ParticleDescriptor()
        descriptor.position = position
        descriptor.positionXRange = -1...1
        descriptor.positionYRange = -1...1
        descriptor.positionZRange = -1...1
        descriptor.direction = [0, 1, 0]
        descriptor.directionRange = -0.3...0.3
        // Units are physical since C11 (speed m/s, life seconds): converted 1:1
        // from the old per-dispatch values at the historical 60 fps cadence
        // (0.2/frame → 12 m/s, 180 frames → 3 s, −50…70 frames → −0.83…1.17 s).
        descriptor.speed = 12.0
        descriptor.pointSize = Float(size.width)
        descriptor.startScale = 0
        descriptor.startScaleRange = 0.5...1.0
        descriptor.endScaleRange = 0...0
        descriptor.life = 3.0
        descriptor.lifeRange = -0.83...1.17
        descriptor.color = Self.FIRE_COLOR
        return Self.fire(descriptor: descriptor)
    }
    
    static func afterburner(descriptor: ParticleDescriptor) -> ParticleEmitter {
        return ParticleEmitter(descriptor,
                               texture: "fire",
                               particleCount: 100_000,
                               birthRate: 20,
                               birthDelay: 0,
                               blending: true)
    }
    
    static func afterburner(size: CGSize, position: float3 = [0, 0, 0]) -> ParticleEmitter {
        var descriptor = ParticleDescriptor()
        descriptor.position = position
        descriptor.positionXRange = -0.4...0.4
        descriptor.positionYRange = -0.4...0.4
        descriptor.positionZRange = -0.1...0.1
        descriptor.direction = [0, 0, -1]
        descriptor.directionRange = -0.05...0.05
        // Units are physical since C11: speed in m/s, life in seconds — plume
        // length ≈ speed × life = 10 m.
        descriptor.speed = 100.0
        descriptor.speedRange = 0...0
        descriptor.pointSize = Float(size.width)
        descriptor.startScale = 0
        descriptor.startScaleRange = 0.1...0.4
        descriptor.endScaleRange = 0...0
        descriptor.life = 0.1
        descriptor.lifeRange = 0...0
        descriptor.color = Self.FIRE_COLOR
        return Self.afterburner(descriptor: descriptor)
    }
    
    func reset() {
        currentParticles = 0
        loggedPoolSaturation = false
    }

    func emit() {
        if currentParticles >= particleCount {
            // Expected steady state, not an error: compute_particle recycles
            // expired particles in place and currentParticles never shrinks
            // while emitting, so a live emitter always fills its pool. Log once
            // — this path runs every update tick once the pool is full.
            if !loggedPoolSaturation {
                loggedPoolSaturation = true
                print("[ParticleEmitter emit] Particle pool saturated: \(currentParticles)/\(particleCount); existing particles recycle in place")
            }
            return
        }
        
        guard let particleBuffer else { return }
        
        birthTimer += 1
        if birthTimer < birthDelay {
            return
        }
        
        birthTimer = 0
        
        var particlePointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        particlePointer = particlePointer.advanced(by: currentParticles)
        
        for _ in 0..<birthRate {
            let positionX = particleDescriptor.position.x + .random(in: particleDescriptor.positionXRange)
            let positionY = particleDescriptor.position.y + .random(in: particleDescriptor.positionYRange)
            let positionZ = particleDescriptor.position.z + .random(in: particleDescriptor.positionZRange)
            particlePointer.pointee.position = [positionX, positionY, positionZ]
            particlePointer.pointee.startPosition = particlePointer.pointee.position
            particlePointer.pointee.size = particleDescriptor.pointSize + Float.random(in: particleDescriptor.pointSizeRange)
            particlePointer.pointee.direction = particleDescriptor.direction +
                                                Float.random(in: particleDescriptor.directionRange)
            particlePointer.pointee.speed = particleDescriptor.speed + Float.random(in: particleDescriptor.speedRange)
            particlePointer.pointee.scale = particleDescriptor.startScale + Float.random(in: particleDescriptor.startScaleRange)
            particlePointer.pointee.startScale = particlePointer.pointee.scale
            
            if let range = particleDescriptor.endScaleRange {
                particlePointer.pointee.endScale = particleDescriptor.endScale + Float.random(in: range)
            } else {
                particlePointer.pointee.endScale = particlePointer.pointee.startScale
            }
            
            particlePointer.pointee.age = 0
            particlePointer.pointee.life = particleDescriptor.life + Float.random(in: particleDescriptor.lifeRange)
            particlePointer.pointee.color = particleDescriptor.color
            particlePointer = particlePointer.advanced(by: 1)
        }
        
        currentParticles += birthRate
    }
}
