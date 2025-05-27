//
//  ParticleRendering.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

import MetalKit

protocol ParticleRendering: RenderPassEncoding, ComputePassEncoding {}

extension ParticleRendering {
    func encodeParticleComputePass(into commandBuffer: MTLCommandBuffer) {
        encodeComputePass(into: commandBuffer, label: "Particle Compute Pass") { computeEncoder in
            let particleComputePipelineState = Graphics.ComputePipelineStates[.Particle]
            computeEncoder.setComputePipelineState(particleComputePipelineState)
            let threadsPerGroup = MTLSize(width: particleComputePipelineState.threadExecutionWidth,
                                          height: 1,
                                          depth: 1)
            ComputeManager.ComputeParticles(with: computeEncoder, threadsPerGroup: threadsPerGroup)
        }
    }
    
    func encodeParticleRenderStage(using renderEncoder: MTLRenderCommandEncoder, withMSAA: Bool = false) {
        encodeRenderStage(using: renderEncoder, label: "Particle Render Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[withMSAA ? .ParticleMSAA : .Particle])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.DrawParticles(with: renderEncoder)
        }
    }
}
