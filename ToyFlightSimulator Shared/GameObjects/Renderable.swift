//
//  Renderable.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

protocol Renderable {
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder, applyMaterials: Bool, submeshesToRender: [String: Bool]?)
    func doRenderShadow(_ renderCommandEncoder: MTLRenderCommandEncoder, submeshesToRender: [String: Bool]?)
}
