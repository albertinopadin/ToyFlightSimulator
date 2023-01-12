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
    
//    override func render(renderCommandEncoder: MTLRenderCommandEncoder) {
//        renderCommandEncoder.setFragmentTexture(Assets.Textures[_skySphereTextureType], index: 10)
//        super.render(renderCommandEncoder: renderCommandEncoder)
//    }
    
//    override func renderOpaque(renderCommandEncoder: MTLRenderCommandEncoder) {
//        renderCommandEncoder.setFragmentTexture(Assets.Textures[_skySphereTextureType], index: 10)
//        super.renderOpaque(renderCommandEncoder: renderCommandEncoder)
//    }
    
    override func render(renderCommandEncoder: MTLRenderCommandEncoder, renderPipelineStateType: RenderPipelineStateType) {
        renderCommandEncoder.setFragmentTexture(Assets.Textures[_skySphereTextureType], index: 10)
        super.render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: renderPipelineStateType)
    }
}
