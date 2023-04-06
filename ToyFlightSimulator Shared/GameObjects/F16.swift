//
//  F16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/29/22.
//

import MetalKit

class F16: Aircraft {
    private let _cameraPositionOffset = float3(0, 2, 4)
    
    init() {
        super.init(name: "F-16", meshType: .F16, renderPipelineStateType: .OpaqueMaterial)
        self.shouldUpdate = false  // Don't update when user moves camera
    }
    
    init(camera: AttachedCamera) {
        super.init(name: "F-16",
                   meshType: .F16,
                   renderPipelineStateType: .OpaqueMaterial,
                   camera: camera,
                   cameraOffset: _cameraPositionOffset)
    }
}
