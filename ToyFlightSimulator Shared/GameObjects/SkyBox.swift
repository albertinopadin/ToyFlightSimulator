//
//  Skybox.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/14/23.
//

import MetalKit

class SkyBox: GameObject {
    private var _skyBoxTextureType: TextureType!
    
    init(skyBoxTextureType: TextureType) {
        super.init(name: "SkyBox", modelType: .Skybox, renderPipelineStateType: .Skybox)
        _skyBoxTextureType = skyBoxTextureType
        setPosition(0, 0, -10)
        setScale(1000)
    }
    
    override func render(with renderEncoder: MTLRenderCommandEncoder,
                         renderPipelineStateType: RenderPipelineStateType,
                         applyMaterials: Bool = false) {
        renderEncoder.setFragmentTexture(Assets.Textures[_skyBoxTextureType],
                                         index: TFSTextureIndexBaseColor.index)
        super.render(with: renderEncoder,
                     renderPipelineStateType: renderPipelineStateType,
                     applyMaterials: applyMaterials)
    }
}
