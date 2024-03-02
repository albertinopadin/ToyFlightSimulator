//
//  SinglePassDeferredDepthStencils.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

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
