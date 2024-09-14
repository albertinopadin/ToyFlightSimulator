//
//  SkySphere.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/2/22.
//

import MetalKit

class SkySphere: GameObject, SkyEntity {
    public var textureType: TextureType
    
    init(textureType: TextureType) {
        self.textureType = textureType
        super.init(name: "SkySphere", modelType: .SkySphere)
        setScale(1000)
    }
}
