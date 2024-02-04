//
//  ForwardPlusTileShadingRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/2/24.
//

import MetalKit

class ForwardPlusTileShadingRenderer: Renderer {
    init() {
        super.init(type: .ForwardPlusTileShading)
    }
    
    init(_ mtkView: MTKView) {
        super.init(mtkView, type: .ForwardPlusTileShading)
    }
}
