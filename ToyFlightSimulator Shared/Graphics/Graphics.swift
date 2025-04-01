//
//  Graphics.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import os

class Graphics {
    private static let shadersLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _shaderLibrary: ShaderLibrary!
    public static var Shaders: ShaderLibrary {
        return withLock(shadersLock) {
            return _shaderLibrary
        }
    }
    
    private static let vertexDescriptorsLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _vertexDescriptorLibrary: VertexDescriptorLibrary!
    public static var VertexDescriptors: VertexDescriptorLibrary {
        return withLock(vertexDescriptorsLock) {
            return _vertexDescriptorLibrary
        }
    }
    
    private static let renderPipelineStatesLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _renderPipelineStateLibrary: RenderPipelineStateLibrary!
    public static var RenderPipelineStates: RenderPipelineStateLibrary {
        return withLock(renderPipelineStatesLock) {
            return _renderPipelineStateLibrary
        }
    }
    
    private static let computePipelineStatesLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _computePipelineStateLibrary: ComputePipelineStateLibrary!
    public static var ComputePipelineStates: ComputePipelineStateLibrary {
        return withLock(computePipelineStatesLock) {
            return _computePipelineStateLibrary
        }
    }
    
    private static let depthStencilStatesLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _depthStencilStateLibrary: DepthStencilStateLibrary!
    public static var DepthStencilStates: DepthStencilStateLibrary {
        return withLock(depthStencilStatesLock) {
            return _depthStencilStateLibrary
        }
    }
    
    private static let samplerStatesLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _samplerStateLibrary: SamplerStateLibrary!
    public static var SamplerStates: SamplerStateLibrary {
        return withLock(samplerStatesLock) {
            return _samplerStateLibrary
        }
    }
    
    private static let mdlVertexDescriptorsLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _mdlVertexDescriptorLibrary: MDLVertexDescriptorLibrary!
    public static var MDLVertexDescriptors: MDLVertexDescriptorLibrary {
        return withLock(mdlVertexDescriptorsLock) {
            return _mdlVertexDescriptorLibrary
        }
    }
    
    public static func Initialize() {
        _shaderLibrary = ShaderLibrary()
        _vertexDescriptorLibrary = VertexDescriptorLibrary()
        _renderPipelineStateLibrary = RenderPipelineStateLibrary()
        _computePipelineStateLibrary = ComputePipelineStateLibrary()
        _depthStencilStateLibrary = DepthStencilStateLibrary()
        _samplerStateLibrary = SamplerStateLibrary()
        _mdlVertexDescriptorLibrary = MDLVertexDescriptorLibrary()
    }
}
