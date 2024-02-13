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
    case GBufferGenerationBase
    case GBufferGenerationMaterial
    case DirectionalLighting
    case LightMask
    case PointLight
    case Skybox
    
    // For testing:
    case Icosahedron
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
        _library.updateValue(GBufferGenerationBaseRenderPipelineState(), forKey: .GBufferGenerationBase)
        _library.updateValue(GBufferGenerationMaterialRenderPipelineState(), forKey: .GBufferGenerationMaterial)
        _library.updateValue(DirectionalLightingRenderPipelineState(), forKey: .DirectionalLighting)
        _library.updateValue(LightMaskRenderPipelineState(), forKey: .LightMask)
        _library.updateValue(PointLightingRenderPipelineState(), forKey: .PointLight)
        _library.updateValue(SkyboxRenderPipelineState(), forKey: .Skybox)
        
        _library.updateValue(IcosahedronRenderPipelineState(), forKey: .Icosahedron)
    }
    
    override subscript(type: RenderPipelineStateType) -> MTLRenderPipelineState {
        return _library[type]!.renderPipelineState
    }
}

protocol RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState { get set }
}

extension RenderPipelineState {
    static func createRenderPipelineState(renderPipelineDescriptor: MTLRenderPipelineDescriptor) -> MTLRenderPipelineState {
        do {
            return try Engine.Device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch let error as NSError {
            fatalError("ERROR::CREATE::RENDER_PIPELINE_STATE::__::\(error) for \(renderPipelineDescriptor.label!)")
        }
    }
    
    static func createRenderPipelineState(tileRenderPipelineDescriptor: MTLTileRenderPipelineDescriptor) ->
        MTLRenderPipelineState {
        do {
            return try Engine.Device.makeRenderPipelineState(tileDescriptor: tileRenderPipelineDescriptor,
                                                             options: .argumentInfo,
                                                             reflection: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    static func createRenderPipelineState(label: String, 
                                          block: (MTLRenderPipelineDescriptor) -> Void) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        block(descriptor)
        do {
            return try Engine.Device.makeRenderPipelineState(descriptor: descriptor)
        } catch let error as NSError {
            fatalError("ERROR::CREATE::RENDER_PIPELINE_STATE::__::\(error) for \(label)")
        }
    }
    
    static func createRenderPipelineState(label: String,
                                          tileBlock: (MTLTileRenderPipelineDescriptor) -> Void) -> MTLRenderPipelineState {
        let descriptor = MTLTileRenderPipelineDescriptor()
        descriptor.label = label
        tileBlock(descriptor)
        do {
            return try Engine.Device.makeRenderPipelineState(tileDescriptor: descriptor,
                                                             options: .argumentInfo,
                                                             reflection: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    static func enableBlending(colorAttachmentDescriptor: MTLRenderPipelineColorAttachmentDescriptor) {
        colorAttachmentDescriptor.isBlendingEnabled = true
        colorAttachmentDescriptor.sourceRGBBlendFactor = .sourceAlpha
        colorAttachmentDescriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachmentDescriptor.rgbBlendOperation = .add
        colorAttachmentDescriptor.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachmentDescriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        colorAttachmentDescriptor.alphaBlendOperation = .add
    }
    
    static func getRenderPipelineDescriptor(vertexDescriptorType: VertexDescriptorType,
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
    
    static func getOpaqueRenderPipelineDescriptor(vertexDescriptorType: VertexDescriptorType,
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
    
    static func setRenderTargetPixelFormats(descriptor: MTLRenderPipelineDescriptor) {
        descriptor.colorAttachments[TFSRenderTargetAlbedo.index].pixelFormat = GBufferTextures.albedoSpecularFormat
        descriptor.colorAttachments[TFSRenderTargetNormal.index].pixelFormat = GBufferTextures.normalShadowFormat
        descriptor.colorAttachments[TFSRenderTargetDepth.index].pixelFormat = GBufferTextures.depthFormat
    }
}

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
        return createRenderPipelineState(label: "Final Render") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.FinalVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.FinalFragment]
        }
    }()
}

struct TileRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "Init Image Block Kernel") { descriptor in
            descriptor.tileFunction = Graphics.Shaders[.TileKernel]
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            descriptor.threadgroupSizeMatchesTileSize = true
        }
    }()
}

struct OpaqueRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                              vertexShaderType: .BaseVertex,
                                                                              fragmentShaderType: .BaseFragment)
        
        renderPipelineDescriptor.label = "Opaque Render"
        return createRenderPipelineState(renderPipelineDescriptor: renderPipelineDescriptor)
    }()
}

struct OpaqueMaterialRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        let renderPipelineDescriptor = Self.getOpaqueRenderPipelineDescriptor(vertexDescriptorType: .Base,
                                                                              vertexShaderType: .BaseVertex,
                                                                              fragmentShaderType: .MaterialFragment)
        
        renderPipelineDescriptor.label = "Opaque Material Render"
        return createRenderPipelineState(renderPipelineDescriptor: renderPipelineDescriptor)
    }()
}

struct OrderIndependentTransparencyRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "Transparent Render") { descriptor in
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.vertexFunction = Graphics.Shaders[.BaseVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.TransparentMaterialFragment]
            
            descriptor.colorAttachments[0].isBlendingEnabled = false
            descriptor.colorAttachments[0].writeMask = MTLColorWriteMask(rawValue: 0)
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            descriptor.stencilAttachmentPixelFormat = .invalid
        }
    }()
}

struct BlendRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "Transparent Fragment Blending") { descriptor in
            descriptor.colorAttachments[0].pixelFormat = Preferences.MainPixelFormat
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthPixelFormat
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.vertexDescriptor = nil
            descriptor.vertexFunction = Graphics.Shaders[.QuadPassVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.BlendFragment]
        }
    }()
}

// -------------- FOR DEFERRED LIGHTING ---------------- //
struct ShadowGenerationRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "Shadow Generation Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.ShadowVertex]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]  // ???
            descriptor.depthAttachmentPixelFormat = .depth32Float
            // TODO: Should I set the render target pixel formats here?
        }
    }()
}

struct GBufferGenerationBaseRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "GBuffer Generation Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.GBufferVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.GBufferFragmentBase]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }()
}

struct GBufferGenerationMaterialRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "GBuffer Generation Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.GBufferVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.GBufferFragmentMaterial]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Base]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }()
}

struct DirectionalLightingRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "Directional Lighting Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.DeferredDirectionalLightingVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.DeferredDirectionalLightingFragment]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }()
}

struct LightMaskRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "Light Mask Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.LightMaskVertex]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }()
}

struct PointLightingRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "Point Lights Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.DeferredPointLightVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.DeferredPointLightFragment]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }()
}

struct SkyboxRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "Skybox Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.SkyboxVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.SkyboxFragment]
            descriptor.vertexDescriptor = Graphics.VertexDescriptors[.Skybox]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }()
}

struct IcosahedronRenderPipelineState: RenderPipelineState {
    var renderPipelineState: MTLRenderPipelineState = {
        return createRenderPipelineState(label: "Icosahedron Stage") { descriptor in
            descriptor.vertexFunction = Graphics.Shaders[.IcosahedronVertex]
            descriptor.fragmentFunction = Graphics.Shaders[.IcosahedronFragment]
            descriptor.depthAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = Preferences.MainDepthStencilPixelFormat
            descriptor.colorAttachments[TFSRenderTargetLighting.index].pixelFormat = Preferences.MainPixelFormat
            Self.setRenderTargetPixelFormats(descriptor: descriptor)
        }
    }()
}
