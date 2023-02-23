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
        setScale(25)
        setPosition(0, 0, 0)
    }
    
    override func render(renderCommandEncoder: MTLRenderCommandEncoder,
                         renderPipelineStateType: RenderPipelineStateType,
                         applyMaterials: Bool = false) {
        if renderPipelineStateType == self._renderPipelineStateType {
            renderCommandEncoder.setFragmentTexture(Assets.Textures[_skyBoxTextureType], index: Int(TFSTextureIndexBaseColor.rawValue))
            super.render(renderCommandEncoder: renderCommandEncoder,
                         renderPipelineStateType: renderPipelineStateType,
                         applyMaterials: applyMaterials)
        }
    }
}
