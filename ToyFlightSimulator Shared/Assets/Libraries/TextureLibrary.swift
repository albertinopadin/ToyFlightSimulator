//
//  TextureLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum TextureType {
    case None
    
    case BaseColorRender_0  // colorAttachment[0]
    case BaseColorRender_1
    case BaseDepthRender  // depthAttachment
    
    // Sky Sphere
    case Clouds_Skysphere
    
    case F16
    case F16Canopy
}

class TextureLibrary: Library<TextureType, MTLTexture> {
    private var _library: [TextureType: Texture] = [:]
    
    override func makeLibrary() {
        // How can I load multiple textures for single object/mesh ???
        _library.updateValue(Texture("F16s", ext: "bmp", origin: .bottomLeft), forKey: .F16)
        _library.updateValue(Texture("F16t", ext: "bmp", origin: .bottomLeft), forKey: .F16Canopy)
        _library.updateValue(Texture("clouds", origin: .bottomLeft), forKey: .Clouds_Skysphere)
    }
    
    func setTexture(textureType: TextureType, texture: MTLTexture) {
        _library.updateValue(Texture(texture: texture), forKey: textureType)
    }
    
    override subscript(type: TextureType) -> MTLTexture? {
        return _library[type]?.texture
    }
}

private class Texture {
    var texture: MTLTexture!
    
    init(texture: MTLTexture) {
        self.texture = texture
    }
    
    init(_ textureName: String, ext: String = "png", origin: MTKTextureLoader.Origin = .topLeft) {
        let textureLoader = TextureLoader(textureName: textureName, textureExtension: ext, origin: origin)
        let texture: MTLTexture = textureLoader.loadTextureFromBundle()
        setTexture(texture)
    }
            
    func setTexture(_ texture: MTLTexture) {
        self.texture = texture
    }
}

class TextureLoader {
    private var _textureName: String!
    private var _textureExtension: String!
    private var _origin: MTKTextureLoader.Origin!
    
    init(textureName: String, textureExtension: String = "png", origin: MTKTextureLoader.Origin = .topLeft) {
        self._textureName = textureName
        self._textureExtension = textureExtension
        self._origin = origin
    }
    
    public func loadTextureFromBundle() -> MTLTexture {
        var result: MTLTexture!
        if let url = Bundle.main.url(forResource: _textureName, withExtension: _textureExtension) {
            let textureLoader = MTKTextureLoader(device: Engine.Device)
            let options: [MTKTextureLoader.Option: Any] = [
                MTKTextureLoader.Option.origin: _origin as Any,
                MTKTextureLoader.Option.generateMipmaps: true  // Unoptimized
            ]
            
            do {
                result = try textureLoader.newTexture(URL: url, options: options)
                result.label = _textureName
            } catch let error as NSError {
                print("ERROR::CREATING::TEXTURE::__\(_textureName!)__::\(error)")
            }
        } else {
            print("ERROR::CREATING::TEXTURE::__\(_textureName!) does not exist")
        }
        
        return result
    }
}
