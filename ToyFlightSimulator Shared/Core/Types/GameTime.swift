//
//  GameTime.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

struct GameTime {
    private static var _totalGameTime: Double = 0.0
    private static var _deltaTime: Double = 0.0
    
    public static func UpdateTime(_ deltaTime: Double) {
        self._deltaTime = deltaTime
        self._totalGameTime += deltaTime
    }
}

extension GameTime {
    public static var TotalGameTime: Double {
        return self._totalGameTime
    }
    
    public static var DeltaTime: Double {
        return self._deltaTime
    }
}
