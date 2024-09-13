//
//  TiledDeferredPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/2/24.
//

import MetalKit

extension RenderPipelineState {
    static func setGBufferPixelFormatsForTiledDeferredPipeline(descriptor: MTLRenderPipelineDescriptor) {
        descriptor.colorAttachments[TFSRenderTargetAlbedo.index].pixelFormat = TiledDeferredGBufferTextures.albedoPixelFormat
        descriptor.colorAttachments[TFSRenderTargetNormal.index].pixelFormat = TiledDeferredGBufferTextures.normalPixelFormat
        descriptor.colorAttachments[TFSRenderTargetPosition.index].pixelFormat =
            TiledDeferredGBufferTextures.positionPixelFormat
    }
}

struct TiledDeferredShadowPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tiled Deferred Shadow", block: { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.ShadowVertex]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = .invalid
            descriptor.depthAttachmentPixelFormat = .depth32Float
        })
    }()
}

struct TiledDeferredGBufferPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tiled Deferred GBuffer") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredGBufferVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TiledDeferredGBufferFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setGBufferPixelFormatsForTiledDeferredPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            
            // Testing
//            Self.enableBlending(colorAttachmentDescriptor: descriptor.colorAttachments[TFSRenderTargetLighting.index])
        }
    }()
}

struct TiledDeferredDirectionalLightPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tiled Deferred Directional Light") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredQuadVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TiledDeferredDirectionalLightFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setGBufferPixelFormatsForTiledDeferredPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            
            // Testing
//            Self.enableBlending(colorAttachmentDescriptor: descriptor.colorAttachments[TFSRenderTargetLighting.index])
        }
    }()
}

struct TiledDeferredTransparencyPipelineState: RenderPipelineState {
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
        createRenderPipelineState(label: "Tiled Transparent Render") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredTransparencyVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TiledDeferredTransparencyFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setGBufferPixelFormatsForTiledDeferredPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            Self.enableBlending(colorAttachmentDescriptor: descriptor.colorAttachments[TFSRenderTargetLighting.index])
        }
    }()
}

struct TiledDeferredPointLightPipelineState: RenderPipelineState {
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
        createRenderPipelineState(label: "Tiled Deferred Point Light") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.PositionOnly]
            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredPointLightVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TiledDeferredPointLightFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setGBufferPixelFormatsForTiledDeferredPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            Self.enableBlending(colorAttachment: descriptor.colorAttachments[TFSRenderTargetLighting.index])
        }
    }()
}
