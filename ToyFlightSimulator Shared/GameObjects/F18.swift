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
    }
    
    init(camera: AttachedCamera) {
        super.init(name: "F-18",
                   meshType: .F18,
                   renderPipelineStateType: .OpaqueMaterial,
                   camera: camera,
                   cameraOffset: _cameraPositionOffset)
    }
}
