//
//  BasicDepthStencils.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

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

struct LessNoWrite_DepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "DepthCompareLessAndNoWrite") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilDescriptor.depthCompareFunction = .less
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

struct DepthWriteDisabledDepthStencilState: DepthStencilState {
    var depthStencilState: MTLDepthStencilState = {
        makeDepthStencilState(label: "Depth Write Disabled") { depthStencilDescriptor in
            depthStencilDescriptor.isDepthWriteEnabled = false
        }
    }()
}
