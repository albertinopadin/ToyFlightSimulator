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
    
    init(label: String, block: (MTLRenderPipelineDescriptor) -> Void) {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        block(descriptor)
        do {
            renderPipelineState = try Engine.Device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    init(label: String, tileBlock: (MTLTileRenderPipelineDescriptor) -> Void) {
        let descriptor = MTLTileRenderPipelineDescriptor()
        descriptor.label = label
        tileBlock(descriptor)
        do {
            renderPipelineState = try Engine.Device.makeRenderPipelineState(tileDescriptor: descriptor,
                                                                            options: .argumentInfo,
                                                                            reflection: nil)
        } catch {
            fatalError(error.localizedDescription)
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
        super.init(label: "Final Render Pipeline Descriptor") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
        }
    }
}

class TileRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "Init Image Block Kernel") { descriptor in
            descriptor.tileFunction = Graphics.Shaders[.TileKernel]
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            descriptor.threadgroupSizeMatchesTileSize = true
        }
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
        super.init(label: "Transparent Render Pipline Descriptor") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.BaseVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TransparentMaterialFragment]
            
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.colorAttachments[0].writeMask = MTLColorWriteMask(rawValue: 0)
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            descriptor.stencilAttachmentPixelFormat = .invalid
        }
    }
}

class BlendRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "Transparent Fragment Blending Descriptor") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexDescriptor = nil
            descriptor.vertexFunction = Graphics.Shaders[.QuadPassVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BlendFragment]
        }
    }
}
