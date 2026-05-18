//
//  BasicDepthStencils.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

// NOTE: The main camera uses **reverse-Z** projection (see
// `Transform.perspectiveProjection`): NDC depth `1.0` is at the near plane and
// `0.0` is at the far plane. "Closer fragment wins" therefore needs
// `.greater` / `.greaterEqual` here, not `.less` / `.lessEqual`. The struct/enum
// names ("Less"...) preserve the geometric *meaning* — "fragments closer to the
// camera pass" — even though the underlying compare function is reversed.

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
        makeDepthStencilState(label: "DepthCompareCloserAndWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .greater  // reverse-Z
        }
    }()
}

struct LessEqualWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareCloserEqualAndWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = true
            depthStencilDescriptor.depthCompareFunction = .greaterEqual  // reverse-Z
        }
    }()
}

struct LessNoWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareCloserAndNoWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilDescriptor.depthCompareFunction = .greater  // reverse-Z
        }
    }()
}

struct LessEqualNoWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareCloserEqualAndNoWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilDescriptor.depthCompareFunction = .greaterEqual  // reverse-Z
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
