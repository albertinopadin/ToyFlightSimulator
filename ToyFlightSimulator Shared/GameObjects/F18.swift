//
//  F18.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/11/23.
//

import MetalKit

class F18: Aircraft {
    private let _cameraPositionOffset = float3(0, 10, 20)
    
    init() {
        super.init(name: "F-18", meshType: .F18, renderPipelineStateType: .OpaqueMaterial)
        self.shouldUpdate = false  // Don't update when user moves camera
    }
    
    init(camera: AttachedCamera, scale: Float = 0.5) {
        super.init(name: "F-18",
                   meshType: .F18,
                   renderPipelineStateType: .OpaqueMaterial,
                   camera: camera,
                   cameraOffset: _cameraPositionOffset,
                   scale: scale)
    }
}
