//
//  SkySphere.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/2/22.
//

import MetalKit

class SkySphere: GameObject {
    private var _skySphereTextureType: TextureType!
    
    init(skySphereTextureType: TextureType) {
        super.init(name: "SkySphere", meshType: .SkySphere, renderPipelineStateType: .SkySphere)
        _skySphereTextureType = skySphereTextureType
        
        setScale(1000)
    }
    
    override func render(renderCommandEncoder: MTLRenderCommandEncoder, renderPipelineStateType: RenderPipelineStateType) {
        renderCommandEncoder.setFragmentTexture(Assets.Textures[_skySphereTextureType], index: 10)
        super.render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: renderPipelineStateType)
    }
    
    override func renderDepth(renderCommandEncoder: MTLRenderCommandEncoder) {
        // Explicitly No-op here, as depth render will just render the whole SkySphere, which is not what we want
    }
}
