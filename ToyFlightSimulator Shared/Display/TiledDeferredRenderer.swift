//
//  TiledDeferredRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//  Heavily inspired from https://www.kodeco.com/books/metal-by-tutorials/v4.0/chapters/15-tile-based-deferred-rendering

import MetalKit

class TiledDeferredRenderer: Renderer {
    init() {
        super.init(type: .TileDeferred)
    }
    
    init(_ mtkView: MTKView) {
        super.init(mtkView, type: .TileDeferred)
    }
}
