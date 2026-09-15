//
//  AttitudeRateControllerTests.swift
//  ToyFlightSimulatorTests
//
//  D.3 (D-attitude): the pilot's rate command as a torque. The controller is
//  the kinematic attitude filter moved inside the physics step: with no other
//  torque, one semi-implicit substep reproduces the filter's exact
//  exponential update, so the in-air response is the one the kinematic path
//  produced. Metal-free: pure functions, then a detached body stepped through
//  real PhysicsWorlds on both solvers. Every expected value was reproduced in
//  a scratch replay before the tests ran.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Attitude rate controller", .tags(.physics))
struct AttitudeRateControllerTests {
    @Test("commandedRates maps pitch, yaw, and roll to body-axis rates with the pilot negations; nil input commands zero")
    func commandedRatesMapping() {
        let dynamics = AttitudeDynamics()
        let input = ControlInput(throttle: 0, pitch: 0.5, roll: -1, yaw: 0.25)
        let rates = AttitudeRateController.commandedRates(input, dynamics)
        // Pitch about X, yaw about Y, roll about Z, each negated as the
        // kinematic path's rotateX(−pitchRate·dt) and so on did.
        #expect(rates == [-0.5 * dynamics.maxPitchRate, -0.25 * dynamics.maxYawRate, 1 * dynamics.maxRollRate])
        #expect(AttitudeRateController.commandedRates(nil, dynamics) == .zero, "no focus: the old decay path")
    }

    @Test("torque is I·(ω_cmd − ω)·(1 − e^(−h/τ))/h per axis")
    func torqueIsTheFilterUpdateTimesInertia() {
        let dynamics = AttitudeDynamics()
        let torque = AttitudeRateController.torque(commandedRates: [1, 2, 3],
                                                   bodyRates: [0.5, 0.5, 0.5],
                                                   inertia: [10, 20, 30],
                                                   dynamics: dynamics,
                                                   substepDelta: 0.01)
        // Per axis: 10 · 0.5 · (1 − e^(−0.04)) / 0.01, 20 · 1.5 · (1 − e^(−0.025)) / 0.01,
        // 30 · 2.5 · (1 − e^(−0.0667)) / 0.01.
        let alpha = float3(1 - exp(-0.01 / dynamics.pitchTimeConstant),
                           1 - exp(-0.01 / dynamics.yawTimeConstant),
                           1 - exp(-0.01 / dynamics.rollTimeConstant))
        #expect(approxEqual(torque, float3(10, 20, 30) * (float3(1, 2, 3) - 0.5) * alpha / 0.01, tolerance: 1e-3))
        #expect(approxEqual(torque, [19.605, 74.070, 483.70], tolerance: 0.01))
        // No rate error, no torque; a body already at the command coasts.
        #expect(AttitudeRateController.torque(commandedRates: [1, 2, 3], bodyRates: [1, 2, 3], inertia: [10, 20, 30],
                                              dynamics: dynamics, substepDelta: 0.01) == .zero)
    }

    @Test("integration: a constant roll command of 1 rad/s with τ = 0.15 s follows the exact exponential, so one axis feels as the kinematic filter did",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func rollCommandFollowsTheExponential(_ updateType: PhysicsUpdateType) {
        // The F-22's tensor, gravity off, a hook adding the controller torque
        // as Aircraft.generateForces does (body axes in, world torque out).
        // With no other torque the substep is ω += (ω_cmd − ω)(1 − e^(−h/τ))
        // exactly, whatever the inertia: ω(t) = 1 − e^(−t/τ).
        let inertia = F22SimpleFlightModel().inertia
        let dynamics = AttitudeDynamics()
        let body = RigidBody(detachedAt: .zero)
        body.shouldApplyGravity = false
        body.inverseInertiaLocal = float3x3(diagonal: 1 / inertia)
        body.forceGenerator = { body, substepDelta, _ in
            let rotation = body.pose().rotation
            let torqueBody = AttitudeRateController.torque(commandedRates: [0, 0, 1],
                                                           bodyRates: rotation.transpose * body.angularVelocity,
                                                           inertia: inertia,
                                                           dynamics: dynamics,
                                                           substepDelta: substepDelta)
            body.torque += rotation * torqueBody
        }
        let world = PhysicsWorld(entities: [body], updateType: updateType)

        for _ in 0..<18 { world.update(deltaTime: PhysicsWorld.fixedDelta) }   // t = τ
        #expect(abs(body.angularVelocity.z - 0.632) <= 0.01, "1 − e⁻¹ at t = τ (replay: 0.63212)")

        for _ in 18..<120 { world.update(deltaTime: PhysicsWorld.fixedDelta) }   // t = 1 s
        #expect(abs(body.angularVelocity.z - 0.999) <= 1e-3, "1 − e^(−1/0.15) = 0.99873")
        // The accumulated roll: the continuous ∫ω = t − τ(1 − e^(−t/τ)) =
        // 0.850 rad; the discrete sum of the new ω each substep (orientation
        // after the velocity half) is 0.854. Column 0 is the body's right
        // axis, rotated about +Z through this angle.
        let right = body.pose().rotation.right
        #expect(abs(atan2(right.y, right.x) - 0.850) <= 0.01)
        #expect(body.angularVelocity.x == 0 && body.angularVelocity.y == 0, "one axis commanded, one axis moves")
        #expect(body.getPosition() == .zero && body.velocity == .zero, "a torque alone moves nothing")
    }
}
