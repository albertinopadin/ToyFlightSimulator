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
    static var enableBlending: Bool = true
    
    static func enableBlending(colorAttachment: MTLRenderPipelineColorAttachmentDescriptor) {
        colorAttachment.isBlendingEnabled = true
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceRGBBlendFactor = .one
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationRGBBlendFactor = .one
        colorAttachment.destinationAlphaBlendFactor = .zero
        colorAttachment.sourceRGBBlendFactor = .one
        colorAttachment.sourceAlphaBlendFactor = .one
    }
    
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Particle Render") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.ParticlesVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.ParticlesFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setGBufferPixelFormatsForTiledDeferredPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            
            if enableBlending {
//                descriptor.colorAttachments[0].isBlendingEnabled = true
//                descriptor.colorAttachments[0].rgbBlendOperation = .add
//                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
//                descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
                
//                Self.enableBlending(colorAttachmentDescriptor: descriptor.colorAttachments[0])
                Self.enableBlending(colorAttachment: descriptor.colorAttachments[TFSRenderTargetLighting.index])
            }
        }
    }()
}