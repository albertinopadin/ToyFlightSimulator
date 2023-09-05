//
//  F35.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/21/23.
//

class F35: Aircraft {
    private let _cameraPositionOffset = float3(0, 10, 40)
    var shouldUpdate: Bool = true
    static let NAME: String = "F-35"
    
    init() {
        super.init(name: Self.NAME, meshType: .CGTrader_F35_GLB, renderPipelineStateType: .OpaqueMaterial)
        self.shouldUpdate = false  // Don't update when user moves camera
    }
    
    init(camera: AttachedCamera, scale: Float = 1.0) {
        super.init(name: Self.NAME,
                   meshType: .CGTrader_F35_GLB,
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
