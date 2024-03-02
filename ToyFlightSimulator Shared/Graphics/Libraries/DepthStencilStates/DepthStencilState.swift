//
//  DepthStencilState.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

protocol DepthStencilState {
    var depthStencilState: MTLDepthStencilState { get set }
}

extension DepthStencilState {
    static func makeDepthStencilState(label: String, block: (MTLDepthStencilDescriptor) -> Void) -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = label
        block(descriptor)
        if let depthStencilState = Engine.Device.makeDepthStencilState(descriptor: descriptor) {
            return depthStencilState
        } else {
            fatalError("Failed to create depth stencil state.")
        }
    }
}
