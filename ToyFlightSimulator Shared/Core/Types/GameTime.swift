//
//  GameTime.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

struct GameTime {
    /// Divisor for converting DispatchTime.uptimeNanoseconds deltas into the
    /// Double seconds all engine time is denominated in (DeltaTime,
    /// TotalGameTime, physics/particle dt). Darwin exports the same value as
    /// NSEC_PER_SEC; that spelling is UInt64, so this Double-typed constant
    /// exists to keep the tick-delta divisions cast-free.
    public static let NanosecondsPerSecond: Double = 1e9

    nonisolated(unsafe) private static var _totalGameTime: Double = 0.0
    nonisolated(unsafe) private static var _deltaTime: Double = 0.0
    
    /*
     This method should only be called from the update thread, to prevent data races
     */
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
