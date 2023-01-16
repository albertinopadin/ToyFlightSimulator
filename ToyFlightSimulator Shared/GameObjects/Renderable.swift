//
//  Renderable.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

protocol Renderable {
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder)
    func doRenderShadow(renderCommandEncoder: MTLRenderCommandEncoder, shadowViewProjectionMatrix: float4x4)
    func doRenderDepth(_ renderCommandEncoder: MTLRenderCommandEncoder)
}
