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
/// The total is a Double. Each step's length is still computed in Float, from the Float
/// step the object applied to its position, and converting it to Double is exact. A sum
/// loses a step only when the step is no longer than half the gap between neighbouring
/// values at the total; for a Double at 100 km that gap is 1.5e-11 m, so every step counts.
/// A Float total, which this used to be, has a 7.8 mm gap from 65,536 m on, so it stopped
/// counting steps of 3.9 mm or less there and never reached a 100 km limit.
struct TravelDistanceLimit {
    /// Distance at which `reachedLimit` turns true, meters.
    let maxDistance: Double
    /// Sum of the lengths of every step passed to `move(by:)`, meters.
    private(set) var distanceTraveled: Double = 0
    /// True once the distance traveled is at least `maxDistance`.
    var reachedLimit: Bool { distanceTraveled >= maxDistance }

    /// Adds the length of one step (the displacement applied this tick, meters), whatever
    /// its direction.
    mutating func move(by delta: float3) { distanceTraveled += delta.magnitude.toDouble() }
}
