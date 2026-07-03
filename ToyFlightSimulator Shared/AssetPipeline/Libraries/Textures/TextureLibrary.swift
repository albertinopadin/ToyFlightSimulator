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
    
    // Terrain
    case MountainHeightMap
    
    case Grass
    case Cliff
    case Snow
}

// File-backed textures are loaded on first request (lazy load); render-target
// textures created at runtime are injected via setTexture(...). The inherited
// LazyLibrary subscript serves both from the same cache.
final class TextureLibrary: LazyLibrary<TextureType, MTLTexture>, @unchecked Sendable {
    override func makeLibrary() {
        register(.Clouds_Skysphere)  { Texture("clouds", origin: .bottomLeft).texture }
        register(.SkyMap)            { Texture(name: "SkyMap", label: "Sky Map").texture }
        register(.MountainHeightMap) { Texture(name: "mountain").texture }
        register(.Grass)             { Texture(name: "grass-color").texture }
        register(.Cliff)             { Texture(name: "cliff-color").texture }
        register(.Snow)              { Texture(name: "snow-color").texture }
    }

    // Render-target textures created at runtime are injected straight into the cache.
    func setTexture(textureType: TextureType, texture: MTLTexture) {
        setResolved(textureType, texture)
    }
}
