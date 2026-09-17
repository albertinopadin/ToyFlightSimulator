//
//  AircraftTelemetry.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/17/26.
//

import Foundation
import simd

/// One frame of pilot-facing flight data for the HUD / game UI.
///
/// A plain value: built on the UpdateThread from the player aircraft's live
/// state (`Aircraft.getTelemetrySnapshot`), then handed to the main actor
/// (`AircraftTelemetryStore`) by copy. Neither the store nor the views hold
/// an engine object, so any vehicle that can fill this struct can drive the
/// same panel. Stored values are SI (meters, m/s) and degrees; the display
/// units are the computed properties below.
struct AircraftTelemetry: Sendable, Equatable {
    static let metersPerSecondToMphConversionFactor: Float = 2.23694
    static let metersPerSecondToKnotsConversionFactor: Float = 1.94384
    static let metersToFeetConversionFactor: Float = 3.28084
    
    let aircraftType: AircraftType?
    /// Compass heading in degrees, 0 ≤ heading < 360: 0 is world +Z, 90 is
    /// world +X (a right turn increases it).
    let heading: Float
    let altitudeInMeters: Float
    /// Velocity projected on the nose axis, dot(v, forward); negative when
    /// sliding backwards. length(v) would be the airspeed a HUD shows.
    let forwardSpeedInMetersPerSecond: Float
    /// Degrees, nose above the horizon positive, −90…+90.
    let pitchAngle: Float
    /// Bank in degrees, right wing down positive, −180…+180.
    let rollAngle: Float
    
    // TODO:
//    let angleOfAttack: Float
    
    var altitudeInFeet: Float { altitudeInMeters * Self.metersToFeetConversionFactor }
    var speedInMph: Float { forwardSpeedInMetersPerSecond * Self.metersPerSecondToMphConversionFactor }
    var speedInKnots: Float { forwardSpeedInMetersPerSecond * Self.metersPerSecondToKnotsConversionFactor }
    
}

// MARK: - Pure snapshot math (Metal-free; AircraftTelemetryTests)

extension AircraftTelemetry {
    /// Aviation Euler angles read back from the body axes in world space.
    /// `roll` and `heading` are nil while the nose is vertical: the nose's
    /// horizontal projection is then a point and neither angle is defined.
    struct AttitudeAngles: Equatable {
        let pitch: Float
        let roll: Float?
        let heading: Float?
    }
    
    /// Below this horizontal nose length (= cos(pitch)) heading and bank are
    /// treated as undefined; 1e-6 is 0.00006° from vertical. Nearer than
    /// about 0.001° the values are still exact in Float but swing fast.
    static let verticalNoseThreshold: Float = 1e-6
    
    /// Pitch, bank, and heading in degrees from the aircraft's world-space
    /// basis vectors (`Node.getFwdVector/getRightVector/getUpVector`: the
    /// rotation matrix's columns, unit length).
    ///
    /// Writing the attitude as heading ψ about world up, then pitch θ about
    /// the new right axis, then bank φ about the new nose axis, the columns
    /// come out as
    ///     forward = (cos θ · sin ψ,  sin θ,  cos θ · cos ψ)
    ///     right.y = −sin φ · cos θ,   up.y = cos φ · cos θ
    /// so the nose's height above the horizon is pitch, its horizontal
    /// direction is heading, and the right wing's dip against the up
    /// vector's height is bank (cos θ cancels inside atan2). Pitch uses
    /// atan2(sin θ, cos θ) rather than asin(sin θ): in Float, asin saturates
    /// about 0.02° short of vertical, atan2 is exact there. These are the
    /// standard aircraft Euler angles (Stevens & Lewis, Aircraft Control and
    /// Simulation, ch. 1) mapped onto this engine's Y-up, Z-forward frame.
    static func attitudeAngles(forward: float3, right: float3, up: float3) -> AttitudeAngles {
        let horizontalForwardLength = (forward.x * forward.x + forward.z * forward.z).squareRoot()  // cos θ ≥ 0
        let pitch = atan2(forward.y, horizontalForwardLength).toDegrees
        
        guard horizontalForwardLength > verticalNoseThreshold else {
            return AttitudeAngles(pitch: pitch, roll: nil, heading: nil)
        }
        
        let roll = atan2(-right.y, up.y).toDegrees
        var heading = atan2(forward.x, forward.z).toDegrees   // −180…180
        if heading < 0 { heading += 360 }
        // A heading a hair below 0 rounds to exactly 360 in Float after the
        // wrap; keep the compass in [0, 360).
        if heading >= 360 { heading -= 360 }
        return AttitudeAngles(pitch: pitch, roll: roll, heading: heading)
    }
    
    /// Builds a snapshot from raw world-space state. Pure, so the whole
    /// frame-to-display path is testable without an `Aircraft` (which needs
    /// Metal). `previous` supplies heading and bank while the nose is
    /// vertical, so the readout holds its last defined values instead of
    /// jumping to an arbitrary number.
    static func make(aircraftType: AircraftType?,
                     forward: float3,
                     right: float3,
                     up: float3,
                     velocity: float3,
                     worldPosition: float3,
                     previous: AircraftTelemetry) -> AircraftTelemetry {
        let angles = attitudeAngles(forward: forward, right: right, up: up)
        return AircraftTelemetry(aircraftType: aircraftType,
                                 heading: angles.heading ?? previous.heading,
                                 altitudeInMeters: worldPosition.y,
                                 forwardSpeedInMetersPerSecond: dot(velocity, forward),
                                 pitchAngle: angles.pitch,
                                 rollAngle: angles.roll ?? previous.rollAngle)
    }
}
