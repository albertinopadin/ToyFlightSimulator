//
//  AircraftLandingGearSpec.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/4/26.
//

/// Landing-gear strut specs per aircraft (the AircraftColliderSpec pattern).
/// Geometry in post-import body-local meters; rates in absolute SI.
enum AircraftLandingGearSpec {
    /// Exhaustive over AircraftType with no `default`: adding an aircraft
    /// forces an authored-or-empty decision. [] means no suspension; the
    /// aircraft rests on its collision geometry as in Phase A.
    static func spec(for type: AircraftType) -> [SuspensionStrut] {
        switch type {
            case .f22_cgtrader:
                return f22CGTrader
            case .f16, .f18, .f22, .f35:
                return []
        }
    }

    /// PLACEHOLDERS until checked against the modeled gear with the X-key
    /// overlay's strut lines (B.5); tune, then update this comment.
    /// Geometry: wheel track 3.24 m (public F-22 data about 3.25), wheelbase
    /// 6.1 m (about 6.0). All three struts share one reachBelowOrigin, 2.05 m,
    /// so a level aircraft touches all wheels together. Rate sizing is derived
    /// in the plan (Phase B, step B.4); the resulting ride height, 1.93 m at
    /// 30 t, is asserted by AircraftLandingGearSpecTests.
    private static let f22CGTrader: [SuspensionStrut] = [
        SuspensionStrut(name: "noseGear",
                        attachLocal: [0, -0.55, 5.2],
                        restLength: 1.20,
                        maxTravel: 0.40,
                        wheelRadius: 0.30,
                        springRate: 268_000,
                        compressionDamping: 34_000,
                        reboundDamping: 51_000,
                        maxSupportForce: 100_000),
        SuspensionStrut(name: "mainGearLeft",
                        attachLocal: [-1.62, -0.55, -0.9],
                        restLength: 1.05,
                        maxTravel: 0.45,
                        wheelRadius: 0.45,
                        springRate: 1_100_000,
                        compressionDamping: 146_000,
                        reboundDamping: 219_000,
                        maxSupportForce: 400_000),
        SuspensionStrut(name: "mainGearRight",
                        attachLocal: [1.62, -0.55, -0.9],
                        restLength: 1.05,
                        maxTravel: 0.45,
                        wheelRadius: 0.45,
                        springRate: 1_100_000,
                        compressionDamping: 146_000,
                        reboundDamping: 219_000,
                        maxSupportForce: 400_000)
    ]

    /// Static stance for a level aircraft with equal-reach struts: every strut
    /// shares one compression x = m·g / Σk, and ride height = reach − x. nil
    /// for an empty spec. `gravity` is the scalar magnitude; the default is
    /// the world's (PhysicsWorld.gravity is the same value along −Y).
    static func staticStance(struts: [SuspensionStrut],
                             mass: Float,
                             gravity: Float = PhysicsWorld.standardGravity) -> (compression: Float, rideHeight: Float)? {
        guard let first = struts.first else { return nil }
        let totalRate = struts.reduce(0) { $0 + $1.springRate }
        guard totalRate > 0 else { return nil }
        let x = mass * gravity / totalRate
        return (x, first.reachBelowOrigin - x)
    }
}
