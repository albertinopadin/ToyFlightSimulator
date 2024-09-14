//
//  F16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/29/22.
//

import MetalKit

class F16: Aircraft {
    init(scale: Float = 1.0, shouldUpdate: Bool = true) {
        super.init(name: "F-16", modelType: .F16, scale: scale, shouldUpdate: shouldUpdate)
    }
    
    // TODO: Whats with the setFrontFacing call?
//    override func doRender(_ renderEncoder: MTLRenderCommandEncoder,
//                           applyMaterials: Bool = true,
//                           submeshesToRender: [String : Bool]? = nil) {
//        renderEncoder.setFrontFacing(.counterClockwise)
//        super.doRender(renderEncoder, applyMaterials: applyMaterials, submeshesToRender: submeshesToRender)
//        renderEncoder.setFrontFacing(.clockwise)
//    }
}
