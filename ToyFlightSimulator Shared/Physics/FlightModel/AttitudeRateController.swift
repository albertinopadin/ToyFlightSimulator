//
//  AttitudeRateController.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/15/26.
//

/// Pilot rate command → torque, so the body's angular velocity follows the
/// command with the first-order lag AttitudeDynamics describes. With no
/// other torque, one semi-implicit substep reproduces the kinematic filter's
/// update exactly: Δω = (ω_cmd − ω)·(1 − e^(−h/τ)). Gear and contact torques
/// add on top and are damped with the same time constants. Pure.
enum AttitudeRateController {
    /// Body-axis rate command: pitch about X (right), yaw about Y (up), roll
    /// about Z (forward). The negations are the pilot convention the
    /// kinematic path used (rotateX(−pitchRate·dt) and so on). nil input
    /// (no focus) commands zero rates, which is the old decay path.
    static func commandedRates(_ input: ControlInput?, _ dynamics: AttitudeDynamics) -> float3 {
        guard let input else { return .zero }
        return [-input.pitch * dynamics.maxPitchRate,
                -input.yaw * dynamics.maxYawRate,
                -input.roll * dynamics.maxRollRate]
    }
    
    /// Body-frame torque for one substep of length h. τ = I·Δω/h per axis,
    /// with Δω the filter's exact discrete update.
    static func torque(commandedRates: float3,
                       bodyRates: float3,
                       inertia: float3,
                       dynamics: AttitudeDynamics,
                       substepDelta h: Float) -> float3 {
        let alpha = float3(1 - exp(-h / dynamics.pitchTimeConstant),
                           1 - exp(-h / dynamics.yawTimeConstant),
                           1 - exp(-h / dynamics.rollTimeConstant))
        let deltaRates = (commandedRates - bodyRates) * alpha
        return inertia * deltaRates / h
    }
}
