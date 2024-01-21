//
//  F22.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/20/24.
//

class F22: Aircraft {
    private let _cameraPositionOffset = float3(0, 10, 40)
    var shouldUpdate: Bool = true
    static let NAME: String = "F-22"
    
    init() {
        super.init(name: Self.NAME, meshType: .Sketchfab_F22, renderPipelineStateType: .OpaqueMaterial)
        self.shouldUpdate = false  // Don't update when user moves camera
    }
    
    init(camera: AttachedCamera, scale: Float = 1.0) {
        super.init(name: Self.NAME,
                   meshType: .Sketchfab_F22,
                   renderPipelineStateType: .OpaqueMaterial,
                   camera: camera,
                   cameraOffset: _cameraPositionOffset,
                   scale: scale)
    }
    
    override func doUpdate() {
        if shouldUpdate {
            super.doUpdate()
        }
    }
}
