//
//  SkyEntity.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/14/24.
//

import MetalKit

protocol SkyEntity: GameObject {
    var textureType: TextureType { get set }

    /// The resolved sky texture. Implementations resolve it off the render thread
    /// (at construction, and again if textureType changes) so DrawSky can bind it
    /// directly instead of going through the texture library's locked, lazily-
    /// building subscript every frame.
    var texture: MTLTexture? { get }
}
