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
    
    // For Deferred Single-Pass Lighting:
    case ShadowGeneration
    case SinglePassDeferredGBufferBase
    case SinglePassDeferredGBufferMaterial
    case SinglePassDeferredDirectionalLighting
    case LightMask
    case SinglePassDeferredPointLight
    case Skybox
    
    // For Tiled Deferred:
    case TiledDeferredGBuffer
    case TiledDeferredDirectionalLight
    case TiledDeferredPointLight
    
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
        _library.updateValue(GBufferGenerationBaseRenderPipelineState(), forKey: .SinglePassDeferredGBufferBase)
        _library.updateValue(GBufferGenerationMaterialRenderPipelineState(), forKey: .SinglePassDeferredGBufferMaterial)
        _library.updateValue(DirectionalLightingRenderPipelineState(), forKey: .SinglePassDeferredDirectionalLighting)
        _library.updateValue(LightMaskRenderPipelineState(), forKey: .LightMask)
        _library.updateValue(PointLightingRenderPipelineState(), forKey: .SinglePassDeferredPointLight)
        _library.updateValue(SkyboxRenderPipelineState(), forKey: .Skybox)
        
        _library.updateValue(IcosahedronRenderPipelineState(), forKey: .Icosahedron)
    }
    
    override subscript(type: RenderPipelineStateType) -> MTLRenderPipelineState {
        return _library[type]!.renderPipelineState
    }
}
