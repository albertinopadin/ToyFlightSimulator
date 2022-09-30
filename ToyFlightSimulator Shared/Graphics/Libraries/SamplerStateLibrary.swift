//
//  SamplerStateLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum SamplerStateType {
    case None
    case Linear
}

class SamplerStateLibrary: Library<SamplerStateType, MTLSamplerState> {
    private var library: [SamplerStateType: SamplerState] = [:]
    
    override func makeLibrary() {
        library.updateValue(Linear_SamplerState(), forKey: .Linear)
    }
    
    override subscript(type: SamplerStateType) -> MTLSamplerState? {
        return (library[type]?.samplerState!)!
    }
}

protocol SamplerState {
    var name: String { get }
    var samplerState: MTLSamplerState! { get }
}

class Linear_SamplerState: SamplerState {
    var name: String = "Linear Sampler State"
    var samplerState: MTLSamplerState!
    
    init() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.lodMinClamp = 0
        samplerDescriptor.label = name
        samplerState = Engine.Device.makeSamplerState(descriptor: samplerDescriptor)
    }
}
