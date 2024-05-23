//
//  Renderable.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

protocol Renderable {
    func doRender(_ renderEncoder: MTLRenderCommandEncoder, applyMaterials: Bool, submeshesToRender: [String: Bool]?)
    func doRenderShadow(_ renderEncoder: MTLRenderCommandEncoder, submeshesToRender: [String: Bool]?)
}
