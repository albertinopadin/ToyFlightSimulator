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
    case SkySphere
    case Final
    
    // For order-independent transparency:
    case TileRender
    case Opaque
    case OpaqueMaterial
    case OrderIndependentTransparent
    case Blend
    
    // For Deferred Single-Pass Lighting:
    case ShadowGeneration
    case SinglePassDeferredGBufferBase
    case SinglePassDeferredGBufferMaterial
    case SinglePassDeferredDirectionalLighting
    case SinglePassDeferredTransparency
    case LightMask
    case SinglePassDeferredPointLight
    case Skybox
    
    // For Tiled Deferred:
    case TiledDeferredShadow
    case TiledDeferredGBuffer
    case TiledDeferredDirectionalLight
    case TiledDeferredPointLight
    case TiledDeferredTransparency
    
    // Tiled MSAA:
    case TiledMSAAShadow
    case TiledMSAAGBuffer
    case TiledMSAADirectionalLight
    case TiledMSAAPointLight
    case TiledMSAATransparency
    
    case TiledMSAAAverageResolve
    
    // For testing:
    case Icosahedron
    
    case Particle
    case ParticleMSAA
    
    case Composite
    
    case Tessellation
    case TessellationGBuffer
}

final class RenderPipelineStateLibrary: Library<RenderPipelineStateType, MTLRenderPipelineState>, @unchecked Sendable {
    private var _library: [RenderPipelineStateType: RenderPipelineState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseRenderPipelineState(), forKey: .Base)
        _library.updateValue(MaterialRenderPipelineState(), forKey: .Material)
        _library.updateValue(SkySphereRenderPipelineState(), forKey: .SkySphere)
        _library.updateValue(FinalRenderPipelineState(), forKey: .Final)
        
        _library.updateValue(TileRenderPipelineState(), forKey: .TileRender)
        _library.updateValue(OpaqueRenderPipelineState(), forKey: .Opaque)
        _library.updateValue(OpaqueMaterialRenderPipelineState(), forKey: .OpaqueMaterial)
        _library.updateValue(OrderIndependentTransparencyRenderPipelineState(), forKey: .OrderIndependentTransparent)
        _library.updateValue(BlendRenderPipelineState(), forKey: .Blend)
        
        _library.updateValue(ShadowGenerationRenderPipelineState(), forKey: .ShadowGeneration)
        _library.updateValue(GBufferGenerationBaseRenderPipelineState(), forKey: .SinglePassDeferredGBufferBase)
        _library.updateValue(GBufferGenerationMaterialRenderPipelineState(), forKey: .SinglePassDeferredGBufferMaterial)
        _library.updateValue(DirectionalLightingRenderPipelineState(), forKey: .SinglePassDeferredDirectionalLighting)
        _library.updateValue(TransparencyPipelineState(), forKey: .SinglePassDeferredTransparency)
        _library.updateValue(LightMaskRenderPipelineState(), forKey: .LightMask)
        _library.updateValue(PointLightingRenderPipelineState(), forKey: .SinglePassDeferredPointLight)
        _library.updateValue(SkyboxRenderPipelineState(), forKey: .Skybox)
        
        _library.updateValue(IcosahedronRenderPipelineState(), forKey: .Icosahedron)
        
        _library.updateValue(TiledDeferredShadowPipelineState(), forKey: .TiledDeferredShadow)
        _library.updateValue(TiledDeferredGBufferPipelineState(), forKey: .TiledDeferredGBuffer)
        _library.updateValue(TiledDeferredDirectionalLightPipelineState(), forKey: .TiledDeferredDirectionalLight)
        _library.updateValue(TiledDeferredPointLightPipelineState(), forKey: .TiledDeferredPointLight)
        _library.updateValue(TiledDeferredTransparencyPipelineState(), forKey: .TiledDeferredTransparency)
        
        _library.updateValue(ParticleRenderPipelineState(), forKey: .Particle)
        
        // MSAA:
        _library.updateValue(TiledMSAAShadowPipelineState(), forKey: .TiledMSAAShadow)
        _library.updateValue(TiledMSAAGBufferPipelineState(), forKey: .TiledMSAAGBuffer)
        _library.updateValue(TiledMSAADirectionalLightPipelineState(), forKey: .TiledMSAADirectionalLight)
        _library.updateValue(TiledMSAAPointLightPipelineState(), forKey: .TiledMSAAPointLight)
        _library.updateValue(TiledMSAATransparencyPipelineState(), forKey: .TiledMSAATransparency)
        _library.updateValue(TiledMSAAAverageResolvePipelineState(), forKey: .TiledMSAAAverageResolve)
        _library.updateValue(ParticleMSAARenderPipelineState(), forKey: .ParticleMSAA)
        
        _library.updateValue(TiledMSAACompositePipelineState(), forKey: .Composite)
        
        _library.updateValue(TessellationRenderPipelineState(), forKey: .Tessellation)
        _library.updateValue(TessellationGBufferRenderPipelineState(), forKey: .TessellationGBuffer)
    }
    
    override subscript(type: RenderPipelineStateType) -> MTLRenderPipelineState {
        return _library[type]!.renderPipelineState
    }
}
