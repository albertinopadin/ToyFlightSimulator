//
//  RenderPipelineStateLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum RenderPipelineStateType {
    case Base
    case Instanced
    case SkySphere
    case Final
    case DebugDrawing
}

class RenderPipelineStateLibrary: Library<RenderPipelineStateType, MTLRenderPipelineState> {
    private var _library: [RenderPipelineStateType: RenderPipelineState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseRenderPipelineState(), forKey: .Base)
        _library.updateValue(InstancedRenderPipelineState(), forKey: .Instanced)
        _library.updateValue(SkySphereRenderPipelineState(), forKey: .SkySphere)
        _library.updateValue(FinalRenderPipelineState(), forKey: .Final)
        _library.updateValue(DebugDrawingRenderPipelineState(), forKey: .DebugDrawing)
    }
    
    override subscript(type: RenderPipelineStateType) -> MTLRenderPipelineState {
        return _library[type]!.renderPipelineState
    }
}

class RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState!
    
    init(renderPipelineDescriptor: MTLRenderPipelineDescriptor) {
        do {
            renderPipelineState = try Engine.Device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch let error as NSError {
            print("ERROR::CREATE::RENDER_PIPELINE_STATE::__::\(error)")
        }
    }
}

class BaseRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.label = "Base Render Pipeline Descriptor"
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.colorAttachments[1].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
        
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.BaseVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BaseFragment]
        
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class DebugDrawingRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.label = "Debug Drawing Render Pipeline Descriptor"
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.colorAttachments[1].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
        
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.BaseVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.DebugDrawingFragment]
        
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class InstancedRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.label = "Instanced Render Pipeline Descriptor"
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.colorAttachments[1].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
        
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.InstancedVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BaseFragment]
        
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class SkySphereRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.label = "Sky Sphere Render Pipeline Descriptor"
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.colorAttachments[1].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
        
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.SkySphereVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.SkySphereFragment]
        
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class FinalRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.label = "Final Render Pipeline Descriptor"
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
        
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
        
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}
