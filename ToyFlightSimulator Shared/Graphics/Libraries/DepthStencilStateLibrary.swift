//
//  DepthStencilStateLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum DepthStencilStateType {
    case Less
}

class DepthStencilStateLibrary: Library<DepthStencilStateType, MTLDepthStencilState> {
    private var _library: [DepthStencilStateType: DepthStencilState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(Less_DepthStencilState(), forKey: .Less)
    }
    
    override subscript(type: DepthStencilStateType) -> MTLDepthStencilState {
        return _library[type]!.depthStencilState
    }
}

protocol DepthStencilState {
    var depthStencilState: MTLDepthStencilState! { get }
}

class Less_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState!
    
    init() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilState = Engine.Device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
}
