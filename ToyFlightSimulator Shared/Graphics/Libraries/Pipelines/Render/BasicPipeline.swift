//
//  BasicPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/27/24.
//

import MetalKit

struct BaseRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Simple,
                                                                        vertexShaderType: .BaseVertex,
                                                                        fragmentShaderType: .BaseFragment)
        renderPipelineDescriptor.label = "Base Render"
        return createRenderPipelineState(descriptor: renderPipelineDescriptor)
    }()
}

struct MaterialRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Simple,
                                                                        vertexShaderType: .BaseVertex,
                                                                        fragmentShaderType: .MaterialFragment)
        renderPipelineDescriptor.label = "Material Render"
        return createRenderPipelineState(descriptor: renderPipelineDescriptor)
    }()
}

struct SkySphereRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Simple,
                                                                        vertexShaderType: .SkySphereVertex,
                                                                        fragmentShaderType: .SkySphereFragment)
        renderPipelineDescriptor.label = "Sky Sphere Render"
        return createRenderPipelineState(descriptor: renderPipelineDescriptor)
    }()
}

struct FinalRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Final Render") { descriptor in
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            // No vertexDescriptor: full_screen_vertex is bufferless (vertex_id
            // only). A leftover descriptor makes the debug layer demand a vertex
            // buffer at index 0 on every draw, even though the function has no
            // [[stage_in]].
            descriptor.vertexFunction = Graphics.Shaders[.FullScreenVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
        }
    }()
}
