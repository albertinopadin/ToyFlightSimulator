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
                               // Pool size IS the steady-state plume density: recycling
                               // never kills particles, so a live emitter always fills
                               // its pool (birthRate only sets the ramp-up speed). 10k
                               // keeps blended-point overdraw manageable.
                               particleCount: 10_000,
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
        // length ≈ speed × life ≈ 8–12 m with the life spread below.
        descriptor.speed = 100.0
        descriptor.speedRange = 0...0
        descriptor.pointSize = Float(size.width)
        descriptor.startScale = 0
        descriptor.startScaleRange = 0.1...0.4
        descriptor.endScaleRange = 0...0
        descriptor.life = 0.1
        // Spread lives ±20% so recycle cycles decorrelate: with identical
        // lives every particle wraps in lockstep and any shared phase persists
        // forever; unequal lives make phases precess past each other into a
        // uniform continuum (fire()'s wide lifeRange has the same effect).
        descriptor.lifeRange = -0.02...0.02
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

        // Clamp the final batch to the remaining pool space: the writes below go
        // through a raw pointer with no bounds check, and nothing forces
        // particleCount to be a multiple of birthRate.
        let batch = min(birthRate, particleCount - currentParticles)
        
        for _ in 0..<batch {
            let positionX = particleDescriptor.position.x + .random(in: particleDescriptor.positionXRange)
            let positionY = particleDescriptor.position.y + .random(in: particleDescriptor.positionYRange)
            let positionZ = particleDescriptor.position.z + .random(in: particleDescriptor.positionZRange)
            particlePointer.pointee.position = [positionX, positionY, positionZ]
            particlePointer.pointee.startPosition = particlePointer.pointee.position
            particlePointer.pointee.size = particleDescriptor.pointSize + .random(in: particleDescriptor.pointSizeRange)
            // Per-lane randoms → conical spread around `direction`. (A scalar
            // Float.random here would broadcast ONE offset to all three lanes,
            // collapsing the spread onto the (1,1,1) diagonal.)
            particlePointer.pointee.direction = particleDescriptor.direction +
                                                float3.random(in: particleDescriptor.directionRange)
            particlePointer.pointee.speed = particleDescriptor.speed + .random(in: particleDescriptor.speedRange)
            particlePointer.pointee.scale = particleDescriptor.startScale + .random(in: particleDescriptor.startScaleRange)
            particlePointer.pointee.startScale = particlePointer.pointee.scale
            
            if let range = particleDescriptor.endScaleRange {
                particlePointer.pointee.endScale = particleDescriptor.endScale + .random(in: range)
            } else {
                particlePointer.pointee.endScale = particlePointer.pointee.startScale
            }
            
            // Spawn at the nozzle with age = 0: an igniting plume visibly
            // extends outward over one particle transit instead of appearing
            // at full length. Safe against the phase collapse
            // (debugging/claude/afterburner_plume_strobing_collapse.md): the
            // batch shares this initial phase only until its first expiry —
            // per-particle lives decorrelate batch-mates there, and the
            // kernel's remainder-carry keeps them separated forever after
            // (sim variant C).
            particlePointer.pointee.age = 0
            particlePointer.pointee.life = particleDescriptor.life + .random(in: particleDescriptor.lifeRange)
            
            particlePointer.pointee.color = particleDescriptor.color
            particlePointer = particlePointer.advanced(by: 1)
        }
        
        currentParticles += batch
    }
}
