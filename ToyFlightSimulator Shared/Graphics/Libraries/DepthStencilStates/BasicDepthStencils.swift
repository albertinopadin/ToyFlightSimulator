//
//  BasicDepthStencils.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

// The main camera uses **reverse-Z** projection (see `Transform.perspectiveProjection`):
// NDC depth `1.0` is at the near plane and `0.0` is at the far plane. "Closer fragment
// wins" therefore uses `.greater` / `.greaterEqual`, not `.less` / `.lessEqual`.

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

/// Uses `.greater` for reverse-Z ("closer" = higher NDC z).
struct CloserWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareCloserAndWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .greater
        }
    }()
}

/// Uses `.greaterEqual` for reverse-Z ("closer or equal" = higher-or-equal NDC z).
struct CloserOrEqualWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareCloserEqualAndWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .greaterEqual
        }
    }()
}

/// Uses `.greater` for reverse-Z ("closer" = higher NDC z).
struct CloserNoWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareCloserAndNoWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilDescriptor.depthCompareFunction = .greater
        }
    }()
}

/// Uses `.greaterEqual` for reverse-Z ("closer or equal" = higher-or-equal NDC z).
struct CloserOrEqualNoWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareCloserEqualAndNoWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilDescriptor.depthCompareFunction = .greaterEqual
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
