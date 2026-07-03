//
//  SkySphere.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/2/22.
//

import MetalKit

class SkySphere: GameObject, SkyEntity {
    public var textureType: TextureType {
        didSet { texture = Assets.Textures[textureType] }
    }

    // Resolved at construction (scene build, off the render thread) so the first
    // DrawSky doesn't load the texture mid-encode inside the library lock.
    public private(set) var texture: MTLTexture?

    init(textureType: TextureType) {
        self.textureType = textureType
        super.init(name: "SkySphere", modelType: .SkySphere)
        setScale(1000)
        texture = Assets.Textures[textureType]
    }
}
