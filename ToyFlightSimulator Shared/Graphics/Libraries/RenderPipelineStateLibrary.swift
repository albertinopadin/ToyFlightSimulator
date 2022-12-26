//
//  RenderPipelineStateLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum RenderPipelineStateType {
    case Base
    case Material
    case Instanced
    case SkySphere
    case Final
    case DebugDrawing
}

class RenderPipelineStateLibrary: Library<RenderPipelineStateType, MTLRenderPipelineState> {
    private var _library: [RenderPipelineStateType: RenderPipelineState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseRenderPipelineState(), forKey: .Base)
        _library.updateValue(MaterialRenderPipelineState(), forKey: .Material)
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
    
    init(renderPipelineDescriptor: MTLRenderPipelineDescriptor, enableAlphaBlending: Bool = true) {
        if enableAlphaBlending {
            enableBlending(colorAttachmentDescriptor: renderPipelineDescriptor.colorAttachments[0])
        }
        
        do {
            renderPipelineState = try Engine.Device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch let error as NSError {
            print("ERROR::CREATE::RENDER_PIPELINE_STATE::__::\(error)")
        }
    }
    
    func enableBlending(colorAttachmentDescriptor: MTLRenderPipelineColorAttachmentDescriptor) {
        colorAttachmentDescriptor.isBlendingEnabled = true
//        colorAttachmentDescriptor.sourceRGBBlendFactor = .one
        colorAttachmentDescriptor.sourceRGBBlendFactor = .sourceAlpha
        colorAttachmentDescriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachmentDescriptor.rgbBlendOperation = .add
//        colorAttachmentDescriptor.sourceAlphaBlendFactor = .one
        colorAttachmentDescriptor.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachmentDescriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        colorAttachmentDescriptor.alphaBlendOperation = .add
    }
    
    class func getRenderPipelineDescriptor(vertexDescriptorType: VertexDescriptorType,
                                           vertexShaderType: ShaderType,
                                           fragmentShaderType: ShaderType) -> MTLRenderPipelineDescriptor {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.colorAttachments[1].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[vertexDescriptorType]
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[vertexShaderType]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[fragmentShaderType]
        return renderPipelineDescriptor
    }
}

class BaseRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = RenderPipelineState.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                                       vertexShaderType: .BaseVertex,
                                                                                       fragmentShaderType: .BaseFragment)
        renderPipelineDescriptor.label = "Base Render Pipeline Descriptor"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class MaterialRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = RenderPipelineState.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                                       vertexShaderType: .BaseVertex,
                                                                                       fragmentShaderType: .MaterialFragment)
        renderPipelineDescriptor.label = "Material Render Pipeline Descriptor"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class DebugDrawingRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = RenderPipelineState.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                                       vertexShaderType: .BaseVertex,
                                                                                       fragmentShaderType: .DebugDrawingFragment)
        renderPipelineDescriptor.label = "Debug Drawing Render Pipeline Descriptor"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class InstancedRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = RenderPipelineState.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                                       vertexShaderType: .InstancedVertex,
                                                                                       fragmentShaderType: .BaseFragment)
        renderPipelineDescriptor.label = "Instanced Render Pipeline Descriptor"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class SkySphereRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = RenderPipelineState.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                                       vertexShaderType: .SkySphereVertex,
                                                                                       fragmentShaderType: .SkySphereFragment)
        renderPipelineDescriptor.label = "Sky Sphere Render Pipeline Descriptor"
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
