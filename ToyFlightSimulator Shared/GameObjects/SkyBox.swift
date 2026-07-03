//
//  Skybox.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/14/23.
//

import MetalKit

class SkyBox: GameObject, SkyEntity {
    public var textureType: TextureType {
        didSet { texture = Assets.Textures[textureType] }
    }

    // Resolved at construction (scene build, off the render thread) so the first
    // DrawSky doesn't load the texture mid-encode inside the library lock.
    public private(set) var texture: MTLTexture?

    init(textureType: TextureType) {
        self.textureType = textureType
        super.init(name: "SkyBox", modelType: .Skybox)
        setPosition(0, 0, -10)
        setScale(1000)
        texture = Assets.Textures[textureType]
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
