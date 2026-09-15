//
//  FlightModel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/17/26.
//

public protocol FlightModel {
    var mass: Float { get }
    
    /// Principal moments of inertia about the body axes, kg·m²: x (pitch),
    /// y (yaw), z (roll). Authored per aircraft like mass, never derived
    /// from the collider spec: fuel, engines, and stores set the real
    /// distribution, not collision boxes (research §3.1).
    var inertia: float3 { get }

    /// Compute the net world-frame force to apply at the rigid body's center
    /// of mass for this physics step.
    ///
    /// - Parameters:
    ///   - state: Snapshot of the rigid body's kinematics (velocity,
    ///     acceleration) and pose (worldForward, worldRight, rotationMatrix)
    ///     taken at the start of the step. Treated as immutable input.
    ///   - input: Normalized pilot/AI command channels. `throttle` is `0...1`;
    ///     `pitch`, `roll`, `yaw` are `-1...1`. Today only `throttle` is read
    ///     by `F22SimpleFlightModel` (engine thrust); pitch/roll/yaw are the
    ///     rate command of the aircraft's `AttitudeRateController` — see the
    ///     note below.
    /// - Returns: Force vector in world coordinates, in newtons (or kgf if
    ///   the implementation is using those units consistently — `F22SimpleFlightModel`
    ///   currently mixes 31_751 kgf thrust with raw lift/drag terms and a
    ///   `throttlePower` fudge, which is a calibration target, not a unit
    ///   contract).
    ///
    /// - Note: Torque is not returned here. Attitude is a rate controller on
    ///   the aircraft (`AttitudeRateController`) whose torque is added to the
    ///   body inside the step; aerodynamic moments would be the next thing a
    ///   flight model returns.
    func computeForce(state: RigidBody.State, input: ControlInput) -> float3
}
