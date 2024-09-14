//
//  Skybox.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/14/23.
//

import MetalKit

class SkyBox: GameObject, SkyEntity {
    public var textureType: TextureType
    
    init(textureType: TextureType) {
        self.textureType = textureType
        super.init(name: "SkyBox", modelType: .Skybox)
        setPosition(0, 0, -10)
        setScale(1000)
    }
    
    // TODO - Decide on consistent index for sky texture:
//    override func render(with renderEncoder: MTLRenderCommandEncoder,
//                         renderPipelineStateType: RenderPipelineStateType,
//                         applyMaterials: Bool = false) {
//        renderEncoder.setFragmentTexture(Assets.Textures[_skyBoxTextureType],
//                                         index: TFSTextureIndexBaseColor.index)
//        super.render(with: renderEncoder,
//                     renderPipelineStateType: renderPipelineStateType,
//                     applyMaterials: applyMaterials)
//    }
}
