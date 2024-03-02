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
    
    // TODO: Clean this up later
    init(name: String, label: String, scale: CGFloat = 1.0) {
        let textureLoader = MTKTextureLoader(device: Engine.Device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]
        
        var result: MTLTexture!
        do {
            result = try textureLoader.newTexture(name: name, scaleFactor: scale, bundle: nil, options: options)
            result.label = label
        } catch {
            fatalError("Failed to create texture: \(error.localizedDescription)")
        }
        
        self.texture = result
    }
            
    func setTexture(_ texture: MTLTexture) {
        self.texture = texture
    }
}
