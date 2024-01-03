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
    
    override func render(with renderCommandEncoder: MTLRenderCommandEncoder,
                         renderPipelineStateType: RenderPipelineStateType,
                         applyMaterials: Bool = true) {
        renderCommandEncoder.setFragmentTexture(Assets.Textures[_skySphereTextureType], index: 10)
        super.render(with: renderCommandEncoder,
                     renderPipelineStateType: renderPipelineStateType,
                     applyMaterials: applyMaterials)
    }
}
