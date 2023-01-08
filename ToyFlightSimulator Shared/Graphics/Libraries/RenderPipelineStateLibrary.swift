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
    
    // For order-independent transparency:
    case TileRender
    case Opaque
    case OpaqueMaterial
    case OrderIndependentTransparent
    case Blend
}

class RenderPipelineStateLibrary: Library<RenderPipelineStateType, MTLRenderPipelineState> {
    private var _library: [RenderPipelineStateType: RenderPipelineState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseRenderPipelineState(), forKey: .Base)
        _library.updateValue(MaterialRenderPipelineState(), forKey: .Material)
        _library.updateValue(InstancedRenderPipelineState(), forKey: .Instanced)
        _library.updateValue(SkySphereRenderPipelineState(), forKey: .SkySphere)
        _library.updateValue(FinalRenderPipelineState(), forKey: .Final)
        
        _library.updateValue(TileRenderPipelineState(), forKey: .TileRender)
        _library.updateValue(OpaqueRenderPipelineState(), forKey: .Opaque)
        _library.updateValue(OpaqueMaterialRenderPipelineState(), forKey: .OpaqueMaterial)
        _library.updateValue(OrderIndependentTransparencyRenderPipelineState(), forKey: .OrderIndependentTransparent)
        _library.updateValue(BlendRenderPipelineState(), forKey: .Blend)
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
    
    init(tilePipelineDescriptor: MTLTileRenderPipelineDescriptor) {
        do {
            renderPipelineState = try Engine.Device.makeRenderPipelineState(tileDescriptor: tilePipelineDescriptor,
                                                                            options: .argumentInfo,
                                                                            reflection: nil)
        } catch let error as NSError {
            print("ERROR::CREATE::RENDER_PIPELINE_STATE_WITH_TILE_DESC::__::\(error)")
        }
    }
    
    class func enableBlending(colorAttachmentDescriptor: MTLRenderPipelineColorAttachmentDescriptor) {
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
                                           fragmentShaderType: ShaderType,
                                           enableAlphaBlending: Bool = true,
                                           colorAttachments: Int = 1) -> MTLRenderPipelineDescriptor {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        for i in 0..<colorAttachments {
            renderPipelineDescriptor.colorAttachments[i].pixelFormat = Preferences.MainPixelFormat
        }
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[vertexDescriptorType]
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[vertexShaderType]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[fragmentShaderType]
        
        if enableAlphaBlending {
            enableBlending(colorAttachmentDescriptor: renderPipelineDescriptor.colorAttachments[0])
        }
        
        return renderPipelineDescriptor
    }
    
    class func getOpaqueRenderPipelineDescriptor(vertexDescriptorType: VertexDescriptorType,
                                                 vertexShaderType: ShaderType,
                                                 fragmentShaderType: ShaderType) -> MTLRenderPipelineDescriptor {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[vertexDescriptorType]
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[vertexShaderType]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[fragmentShaderType]
//        RenderPipelineState.enableBlending(colorAttachmentDescriptor: renderPipelineDescriptor.colorAttachments[0])
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        renderPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        renderPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .zero
        renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        renderPipelineDescriptor.colorAttachments[0].writeMask = .all
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

class TileRenderPipelineState: RenderPipelineState {
    init() {
        let tileRenderPipelineDescriptor = MTLTileRenderPipelineDescriptor()
        tileRenderPipelineDescriptor.label = "Init Image Block Kernel"
        tileRenderPipelineDescriptor.tileFunction = Graphics.Shaders[.TileKernel]
        tileRenderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        tileRenderPipelineDescriptor.threadgroupSizeMatchesTileSize = true
        super.init(tilePipelineDescriptor: tileRenderPipelineDescriptor)
    }
}

class OpaqueRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor =
            RenderPipelineState.getOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                  vertexShaderType: .BaseVertex,
                                                                  fragmentShaderType: .BaseFragment)
        
        renderPipelineDescriptor.label = "Opaque Render Pipline Descriptor"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class OpaqueMaterialRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor =
            RenderPipelineState.getOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                  vertexShaderType: .BaseVertex,
                                                                  fragmentShaderType: .MaterialFragment)
        
        renderPipelineDescriptor.label = "Opaque Material Render Pipline Descriptor"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class OrderIndependentTransparencyRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.BaseVertex]
//        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.TransparentFragment]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.TransparentMaterialFragment]
        
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.colorAttachments[0].writeMask = MTLColorWriteMask(rawValue: 0)
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        
        renderPipelineDescriptor.label = "Transparent Render Pipline Descriptor"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class BlendRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
        renderPipelineDescriptor.vertexDescriptor = nil
        renderPipelineDescriptor.vertexFunction = Graphics.Shaders[.QuadPassVertex]
        renderPipelineDescriptor.fragmentFunction = Graphics.Shaders[.BlendFragment]
        
        renderPipelineDescriptor.label = "Transparent Fragment Blending Descriptor"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

