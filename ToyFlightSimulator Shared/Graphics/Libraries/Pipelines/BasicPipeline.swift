//
//  BasicPipeline.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/27/24.
//

import MetalKit

struct BaseRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                        vertexShaderType: .BaseVertex,
                                                                        fragmentShaderType: .BaseFragment)
        renderPipelineDescriptor.label = "Base Render"
        return createRenderPipelineState(renderPipelineDescriptor: renderPipelineDescriptor)
    }()
}

struct MaterialRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                        vertexShaderType: .BaseVertex,
                                                                        fragmentShaderType: .MaterialFragment)
        renderPipelineDescriptor.label = "Material Render"
        return createRenderPipelineState(renderPipelineDescriptor: renderPipelineDescriptor)
    }()
}

struct InstancedRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                        vertexShaderType: .InstancedVertex,
                                                                        fragmentShaderType: .BaseFragment)
        renderPipelineDescriptor.label = "Instanced Render"
        return createRenderPipelineState(renderPipelineDescriptor: renderPipelineDescriptor)
    }()
}

struct SkySphereRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                        vertexShaderType: .SkySphereVertex,
                                                                        fragmentShaderType: .SkySphereFragment)
        renderPipelineDescriptor.label = "Sky Sphere Render"
        return createRenderPipelineState(renderPipelineDescriptor: renderPipelineDescriptor)
    }()
}

struct FinalRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        createRenderPipelineState(label: "Final Render") { descriptor in
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
        }
    }()
}
