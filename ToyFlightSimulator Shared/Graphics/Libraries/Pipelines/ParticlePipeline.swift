//
//  ParticlePipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/1/24.
//

import MetalKit

struct ParticleComputePipelineState: ComputePipelineState {
    var computePipelineState: MTLComputePipelineState = {
        Self.createComputePipelineState(function: Graphics.Shaders[.ComputeParticles])
    }()
}

struct ParticleRenderPipelineState: RenderPipelineState {
    static var enableBlending: Bool = false
    
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Particle Render") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.ParticlesVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.ParticlesFragment]
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat  // Check this
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
//            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat  // Check this (NEW)
//            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            
            if enableBlending {
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].rgbBlendOperation = .add
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            }
        }
    }()
}
