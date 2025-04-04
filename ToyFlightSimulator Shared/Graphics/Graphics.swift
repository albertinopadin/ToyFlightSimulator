//
//  Graphics.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import os

final class Graphics {
    public static let Shaders = ShaderLibrary()
    public static let VertexDescriptors = VertexDescriptorLibrary()
    public static let RenderPipelineStates = RenderPipelineStateLibrary()
    public static let ComputePipelineStates = ComputePipelineStateLibrary()
    public static let DepthStencilStates = DepthStencilStateLibrary()
    public static let SamplerStates = SamplerStateLibrary()
    public static let MDLVertexDescriptors = MDLVertexDescriptorLibrary()
}
