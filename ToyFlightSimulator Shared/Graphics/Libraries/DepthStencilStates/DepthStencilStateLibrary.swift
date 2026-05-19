//
//  DepthStencilStateLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum DepthStencilStateType {
    case AlwaysNoWrite
    case CloserWrite
    case CloserOrEqualWrite
    case CloserNoWrite
    case CloserOrEqualNoWrite
    
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
    case TiledDeferredTransparency
}

final class DepthStencilStateLibrary: Library<DepthStencilStateType, MTLDepthStencilState>, @unchecked Sendable {
    private var _library: [DepthStencilStateType: DepthStencilState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(AlwaysNoWrite_DepthStencilState(), forKey: .AlwaysNoWrite)
        _library.updateValue(CloserWrite_DepthStencilState(), forKey: .CloserWrite)
        _library.updateValue(CloserOrEqualWrite_DepthStencilState(), forKey: .CloserOrEqualWrite)
        _library.updateValue(CloserNoWrite_DepthStencilState(), forKey: .CloserNoWrite)
        _library.updateValue(CloserOrEqualNoWrite_DepthStencilState(), forKey: .CloserOrEqualNoWrite)
        
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
        _library.updateValue(TiledDeferredGBufferTransparencyDepthStencilState(), forKey: .TiledDeferredTransparency)
    }
    
    override subscript(type: DepthStencilStateType) -> MTLDepthStencilState {
        return _library[type]!.depthStencilState
    }
}
