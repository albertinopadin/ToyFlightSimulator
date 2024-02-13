//
//  Graphics.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

struct Graphics {
    private static var _shaderLibrary: ShaderLibrary!
    public static var Shaders: ShaderLibrary { return _shaderLibrary }
    
    private static var _vertexDescriptorLibrary: VertexDescriptorLibrary!
    public static var VertexDescriptors: VertexDescriptorLibrary { return _vertexDescriptorLibrary }
    
    private static var _renderPipelineStateLibrary: RenderPipelineStateLibrary!
    public static var RenderPipelineStates: RenderPipelineStateLibrary { return _renderPipelineStateLibrary }
    
    private static var _depthStencilStateLibrary: DepthStencilStateLibrary!
    public static var DepthStencilStates: DepthStencilStateLibrary { return _depthStencilStateLibrary }
    
    private static var _samplerStateLibrary: SamplerStateLibrary!
    public static var SamplerStates: SamplerStateLibrary { return _samplerStateLibrary }
    
    private static var _mdlVertexDescriptorLibrary: MDLVertexDescriptorLibrary!
    public static var MDLVertexDescriptors: MDLVertexDescriptorLibrary { return _mdlVertexDescriptorLibrary }
    
    public static func Initialize() {
        _shaderLibrary = ShaderLibrary()
        _vertexDescriptorLibrary = VertexDescriptorLibrary()
        _renderPipelineStateLibrary = RenderPipelineStateLibrary()
        _depthStencilStateLibrary = DepthStencilStateLibrary()
        _samplerStateLibrary = SamplerStateLibrary()
        _mdlVertexDescriptorLibrary = MDLVertexDescriptorLibrary()
    }
}
