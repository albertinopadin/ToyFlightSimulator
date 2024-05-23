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
    var direction: Float = 0
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

class ParticleEmitter {
    var position: float3 = [0, 0, 0]
    var currentParticles: Int = 0
    var particleCount: Int = 0
    var birthRate: Int
    var birthDelay: Int = 0
    private var birthTimer: Int = 0
    
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
        descriptor.positionXRange = 0...10
        descriptor.positionYRange = 0...10
        descriptor.direction = .pi / 2
        descriptor.directionRange = -0.3...0.3
        descriptor.speed = 3
        descriptor.pointSize = 80
        descriptor.startScale = 0
        descriptor.startScaleRange = 0.5...1.0
        descriptor.endScaleRange = 0...0
        descriptor.life = 180
        descriptor.lifeRange = -50...70
        descriptor.color = float4(1.0, 0.392, 0.1, 0.5)
        return Self.fire(descriptor: descriptor)
    }
    
    func emit() {
        if currentParticles >= particleCount {
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
            particlePointer.pointee.size = particleDescriptor.pointSize + .random(in: particleDescriptor.pointSizeRange)
            particlePointer.pointee.direction = particleDescriptor.direction + .random(in: particleDescriptor.directionRange)
            particlePointer.pointee.speed = particleDescriptor.speed + .random(in: particleDescriptor.speedRange)
            particlePointer.pointee.scale = particleDescriptor.startScale + .random(in: particleDescriptor.startScaleRange)
            particlePointer.pointee.startScale = particlePointer.pointee.scale
            
            if let range = particleDescriptor.endScaleRange {
                particlePointer.pointee.endScale = particleDescriptor.endScale + .random(in: range)
            } else {
                particlePointer.pointee.endScale = particlePointer.pointee.startScale
            }
            
            particlePointer.pointee.age = 0
            particlePointer.pointee.life = particleDescriptor.life + .random(in: particleDescriptor.lifeRange)
            particlePointer.pointee.color = particleDescriptor.color
            particlePointer = particlePointer.advanced(by: 1)
        }
        
        currentParticles += birthRate
    }
}
