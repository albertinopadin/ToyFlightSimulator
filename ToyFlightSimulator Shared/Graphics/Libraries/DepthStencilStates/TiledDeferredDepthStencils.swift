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
            depthStencilDescriptor.backFaceStencil = frontFaceStencil
        }
    }()
}

struct TiledDeferredGBufferTransparencyDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Tiled Deferred GBuffer Transparency") { depthStencilDescriptor in
            depthStencilDescriptor.depthCompareFunction = .less
            depthStencilDescriptor.isDepthWriteEnabled = false
            
            let frontFaceStencil = MTLStencilDescriptor()
            frontFaceStencil.stencilCompareFunction = .always
            frontFaceStencil.stencilFailureOperation = .keep
            frontFaceStencil.depthFailureOperation = .keep
            frontFaceStencil.depthStencilPassOperation = .incrementClamp
            
            depthStencilDescriptor.frontFaceStencil = frontFaceStencil
            depthStencilDescriptor.backFaceStencil = frontFaceStencil
        }
    }()
}

struct TiledDeferredLightingDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Tiled Deferred Lighting") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
//            depthStencilDescriptor.depthCompareFunction = .equal
            
            let frontFaceStencil = MTLStencilDescriptor()
            // This prevents the ground from rendering unless we invert the normals
            // TODO: figure out why this happens
            frontFaceStencil.stencilCompareFunction = .notEqual
//            frontFaceStencil.stencilCompareFunction = .always
            frontFaceStencil.stencilFailureOperation = .keep
            frontFaceStencil.depthFailureOperation = .keep
            frontFaceStencil.depthStencilPassOperation = .keep
            
            let backFaceStencil = MTLStencilDescriptor()
            backFaceStencil.stencilCompareFunction = .notEqual
//            backFaceStencil.stencilCompareFunction = .always
            backFaceStencil.stencilFailureOperation = .keep
            backFaceStencil.depthFailureOperation = .keep
            backFaceStencil.depthStencilPassOperation = .keep
            
            depthStencilDescriptor.frontFaceStencil = frontFaceStencil
            depthStencilDescriptor.backFaceStencil = backFaceStencil
//            depthStencilDescriptor.backFaceStencil = frontFaceStencil
        }
    }()
}
