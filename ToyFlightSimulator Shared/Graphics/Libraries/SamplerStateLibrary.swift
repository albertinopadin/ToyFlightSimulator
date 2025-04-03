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

final class SamplerStateLibrary: Library<SamplerStateType, MTLSamplerState>, @unchecked Sendable {
    private var library: [SamplerStateType: SamplerState] = [:]
    
    override func makeLibrary() {
        library.updateValue(Linear_SamplerState(), forKey: .Linear)
    }
    
    override subscript(type: SamplerStateType) -> MTLSamplerState? {
        return (library[type]?.samplerState)!
    }
}

protocol SamplerState {
    static var name: String { get }
    var samplerState: MTLSamplerState { get }
}

struct Linear_SamplerState: SamplerState {
    static let name: String = "Linear Sampler State"
    var samplerState: MTLSamplerState = {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.lodMinClamp = 0
        samplerDescriptor.label = name
        return Engine.Device.makeSamplerState(descriptor: samplerDescriptor)!
    }()
}
