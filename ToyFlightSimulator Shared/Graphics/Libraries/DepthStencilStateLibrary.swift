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
    }
    
    override subscript(type: DepthStencilStateType) -> MTLDepthStencilState {
        return _library[type]!.depthStencilState
    }
}

class DepthStencilState {
    var depthStencilState: MTLDepthStencilState!
    
    func makeDepthStencilState(label: String, block: (MTLDepthStencilDescriptor) -> Void) -> MTLDepthStencilState {
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

class AlwaysNoWrite_DepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "DepthCompareAlwaysAndNoWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilDescriptor.depthCompareFunction = .always
            depthStencilDescriptor.backFaceStencil = nil
            depthStencilDescriptor.frontFaceStencil = nil
        }
    }
}

class Less_DepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "DepthCompareLessAndWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .less
        }
    }
}

class LessEqualWrite_DepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "DepthCompareLessEqualAndWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .lessEqual
        }
    }
}

class LessEqualNoWrite_DepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "DepthCompareLessEqualAndNoWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilDescriptor.depthCompareFunction = .lessEqual
        }
    }
}

// -------------- FOR DEFERRED LIGHTING ---------------- //
class ShadowGenerationDepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "Shadow Generation Stage") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .lessEqual
        }
    }
}

class GBufferGenerationDepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "GBuffer Generation Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
            stencilStateDescriptor.depthStencilPassOperation = .replace
            
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .less
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }
}

class DirectionalLightingDepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "Directional Lighting Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
            stencilStateDescriptor.stencilCompareFunction = .equal
            stencilStateDescriptor.readMask = 0xFF
            stencilStateDescriptor.writeMask = 0x0
            
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }
}

class LightMaskDepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "Point Light Mask Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
            stencilStateDescriptor.depthFailureOperation = .incrementClamp
            
            depthStencilDescriptor.depthCompareFunction = .lessEqual
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }
}

class PointLightDepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "Point Lights Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
            stencilStateDescriptor.stencilCompareFunction = .less
            stencilStateDescriptor.readMask = 0xFF
            stencilStateDescriptor.writeMask = 0x0
            
            depthStencilDescriptor.depthCompareFunction = .lessEqual
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }
}

class SkyboxDepthStencilState: DepthStencilState {
    override init() {
        super.init()
        depthStencilState = makeDepthStencilState(label: "Skybox Stage") { depthStencilDescriptor in
            depthStencilDescriptor.depthCompareFunction = .less
        }
    }
}
