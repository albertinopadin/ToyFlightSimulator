//
//  OrderIndependentTransparencyPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/27/24.
//

import MetalKit

extension RenderPipelineState {
    static func EnableBlending(colorAttachment: MTLRenderPipelineColorAttachmentDescriptor) {
        colorAttachment.isBlendingEnabled = true
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationAlphaBlendFactor = .zero
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.writeMask = .all
    }
    
    static func GetOpaqueRenderPipelineDescriptor(vertexDescriptorType: VertexDescriptorType,
                                                  vertexShaderType: ShaderType,
                                                  fragmentShaderType: ShaderType) -> MTLRenderPipelineDescriptor {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
        descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        descriptor.stencilAttachmentPixelFormat = .invalid
        descriptor.vertexDescriptor = Graphics.VertexDescriptors[vertexDescriptorType]
        descriptor.vertexFunction = Graphics.Shaders[vertexShaderType]
        descriptor.fragmentFunction = Graphics.Shaders[fragmentShaderType]
        Self.EnableBlending(colorAttachment: descriptor.colorAttachments[TFSRenderTargetLighting.index])
        return descriptor
    }
}

struct TileRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createTileRenderPipelineState(label: "Init Image Block Kernel") { descriptor in
            descriptor.tileFunction = Graphics.Shaders[.TileKernel]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            descriptor.threadgroupSizeMatchesTileSize = true
        }
    }()
}

struct OpaqueRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.GetOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                              vertexShaderType: .BaseVertex,
                                                                              fragmentShaderType: .BaseFragment)
        
        renderPipelineDescriptor.label = "Opaque Render"
        return createRenderPipelineState(renderPipelineDescriptor: renderPipelineDescriptor)
    }()
}

struct OpaqueMaterialRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.GetOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                              vertexShaderType: .BaseVertex,
                                                                              fragmentShaderType: .MaterialFragment)
        
        renderPipelineDescriptor.label = "Opaque Material Render"
        return createRenderPipelineState(renderPipelineDescriptor: renderPipelineDescriptor)
    }()
}

struct OrderIndependentTransparencyRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Transparent Render") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.BaseVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TransparentMaterialFragment]
            
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.colorAttachments[0].writeMask = MTLColorWriteMask(rawValue: 0)
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            descriptor.stencilAttachmentPixelFormat = .invalid
        }
    }()
}

struct BlendRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Transparent Fragment Blending") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexDescriptor = nil
            descriptor.vertexFunction = Graphics.Shaders[.QuadPassVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BlendFragment]
        }
    }()
}
