//
//  TesselationPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/9/25.
//

import MetalKit

struct TesselationRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Tesselation", block: { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Tesselation]
            descriptor.vertexFunction = Graphics.Shaders[.BaseVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BaseFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
//            descriptor.rasterSampleCount = 4  // TODO: Refactor to set this dynamically
            descriptor.tessellationFactorStepFunction = .perPatch
            descriptor.maxTessellationFactor = 16  // TODO: Refactor to set this dynamically
            descriptor.tessellationPartitionMode = .pow2
        })
    }()
}

struct TesselationComputePipelineState: ComputePipelineState {
    var computePipelineState: MTLComputePipelineState = {
        Self.createComputePipelineState(function: Graphics.Shaders[.ComputeTesselation])
    }()
}
