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
    
    case SkyMap
}

class TextureLibrary: Library<TextureType, MTLTexture> {
    private var _library: [TextureType: Texture] = [:]
    
    override func makeLibrary() {
        _library.updateValue(Texture("clouds", origin: .bottomLeft), forKey: .Clouds_Skysphere)
        _library.updateValue(Texture(name: "SkyMap", label: "Sky Map"), forKey: .SkyMap)
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
                .origin: _origin as Any,
                .generateMipmaps: true,  // Unoptimized
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
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
