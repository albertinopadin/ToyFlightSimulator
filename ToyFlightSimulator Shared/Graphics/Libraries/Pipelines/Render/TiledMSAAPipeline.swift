//
//  TiledMSAAPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/24.
//

import MetalKit

extension RenderPipelineState {
    static func setGBufferPixelFormatsForTiledMultisampledPipeline(descriptor: MTLRenderPipelineDescriptor) {
        descriptor.colorAttachments[TFSRenderTargetAlbedo.index].pixelFormat = TiledDeferredGBufferTextures.albedoPixelFormat
        descriptor.colorAttachments[TFSRenderTargetNormal.index].pixelFormat = TiledDeferredGBufferTextures.normalPixelFormat
        descriptor.colorAttachments[TFSRenderTargetPosition.index].pixelFormat =
            TiledDeferredGBufferTextures.positionPixelFormat
    }
}

struct TiledMSAAShadowPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tiled Multisampled Shadow", block: { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.ShadowVertex]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = .invalid
            descriptor.depthAttachmentPixelFormat = .depth32Float
            descriptor.rasterSampleCount = 4  // TODO: Refactor to set this dynamically
        })
    }()
}

struct TiledMSAAGBufferPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tiled Multisampled GBuffer") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredGBufferVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TiledDeferredGBufferFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setGBufferPixelFormatsForTiledMultisampledPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.rasterSampleCount = 4  // TODO: Refactor to set this dynamically
        }
    }()
}

struct TiledMSAADirectionalLightPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tiled Multisampled Directional Light") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredQuadVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TiledDeferredDirectionalLightFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setGBufferPixelFormatsForTiledMultisampledPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.rasterSampleCount = 4  // TODO: Refactor to set this dynamically
        }
    }()
}

struct TiledMSAATransparencyPipelineState: RenderPipelineState {
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
            Self.setGBufferPixelFormatsForTiledMultisampledPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            Self.enableBlending(colorAttachmentDescriptor: descriptor.colorAttachments[TFSRenderTargetLighting.index])
            descriptor.rasterSampleCount = 4  // TODO: Refactor to set this dynamically
        }
    }()
}

struct TiledMSAAPointLightPipelineState: RenderPipelineState {
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
        createRenderPipelineState(label: "Tiled Multisampled Point Light") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.PositionOnly]
            descriptor.vertexFunction = Graphics.Shaders[.TiledDeferredPointLightVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TiledDeferredPointLightFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setGBufferPixelFormatsForTiledMultisampledPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            Self.enableBlending(colorAttachment: descriptor.colorAttachments[TFSRenderTargetLighting.index])
            descriptor.rasterSampleCount = 4  // TODO: Refactor to set this dynamically
        }
    }()
}

struct TiledMSAAAverageResolvePipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createTileRenderPipelineState(label: "Tiled MSAA Resolve") { descriptor in
            descriptor.tileFunction = Graphics.Shaders[.TiledMSAAAverageResolve]
            descriptor.threadgroupSizeMatchesTileSize = true
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            descriptor.colorAttachments[TFSRenderTargetAlbedo.index].pixelFormat = TiledDeferredGBufferTextures.albedoPixelFormat
            descriptor.colorAttachments[TFSRenderTargetNormal.index].pixelFormat = TiledDeferredGBufferTextures.normalPixelFormat
            descriptor.colorAttachments[TFSRenderTargetPosition.index].pixelFormat =
                TiledDeferredGBufferTextures.positionPixelFormat
            descriptor.rasterSampleCount = 4  // TODO: Refactor to set this dynamically
        }
    }()
}

struct TiledMSAACompositePipelineState: RenderPipelineState {
    var renderPipelineState: any MTLRenderPipelineState = {
        createRenderPipelineState(label: "Composition") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.CompositeVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.CompositeFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
        }
    }()
}
