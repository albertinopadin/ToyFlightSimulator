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
    case OpaqueMaterialAnimated
    case OrderIndependentTransparent
    case OrderIndependentTransparentAnimated
    case Blend

    // For Deferred Single-Pass Lighting:
    case ShadowGeneration
    case SinglePassDeferredGBufferBase
    case SinglePassDeferredGBufferMaterial
    case SinglePassDeferredGBufferMaterialAnimated
    case SinglePassDeferredDirectionalLighting
    case SinglePassDeferredTransparency
    case SinglePassDeferredTransparencyAnimated
    case LightMask
    case SinglePassDeferredPointLight
    case Skybox
    
    // For Tiled Deferred:
    case TiledDeferredShadow
    case TiledDeferredGBuffer
    case TiledDeferredGBufferAnimated
    case TiledDeferredDirectionalLight
    case TiledDeferredPointLight
    case TiledDeferredTransparency
    
    // Tiled MSAA:
    case TiledMSAAShadow
    case TiledMSAAShadowAnimated
    case TiledMSAAGBuffer
    case TiledMSAAGBufferAnimated
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

extension RenderPipelineStateType {
    /// Skinned-mesh variant of a pass PSO, nil when the pass has none.
    /// DrawManager.SetupAnimation derives its PSO swap from this so every
    /// renderer family binds an attachment-compatible animated pipeline
    /// (a hardcoded MSAA-family type bound 4x/shadow PSOs into mismatched
    /// passes — the renderer-switch validation assert).
    /// Transparency stages map to the GBuffer-animated PSO because they run
    /// in the same tile encoder with the same attachments. All shadow passes
    /// share one animated PSO: every cascade pass has the same attachment
    /// layout (no color, depth32Float, sample count 1).
    var animatedVariant: RenderPipelineStateType? {
        switch self {
            case .TiledMSAAGBuffer, .TiledMSAATransparency:
                return .TiledMSAAGBufferAnimated
            case .TiledDeferredGBuffer, .TiledDeferredTransparency:
                return .TiledDeferredGBufferAnimated
            case .TiledMSAAShadow, .TiledDeferredShadow, .ShadowGeneration:
                return .TiledMSAAShadowAnimated
            case .OpaqueMaterial:
                return .OpaqueMaterialAnimated
            case .OrderIndependentTransparent:
                return .OrderIndependentTransparentAnimated
            case .SinglePassDeferredGBufferMaterial:
                return .SinglePassDeferredGBufferMaterialAnimated
            case .SinglePassDeferredTransparency:
                return .SinglePassDeferredTransparencyAnimated
            default:
                return nil
        }
    }

    /// True for exactly the animated PSOs SetupAnimation can have bound.
    var isAnimatedVariant: Bool {
        switch self {
            case .TiledMSAAGBufferAnimated, .TiledDeferredGBufferAnimated, .TiledMSAAShadowAnimated,
                 .OpaqueMaterialAnimated, .OrderIndependentTransparentAnimated,
                 .SinglePassDeferredGBufferMaterialAnimated, .SinglePassDeferredTransparencyAnimated:
                return true
            default:
                return false
        }
    }
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
        _library.updateValue(OpaqueMaterialAnimatedRenderPipelineState(), forKey: .OpaqueMaterialAnimated)
        _library.updateValue(OrderIndependentTransparencyRenderPipelineState(), forKey: .OrderIndependentTransparent)
        _library.updateValue(OrderIndependentTransparencyAnimatedRenderPipelineState(),
                             forKey: .OrderIndependentTransparentAnimated)
        _library.updateValue(BlendRenderPipelineState(), forKey: .Blend)
        
        _library.updateValue(ShadowGenerationRenderPipelineState(), forKey: .ShadowGeneration)
        _library.updateValue(GBufferGenerationBaseRenderPipelineState(), forKey: .SinglePassDeferredGBufferBase)
        _library.updateValue(GBufferGenerationMaterialRenderPipelineState(), forKey: .SinglePassDeferredGBufferMaterial)
        _library.updateValue(GBufferGenerationMaterialAnimatedRenderPipelineState(),
                             forKey: .SinglePassDeferredGBufferMaterialAnimated)
        _library.updateValue(DirectionalLightingRenderPipelineState(), forKey: .SinglePassDeferredDirectionalLighting)
        _library.updateValue(TransparencyPipelineState(), forKey: .SinglePassDeferredTransparency)
        _library.updateValue(TransparencyAnimatedPipelineState(), forKey: .SinglePassDeferredTransparencyAnimated)
        _library.updateValue(LightMaskRenderPipelineState(), forKey: .LightMask)
        _library.updateValue(PointLightingRenderPipelineState(), forKey: .SinglePassDeferredPointLight)
        _library.updateValue(SkyboxRenderPipelineState(), forKey: .Skybox)
        
        _library.updateValue(IcosahedronRenderPipelineState(), forKey: .Icosahedron)
        
        _library.updateValue(TiledDeferredShadowPipelineState(), forKey: .TiledDeferredShadow)
        _library.updateValue(TiledDeferredGBufferPipelineState(), forKey: .TiledDeferredGBuffer)
        _library.updateValue(TiledDeferredGBufferAnimatedPipelineState(), forKey: .TiledDeferredGBufferAnimated)
        _library.updateValue(TiledDeferredDirectionalLightPipelineState(), forKey: .TiledDeferredDirectionalLight)
        _library.updateValue(TiledDeferredPointLightPipelineState(), forKey: .TiledDeferredPointLight)
        _library.updateValue(TiledDeferredTransparencyPipelineState(), forKey: .TiledDeferredTransparency)
        
        _library.updateValue(ParticleRenderPipelineState(), forKey: .Particle)
        
        // MSAA:
        _library.updateValue(TiledMSAAShadowPipelineState(), forKey: .TiledMSAAShadow)
        _library.updateValue(TiledMSAAShadowAnimatedPipelineState(), forKey: .TiledMSAAShadowAnimated)
        _library.updateValue(TiledMSAAGBufferPipelineState(), forKey: .TiledMSAAGBuffer)
        _library.updateValue(TiledMSAAGBufferAnimatedPipelineState(), forKey: .TiledMSAAGBufferAnimated)
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
