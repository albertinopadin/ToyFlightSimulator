//
//  Texture.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

public class Texture {
    var texture: MTLTexture!
    
    init(texture: MTLTexture) {
        self.texture = texture
    }
    
    init(_ textureName: String, ext: String = "png", origin: MTKTextureLoader.Origin = .topLeft) {
        let textureLoader = TextureLoader(textureName: textureName, textureExtension: ext, origin: origin)
        let texture: MTLTexture = textureLoader.loadTextureFromBundle()
        setTexture(texture)
    }
    
    init(name: String, label: String, scale: CGFloat = 1.0) {
        self.texture = TextureLoader.LoadTexture(name: name, scale: scale)
        self.texture.label = label
    }
            
    func setTexture(_ texture: MTLTexture) {
        self.texture = texture
    }
}
