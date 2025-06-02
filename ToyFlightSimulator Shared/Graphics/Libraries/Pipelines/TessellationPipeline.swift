//
//  TessellationPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/9/25.
//

import MetalKit

struct TessellationRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tessellation", block: { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Tessellation]
            descriptor.vertexFunction = Graphics.Shaders[.TessellationVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TessellationFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            
            descriptor.tessellationFactorStepFunction = .perPatch
            descriptor.maxTessellationFactor = TessellatedRendering.maxTessellation  // TODO: Refactor to set this dynamically
            descriptor.tessellationPartitionMode = .pow2
        })
    }()
}

struct TessellationGBufferRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tessellation GBuffer", block: { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Tessellation]
            descriptor.vertexFunction = Graphics.Shaders[.TessellationVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TessellationGBufferFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setGBufferPixelFormatsForTiledMultisampledPipeline(descriptor: descriptor)
            descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
            descriptor.rasterSampleCount = 4  // TODO: Refactor to set this dynamically
            
            descriptor.tessellationFactorStepFunction = .perPatch
            descriptor.maxTessellationFactor = TessellatedRendering.maxTessellation  // TODO: Refactor to set this dynamically
            descriptor.tessellationPartitionMode = .pow2
        })
    }()
}

struct TessellationComputePipelineState: ComputePipelineState {
    var computePipelineState: MTLComputePipelineState = {
        Self.createComputePipelineState(function: Graphics.Shaders[.ComputeTessellation])
    }()
}
