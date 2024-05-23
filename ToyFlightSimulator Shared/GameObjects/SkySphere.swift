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
    
    override func render(with renderEncoder: MTLRenderCommandEncoder,
                         renderPipelineStateType: RenderPipelineStateType,
                         applyMaterials: Bool = true) {
        renderEncoder.setFragmentTexture(Assets.Textures[_skySphereTextureType], index: 10)
        super.render(with: renderEncoder,
                     renderPipelineStateType: renderPipelineStateType,
                     applyMaterials: applyMaterials)
    }
}
