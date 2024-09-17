//
//  SinglePassDeferredPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/27/24.
//

import MetalKit

extension RenderPipelineState {
    static func setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: MTLRenderPipelineDescriptor) {
        descriptor.colorAttachments[TFSRenderTargetAlbedo.index].pixelFormat = SinglePassDeferredGBufferTextures.albedoSpecularFormat
        descriptor.colorAttachments[TFSRenderTargetNormal.index].pixelFormat = SinglePassDeferredGBufferTextures.normalShadowFormat
        descriptor.colorAttachments[TFSRenderTargetDepth.index].pixelFormat = SinglePassDeferredGBufferTextures.depthFormat
    }
}

// -------------- FOR DEFERRED LIGHTING ---------------- //
struct ShadowGenerationRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Shadow Generation Stage") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]  // ???
            descriptor.vertexFunction = Graphics.Shaders[.ShadowVertex]
            descriptor.depthAttachmentPixelFormat = .depth32Float
            // TODO: Should I set the render target pixel formats here?
        }
    }()
}

struct GBufferGenerationBaseRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "GBuffer Generation Stage") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.SinglePassDeferredGBufferVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SinglePassDeferredGBufferFragmentBase]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
            
            let attachment = descriptor.colorAttachments[TFSRenderTargetLighting.index]
            attachment?.isBlendingEnabled = true
            attachment?.destinationRGBBlendFactor = .one
            attachment?.destinationAlphaBlendFactor = .zero
        }
    }()
}

struct GBufferGenerationMaterialRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "GBuffer Generation Stage") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.SinglePassDeferredGBufferVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SinglePassDeferredGBufferFragmentMaterial]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
        }
    }()
}

struct DirectionalLightingRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Directional Lighting Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.SinglePassDeferredDirectionalLightVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SinglePassDeferredDirectionalLightFragment]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
        }
    }()
}

struct TransparencyPipelineState: RenderPipelineState {
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
        createRenderPipelineState(label: "Transparency Stage") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.SinglePassDeferredTransparencyVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SinglePassDeferredTransparencyFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            Self.enableBlending(colorAttachmentDescriptor: descriptor.colorAttachments[TFSRenderTargetLighting.index])
        }
    }()
}

struct LightMaskRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Light Mask Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.LightMaskVertex]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
        }
    }()
}

struct PointLightingRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Point Lights Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.SinglePassDeferredPointLightVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SinglePassDeferredPointLightFragment]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            
//            let attachment = descriptor.colorAttachments[0]!
//            enableBlending(colorAttachmentDescriptor: attachment)
            
            let attachment = descriptor.colorAttachments[TFSRenderTargetLighting.index]
            attachment?.isBlendingEnabled = true
            attachment?.destinationRGBBlendFactor = .one
            attachment?.destinationAlphaBlendFactor = .zero
            
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
        }
    }()
}

struct SkyboxRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Skybox Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.SkyboxVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SkyboxFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Skybox]
//            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
        }
    }()
}

struct IcosahedronRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Icosahedron Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.IcosahedronVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.IcosahedronFragment]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormatsForSinglePassDeferredPipeline(descriptor: descriptor)
        }
    }()
}
