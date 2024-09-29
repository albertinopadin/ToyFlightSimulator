//
//  RendererType.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/14/23.
//

enum RendererType: String, CaseIterable, Identifiable {
    case OrderIndependentTransparency = "Order Independent Transparency"
    case SinglePassDeferredLighting = "Single-Pass Deferred Lighting"
    case TiledDeferred = "Tile Deferred"
    case TiledDeferredMSAA = "Tiled Deferred MSAA"
    case ForwardPlusTileShading = "Forward+"
    
    var id: String { rawValue }
}
