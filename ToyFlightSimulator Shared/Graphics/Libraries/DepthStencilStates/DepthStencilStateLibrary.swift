//
//  DepthStencilStateLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum DepthStencilStateType {
    case AlwaysNoWrite
    case Less
    case LessEqualWrite
    case LessEqualNoWrite
    
    case ShadowGeneration
    case GBufferGeneration
    case DirectionalLighting
    case LightMask
    case PointLight
    case Skybox
    
    case DepthWriteDisabled
    
    case TiledDeferredShadow
    case TiledDeferredGBuffer
    case TiledDeferredLight
}

class DepthStencilStateLibrary: Library<DepthStencilStateType, MTLDepthStencilState> {
    private var _library: [DepthStencilStateType: DepthStencilState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(AlwaysNoWrite_DepthStencilState(), forKey: .AlwaysNoWrite)
        _library.updateValue(Less_DepthStencilState(), forKey: .Less)
        _library.updateValue(LessEqualWrite_DepthStencilState(), forKey: .LessEqualWrite)
        _library.updateValue(LessEqualNoWrite_DepthStencilState(), forKey: .LessEqualNoWrite)
        
        _library.updateValue(ShadowGenerationDepthStencilState(), forKey: .ShadowGeneration)
        _library.updateValue(GBufferGenerationDepthStencilState(), forKey: .GBufferGeneration)
        _library.updateValue(DirectionalLightingDepthStencilState(), forKey: .DirectionalLighting)
        _library.updateValue(LightMaskDepthStencilState(), forKey: .LightMask)
        _library.updateValue(PointLightDepthStencilState(), forKey: .PointLight)
        _library.updateValue(SkyboxDepthStencilState(), forKey: .Skybox)
        
        _library.updateValue(DepthWriteDisabledDepthStencilState(), forKey: .DepthWriteDisabled)
        
        _library.updateValue(TiledDeferredShadowDepthStencilState(), forKey: .TiledDeferredShadow)
        _library.updateValue(TiledDeferredGBufferDepthStencilState(), forKey: .TiledDeferredGBuffer)
        _library.updateValue(TiledDeferredLightingDepthStencilState(), forKey: .TiledDeferredLight)
    }
    
    override subscript(type: DepthStencilStateType) -> MTLDepthStencilState {
        return _library[type]!.depthStencilState
    }
}
