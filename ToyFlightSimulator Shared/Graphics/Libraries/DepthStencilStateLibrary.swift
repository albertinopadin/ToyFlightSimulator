//
//  DepthStencilStateLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum DepthStencilStateType {
    case AlwaysNoWrite
    case Less
    case LessEqualWrite
    case LessEqualNoWrite
}

class DepthStencilStateLibrary: Library<DepthStencilStateType, MTLDepthStencilState> {
    private var _library: [DepthStencilStateType: DepthStencilState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(AlwaysNoWrite_DepthStencilState(), forKey: .AlwaysNoWrite)
        _library.updateValue(Less_DepthStencilState(), forKey: .Less)
        _library.updateValue(LessEqualWrite_DepthStencilState(), forKey: .LessEqualWrite)
        _library.updateValue(LessEqualNoWrite_DepthStencilState(), forKey: .LessEqualNoWrite)
    }
    
    override subscript(type: DepthStencilStateType) -> MTLDepthStencilState {
        return _library[type]!.depthStencilState
    }
}

protocol DepthStencilState {
    var depthStencilState: MTLDepthStencilState! { get }
}

class AlwaysNoWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState!
    
    init() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.label = "DepthCompareAlwaysAndNoWriteDepthStencil"
        depthStencilDescriptor.isDepthWriteEnabled = false
        depthStencilDescriptor.depthCompareFunction = .always
        depthStencilDescriptor.backFaceStencil = nil
        depthStencilDescriptor.frontFaceStencil = nil
        depthStencilState = Engine.Device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
}

class Less_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState!
    
    init() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.label = "DepthCompareLessAndWriteDepthStencil"
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilState = Engine.Device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
}

class LessEqualWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState!
    
    init() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.label = "DepthCompareLessEqualAndWriteDepthStencil"
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.depthCompareFunction = .lessEqual
        depthStencilState = Engine.Device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
}

class LessEqualNoWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState!
    
    init() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.label = "DepthCompareLessEqualAndNoWriteDepthStencil"
        depthStencilDescriptor.isDepthWriteEnabled = false
        depthStencilDescriptor.depthCompareFunction = .lessEqual
        depthStencilState = Engine.Device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
}
