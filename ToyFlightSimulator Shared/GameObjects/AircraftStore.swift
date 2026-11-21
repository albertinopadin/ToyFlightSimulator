//
//  AircraftStore.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/9/23.
//

/// A weapon or fuel tank that an aircraft carries and releases in flight. `Missile` and
/// `Droppable` conform, and through them AIM120, Sidewinder, GBU16 and FuelTank.
/// Its one member is the distance a released store travels before it removes itself from
/// the scene; both classes pass it to their `TravelDistanceLimit`.
protocol AircraftStore {
    /// Distance traveled after release at which the store removes itself, meters.
    ///
    /// The extension below gives every store 100 km. A class that declares the conformance
    /// (`Missile`, `Droppable`) can replace it with its own static. A subclass of those
    /// cannot: a conformance belongs to the class that declares it and subclasses inherit it
    /// unchanged, and `travelLimit` names `Missile.` / `Droppable.` explicitly. A constant
    /// declared in AIM120 would only hide the inherited one (`AIM120.MAX_DISTANCE_BEFORE_REAP`
    /// would read it), and the missile would still be reaped at 100 km.
    static var MAX_DISTANCE_BEFORE_REAP: Double { get }
}

extension AircraftStore {
    /// 100 km. At 60 updates per second a missile (0.5 m per update) covers it in 55.6 min,
    /// a dropped store (0.165 m per update) in 2.8 h. Moves are per update, not per second,
    /// so both times halve at 120 Hz.
    static var MAX_DISTANCE_BEFORE_REAP: Double { 100_000 }  // 100 km
}
