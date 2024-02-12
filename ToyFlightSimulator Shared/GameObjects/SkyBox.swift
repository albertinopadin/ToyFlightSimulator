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
        super.init(name: "SkyBox", meshType: .Skybox, renderPipelineStateType: .Skybox)
        _skyBoxTextureType = skyBoxTextureType
        setPosition(0, 0, -10)
        setScale(1000)
    }
    
    override func render(with renderCommandEncoder: MTLRenderCommandEncoder,
                         renderPipelineStateType: RenderPipelineStateType,
                         applyMaterials: Bool = false) {
        renderCommandEncoder.setFragmentTexture(Assets.Textures[_skyBoxTextureType],
                                                index: TFSTextureIndexBaseColor.index)
        super.render(with: renderCommandEncoder,
                     renderPipelineStateType: renderPipelineStateType,
                     applyMaterials: applyMaterials)
    }
}
