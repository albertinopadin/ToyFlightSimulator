//
//  TextureLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit
import os

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

final class TextureLibrary: Library<TextureType, MTLTexture>, @unchecked Sendable {
    // Factories describe *how* to build each file-backed texture; they are not
    // invoked until that texture is first requested (lazy load).
    private var _factories: [TextureType: () -> Texture] = [:]
    // Resolved textures: lazily-built file-backed textures plus render-target
    // textures injected at runtime via setTexture(...).
    private var _cache: [TextureType: Texture] = [:]
    private let _lock = OSAllocatedUnfairLock()

    override func makeLibrary() {
        _factories[.Clouds_Skysphere]  = { Texture("clouds", origin: .bottomLeft) }
        _factories[.SkyMap]            = { Texture(name: "SkyMap", label: "Sky Map") }
        _factories[.MountainHeightMap] = { Texture(name: "mountain") }
        _factories[.Grass]             = { Texture(name: "grass-color") }
        _factories[.Cliff]             = { Texture(name: "cliff-color") }
        _factories[.Snow]              = { Texture(name: "snow-color") }
    }

    // Render-target textures created at runtime are injected straight into the cache.
    func setTexture(textureType: TextureType, texture: MTLTexture) {
        withLock(_lock) {
            _cache[textureType] = Texture(texture: texture)
        }
    }

    override subscript(type: TextureType) -> MTLTexture? {
        withLock(_lock) {
            if let cached = _cache[type] { return cached.texture }
            guard let factory = _factories[type] else { return nil }
            let texture = factory()
            _cache[type] = texture
            return texture.texture
        }
    }
}
