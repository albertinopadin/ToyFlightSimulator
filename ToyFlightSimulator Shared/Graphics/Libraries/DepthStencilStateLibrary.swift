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
    
    case ShadowGeneration
    case GBufferGeneration
    case DirectionalLighting
    case LightMask
    case PointLight
    case Skybox
    
    case DepthWriteDisabled
}

class DepthStencilStateLibrary: Library<DepthStencilStateType, MTLDepthStencilState> {
    private var _library: [DepthStencilStateType: DepthStencilState] = [:]
    
    override func makeLibrary() {
        _library.updateValue(AlwaysNoWrite_DepthStencilState(), forKey: .AlwaysNoWrite)
        _library.updateValue(Less_DepthStencilState(), forKey: .Less)
        _library.updateValue(LessEqualWrite_DepthStencilState(), forKey: .LessEqualWrite)
        _library.updateValue(LessEqualNoWrite_DepthStencilState(), forKey: .LessEqualNoWrite)
        
        _library.updateValue(ShadowGenerationDepthStencilState(), forKey: .ShadowGeneration)
        _library.updateValue(GBufferGenerationDepthStencilState(), forKey: .GBufferGeneration)
        _library.updateValue(DirectionalLightingDepthStencilState(), forKey: .DirectionalLighting)
        _library.updateValue(LightMaskDepthStencilState(), forKey: .LightMask)
        _library.updateValue(PointLightDepthStencilState(), forKey: .PointLight)
        _library.updateValue(SkyboxDepthStencilState(), forKey: .Skybox)
        
        _library.updateValue(DepthWriteDisabledDepthStencilState(), forKey: .DepthWriteDisabled)
    }
    
    override subscript(type: DepthStencilStateType) -> MTLDepthStencilState {
        return _library[type]!.depthStencilState
    }
}

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

struct AlwaysNoWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareAlwaysAndNoWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilDescriptor.depthCompareFunction = .always
            depthStencilDescriptor.backFaceStencil = nil
            depthStencilDescriptor.frontFaceStencil = nil
        }
    }()
}

struct Less_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareLessAndWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .less
        }
    }()
}

struct LessEqualWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareLessEqualAndWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .lessEqual
        }
    }()
}

struct LessEqualNoWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareLessEqualAndNoWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilDescriptor.depthCompareFunction = .lessEqual
        }
    }()
}

// -------------- FOR DEFERRED LIGHTING ---------------- //
struct ShadowGenerationDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Shadow Generation Stage") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .lessEqual
        }
    }()
}

struct GBufferGenerationDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "GBuffer Generation Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
            stencilStateDescriptor.depthStencilPassOperation = .replace
            
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .less
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }()
}

struct DirectionalLightingDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Directional Lighting Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
            stencilStateDescriptor.stencilCompareFunction = .equal
            stencilStateDescriptor.readMask = 0xFF
            stencilStateDescriptor.writeMask = 0x0
            
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }()
}

struct LightMaskDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Point Light Mask Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
            stencilStateDescriptor.depthFailureOperation = .incrementClamp
            
            depthStencilDescriptor.depthCompareFunction = .lessEqual
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }()
}

struct PointLightDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Point Lights Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
//            stencilStateDescriptor.stencilCompareFunction = .less
            stencilStateDescriptor.stencilCompareFunction = .lessEqual
//            stencilStateDescriptor.stencilCompareFunction = .always
            stencilStateDescriptor.readMask = 0xFF
            stencilStateDescriptor.writeMask = 0x0
            
//            depthStencilDescriptor.depthCompareFunction = .less
            depthStencilDescriptor.depthCompareFunction = .lessEqual
//            depthStencilDescriptor.depthCompareFunction =  .always
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }()
}

struct SkyboxDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Skybox Stage") { depthStencilDescriptor in
            depthStencilDescriptor.depthCompareFunction = .less
        }
    }()
}

struct DepthWriteDisabledDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Depth Write Disabled") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
        }
    }()
}
