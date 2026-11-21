//
//  TravelDistanceLimit.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 11/21/26.
//

/// Counts how far an object has moved, in meters, and says when that reaches a limit.
/// `Missile` and `Droppable` remove themselves from the scene with it.
///
/// It holds no position, only the sum of the step lengths, so a floating-origin shift
/// (which moves every stored position) cannot change it. A rule on the stored position,
/// such as the old "any coordinate past 1,000 m", measures the distance from the current
/// origin instead, and a shift changes that.
///
/// The total is a Float. A step no longer than half the gap between neighbouring Float
/// values at the running total adds nothing. From 65,536 m on that gap is 0.0078 m, so a
/// step of 3.9 mm or less (0.23 m/s at 60 Hz) stops counting there and never reaches a
/// 100 km limit. The weapons move 0.16 m or more per tick.
struct TravelDistanceLimit {
    /// Distance at which `reachedLimit` turns true, meters.
    let maxDistance: Float
    /// Sum of the lengths of every step passed to `move(by:)`, meters.
    private(set) var distanceTraveled: Float = 0
    /// True once the distance traveled is at least `maxDistance`.
    var reachedLimit: Bool { distanceTraveled >= maxDistance }

    /// Adds the length of one step (the displacement applied this tick, meters), whatever
    /// its direction.
    mutating func move(by delta: float3) { distanceTraveled += delta.magnitude }
}
