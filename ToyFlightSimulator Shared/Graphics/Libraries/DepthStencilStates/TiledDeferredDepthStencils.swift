//
//  TiledDeferredDepthStencils.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

struct TiledDeferredShadowDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Tiled Deferred Shadow") { depthStencilDescriptor in
            depthStencilDescriptor.depthCompareFunction = .less
            depthStencilDescriptor.isDepthWriteEnabled = true
        }
    }()
}

struct TiledDeferredGBufferDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Tiled Deferred GBuffer") { depthStencilDescriptor in
            depthStencilDescriptor.depthCompareFunction = .less
            depthStencilDescriptor.isDepthWriteEnabled = true
            
            let frontFaceStencil = MTLStencilDescriptor()
            frontFaceStencil.stencilCompareFunction = .always
            frontFaceStencil.stencilFailureOperation = .keep
            frontFaceStencil.depthFailureOperation = .keep
            frontFaceStencil.depthStencilPassOperation = .incrementClamp
            
            depthStencilDescriptor.frontFaceStencil = frontFaceStencil
        }
    }()
}

struct TiledDeferredLightingDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Tiled Deferred Lighting") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            
            let frontFaceStencil = MTLStencilDescriptor()
//            frontFaceStencil.stencilCompareFunction = .notEqual  // This prevents the groung from rendering
            frontFaceStencil.stencilCompareFunction = .always
            frontFaceStencil.stencilFailureOperation = .keep
            frontFaceStencil.depthFailureOperation = .keep
            frontFaceStencil.depthStencilPassOperation = .keep
            
            depthStencilDescriptor.frontFaceStencil = frontFaceStencil
        }
    }()
}
