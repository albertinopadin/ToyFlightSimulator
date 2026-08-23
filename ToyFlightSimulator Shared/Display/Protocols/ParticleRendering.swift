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
        // Freeze the plume while paused. Steady-state pause parks both loops
        // (Paused also pauses the MTKView, which stops draw and therefore the
        // update handshake), but Engine.PauseView flips metalView.isPaused via
        // DispatchQueue.main.async — the frame or two that still draws in that
        // window would advance the simulation with the stale, non-zero
        // GameTime.DeltaTime the paused update ticks no longer refresh.
        // Skipping the whole encode (rather than binding dt = 0) also skips
        // the encoder + scene-graph walk; DrawParticles still runs, so the
        // frozen plume stays visible behind the menu.
        guard !SceneManager.Paused else { return }
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
