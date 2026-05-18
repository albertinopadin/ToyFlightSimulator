//
//  SinglePassDeferredDepthStencils.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

// -------------- FOR DEFERRED LIGHTING ---------------- //
// NOTE: Shadow generation runs in the LIGHT's projection (orthographic, see
// `LightObject.projectionMatrix`), which is *not* reverse-Z — only the main
// camera's `Transform.perspectiveProjection` is. So shadow depth compares stay
// `.less` / `.lessEqual` while main-camera compares are flipped to `.greater(Equal)`.

struct ShadowGenerationDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Shadow Generation Stage") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .lessEqual  // light-space, NOT reverse-Z
        }
    }()
}

struct GBufferGenerationDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "GBuffer Generation Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
            stencilStateDescriptor.depthStencilPassOperation = .replace

            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .greater  // reverse-Z: closer = larger
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

            depthStencilDescriptor.depthCompareFunction = .greaterEqual  // reverse-Z
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }()
}

struct PointLightDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Point Lights Stage") { depthStencilDescriptor in
            let stencilStateDescriptor = MTLStencilDescriptor()
            stencilStateDescriptor.stencilCompareFunction = .lessEqual  // stencil ref vs mask, not depth
            stencilStateDescriptor.readMask = 0xFF
            stencilStateDescriptor.writeMask = 0x0

            depthStencilDescriptor.depthCompareFunction = .greaterEqual  // reverse-Z
            depthStencilDescriptor.frontFaceStencil = stencilStateDescriptor
            depthStencilDescriptor.backFaceStencil = stencilStateDescriptor
        }
    }()
}

struct SkyboxDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Skybox Stage") { depthStencilDescriptor in
            // Skybox is drawn last; we want it to fail where any closer geometry has
            // already written depth, and pass where nothing has been drawn yet (depth
            // == cleared 0.0 in reverse-Z). The skybox sphere's own depth is small
            // (close to 0) since the sphere is far in view space.
            depthStencilDescriptor.depthCompareFunction = .greater  // reverse-Z
        }
    }()
}
