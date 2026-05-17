//
//  FlightModel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/17/26.
//

public protocol FlightModel {
    var mass: Float { get }

    /// Compute the net world-frame force to apply at the rigid body's center
    /// of mass for this physics step.
    ///
    /// - Parameters:
    ///   - state: Snapshot of the rigid body's kinematics (velocity,
    ///     acceleration) and pose (worldForward, worldRight, rotationMatrix)
    ///     taken at the start of the step. Treated as immutable input.
    ///   - input: Normalized pilot/AI command channels. `throttle` is `0...1`;
    ///     `pitch`, `roll`, `yaw` are `-1...1`. Today only `throttle` is read
    ///     by `F22SimpleFlightModel` (engine thrust); pitch/roll/yaw flow
    ///     through `Aircraft.applyPlayerAttitudeInput` as kinematic rotation
    ///     until a torque path is added — see below.
    /// - Returns: Force vector in world coordinates, in newtons (or kgf if
    ///   the implementation is using those units consistently — `F22SimpleFlightModel`
    ///   currently mixes 31_751 kgf thrust with raw lift/drag terms and a
    ///   `throttlePower` fudge, which is a calibration target, not a unit
    ///   contract).
    ///
    /// - Note: This contract only covers translational force. Torque is not
    ///   returned — attitude is still applied kinematically by
    ///   `Aircraft.applyPlayerAttitudeInput` via direct `rotateX/Y/Z` calls
    ///   on the node, which means there is no rotational inertia and the
    ///   aircraft snaps to commanded angular rate instantly. Two follow-ups
    ///   are on the table:
    ///   1. Damped first-order response on the kinematic rotation rate
    ///      (cheap, gives most of the feel — see `plans/claude/`).
    ///   2. Promote this method to return `(force, torque)` and have
    ///      `RigidBody` integrate angular velocity for real (the proper fix,
    ///      requires moment-of-inertia data and an angular integrator).
    func computeForce(state: RigidBody.State, input: ControlInput) -> float3
}
