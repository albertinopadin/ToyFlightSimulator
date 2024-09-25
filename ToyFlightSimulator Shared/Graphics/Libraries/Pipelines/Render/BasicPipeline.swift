//
//  BasicPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/27/24.
//

import MetalKit

struct BaseRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let descriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                          vertexShaderType: .BaseVertex,
                                                          fragmentShaderType: .BaseFragment)
        descriptor.label = "Base Render"
        return createRenderPipelineState(descriptor: descriptor)
    }()
}

struct MaterialRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let descriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                          vertexShaderType: .BaseVertex,
                                                          fragmentShaderType: .MaterialFragment)
        descriptor.label = "Material Render"
        return createRenderPipelineState(descriptor: descriptor)
    }()
}

struct SkySphereRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let descriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                          vertexShaderType: .SkySphereVertex,
                                                          fragmentShaderType: .SkySphereFragment)
        descriptor.label = "Sky Sphere Render"
//        descriptor.rasterSampleCount = 2
        return createRenderPipelineState(descriptor: descriptor)
    }()
}

struct FinalRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Final Render") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            descriptor.rasterSampleCount = 4
        }
    }()
}
