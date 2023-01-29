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
    
    // For Deferred Lighting:
    case ShadowGeneration
    case GBufferGeneration
    case DirectionalLighting
    case LightMask
    case PointLight
    case Skybox
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
        
        _library.updateValue(ShadowGenerationRenderPipelineState(), forKey: .ShadowGeneration)
        _library.updateValue(GBufferGenerationRenderPipelineState(), forKey: .GBufferGeneration)
        _library.updateValue(DirectionalLightingRenderPipelineState(), forKey: .DirectionalLighting)
        _library.updateValue(LightMaskRenderPipelineState(), forKey: .LightMask)
        _library.updateValue(PointLightingRenderPipelineState(), forKey: .PointLight)
        _library.updateValue(SkyboxRenderPipelineState(), forKey: .Skybox)
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
    
    init(tileRenderPipelineDescriptor: MTLTileRenderPipelineDescriptor) {
        do {
            renderPipelineState = try Engine.Device.makeRenderPipelineState(tileDescriptor: tileRenderPipelineDescriptor,
                                                                            options: .argumentInfo,
                                                                            reflection: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    init(label: String, block: (MTLRenderPipelineDescriptor) -> Void) {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        block(descriptor)
        do {
            renderPipelineState = try Engine.Device.makeRenderPipelineState(descriptor: descriptor)
        } catch let error as NSError {
            print("ERROR::CREATE::RENDER_PIPELINE_STATE::__::\(error)")
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
        colorAttachmentDescriptor.sourceRGBBlendFactor = .sourceAlpha
        colorAttachmentDescriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachmentDescriptor.rgbBlendOperation = .add
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
    
    class func setRenderTargetPixelFormats(descriptor: MTLRenderPipelineDescriptor) {
        descriptor.colorAttachments[Int(TFSRenderTargetAlbedo.rawValue)].pixelFormat = GBufferTextures.albedoSpecularFormat
        descriptor.colorAttachments[Int(TFSRenderTargetNormal.rawValue)].pixelFormat = GBufferTextures.normalShadowFormat
        descriptor.colorAttachments[Int(TFSRenderTargetDepth.rawValue)].pixelFormat = GBufferTextures.depthFormat
    }
}

class BaseRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = RenderPipelineState.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                                       vertexShaderType: .BaseVertex,
                                                                                       fragmentShaderType: .BaseFragment)
        renderPipelineDescriptor.label = "Base Render"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class MaterialRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = RenderPipelineState.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                                       vertexShaderType: .BaseVertex,
                                                                                       fragmentShaderType: .MaterialFragment)
        renderPipelineDescriptor.label = "Material Render"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class InstancedRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = RenderPipelineState.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                                       vertexShaderType: .InstancedVertex,
                                                                                       fragmentShaderType: .BaseFragment)
        renderPipelineDescriptor.label = "Instanced Render"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class SkySphereRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor = RenderPipelineState.getRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                                       vertexShaderType: .SkySphereVertex,
                                                                                       fragmentShaderType: .SkySphereFragment)
        renderPipelineDescriptor.label = "Sky Sphere Render"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class FinalRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "Final Render") { descriptor in
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
        
        renderPipelineDescriptor.label = "Opaque Render"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class OpaqueMaterialRenderPipelineState: RenderPipelineState {
    init() {
        let renderPipelineDescriptor =
            RenderPipelineState.getOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                  vertexShaderType: .BaseVertex,
                                                                  fragmentShaderType: .MaterialFragment)
        
        renderPipelineDescriptor.label = "Opaque Material Render"
        super.init(renderPipelineDescriptor: renderPipelineDescriptor)
    }
}

class OrderIndependentTransparencyRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "Transparent Render") { descriptor in
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
        super.init(label: "Transparent Fragment Blending") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexDescriptor = nil
            descriptor.vertexFunction = Graphics.Shaders[.QuadPassVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BlendFragment]
        }
    }
}

// -------------- FOR DEFERRED LIGHTING ---------------- //
class ShadowGenerationRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "Shadow Generation Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.ShadowVertex]
            descriptor.depthAttachmentPixelFormat = .depth32Float
        }
    }
}

class GBufferGenerationRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "GBuffer Generation Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.GBufferVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.GBufferFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[Int(TFSRenderTargetLighting.rawValue)].pixelFormat = Preferences.MainPixelFormat
            RenderPipelineState.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }
}

class DirectionalLightingRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "Directional Lighting Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.DeferredDirectionalLightingVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.DeferredDirectionalLightingFragment]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[Int(TFSRenderTargetLighting.rawValue)].pixelFormat = Preferences.MainPixelFormat
            RenderPipelineState.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }
}

class LightMaskRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "Light Mask Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.LightMaskVertex]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[Int(TFSRenderTargetLighting.rawValue)].pixelFormat = Preferences.MainPixelFormat
            RenderPipelineState.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }
}

class PointLightingRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "Point Lights Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.DeferredPointLightVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.DeferredPointLightFragment]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[Int(TFSRenderTargetLighting.rawValue)].pixelFormat = Preferences.MainPixelFormat
            RenderPipelineState.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }
}

class SkyboxRenderPipelineState: RenderPipelineState {
    init() {
        super.init(label: "Skybox Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.SkyboxVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SkyboxFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Skybox]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[Int(TFSRenderTargetLighting.rawValue)].pixelFormat = Preferences.MainPixelFormat
            RenderPipelineState.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }
}
