//
//  Math.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

public var X_AXIS: float3 {
    return float3(1, 0, 0)
}

public var Y_AXIS: float3 {
    return float3(0, 1, 0)
}

public var Z_AXIS: float3 {
    return float3(0, 0, 1)
}

extension Float {
    var toRadians: Float {
        return (self / 180.0) * Float.pi
    }
    
    var toDegrees: Float {
        return self * (180.0 / Float.pi)
    }
    
    static var randomZeroToOne: Float {
        return Float(arc4random()) / Float(UINT32_MAX)
    }
}

