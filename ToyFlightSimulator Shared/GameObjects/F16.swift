//
//  F16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/29/22.
//

import MetalKit

class F16: Aircraft {
    init(scale: Float = 1.0, shouldUpdate: Bool = true) {
        super.init(name: "F-16",
                   meshType: .F16,
                   renderPipelineStateType: .OpaqueMaterial,
                   scale: scale,
                   shouldUpdate: shouldUpdate)
    }
    
    override func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder, 
                           applyMaterials: Bool = true,
                           submeshesToRender: [String : Bool]? = nil) {
        renderCommandEncoder.setFrontFacing(.counterClockwise)
        super.doRender(renderCommandEncoder, applyMaterials: applyMaterials, submeshesToRender: submeshesToRender)
        renderCommandEncoder.setFrontFacing(.clockwise)
    }
}
