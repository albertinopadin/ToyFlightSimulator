//
//  F35.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/21/23.
//

class F35: Aircraft {
    static let NAME: String = "F-35"
    
    init(scale: Float = 1.0, shouldUpdate: Bool = true) {
        super.init(name: Self.NAME,
                   meshType: .CGTrader_F35,
                   renderPipelineStateType: .OpaqueMaterial,
                   scale: scale,
                   shouldUpdate: shouldUpdate)
    }
}
