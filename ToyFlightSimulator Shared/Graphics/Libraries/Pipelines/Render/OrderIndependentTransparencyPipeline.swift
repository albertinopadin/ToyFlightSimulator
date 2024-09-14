//
//  OrderIndependentTransparencyPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/27/24.
//

import MetalKit

extension RenderPipelineState {
    static func getOpaqueRenderPipelineDescriptor(vertexDescriptorType: VertexDescriptorType,
                                                  vertexShaderType: ShaderType,
                                                  fragmentShaderType: ShaderType) -> MTLRenderPipelineDescriptor {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[vertexDescriptorType]
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[vertexShaderType]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[fragmentShaderType]
        renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index].isBlendingEnabled = true
        renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index].alphaBlendOperation = .add
        renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index].sourceAlphaBlendFactor = .one
        renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index].destinationAlphaBlendFactor = .zero
        renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index].sourceRGBBlendFactor = .sourceAlpha
        renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index].rgbBlendOperation = .add
        renderPipelineDescriptor.colorAttachments[TFSRenderTargetLighting.index].writeMask = .all
        return renderPipelineDescriptor
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
        let renderPipelineDescriptor = Self.getOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                              vertexShaderType: .BaseVertex,
                                                                              fragmentShaderType: .BaseFragment)
        
        renderPipelineDescriptor.label = "Opaque Render"
        return createRenderPipelineState(renderPipelineDescriptor: renderPipelineDescriptor)
    }()
}

struct OpaqueMaterialRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Base,
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
