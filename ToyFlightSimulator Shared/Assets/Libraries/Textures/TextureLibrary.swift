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
