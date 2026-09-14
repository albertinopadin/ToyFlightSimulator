//
//  TireModelTests.swift
//  ToyFlightSimulatorTests
//
//  D.2 (D-tires): the pure tire solve — holding Coulomb friction over the
//  loaded wheels as sequential impulses against one predicted velocity —
//  straight through TireModel.solve, no bodies and no world. Unless a case
//  says otherwise: one wheel with a 1000 N load on level ground, a body of
//  mass 100 with infinite inertia (inverseMass 0.01, the zero tensor), one
//  1/120 s substep, and the predicted velocity given as the body's. Every
//  expected value was reproduced in a scratch script with the shipped
//  source before the tests ran; the `==` comparisons are exact in Float.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("TireModel", .tags(.physics))
struct TireModelTests {
    /// One substep, so an impulse of J N·s reads as a force of 120·J N.
    private static let h = PhysicsWorld.fixedDelta

    /// Level ground: the wheel rolls along +Z and its side direction,
    /// cross(normal, forward), is +X.
    private static let groundNormal: float3 = [0, 1, 0]
    private static let forward: float3 = [0, 0, 1]
    private static let side: float3 = [1, 0, 0]

    /// Mass 100 with infinite inertia: every patch moves with the origin and
    /// the effective mass along any direction is the mass itself.
    private static let body = TireModel.Body(origin: .zero,
                                             inverseMass: 0.01,
                                             inverseInertiaWorld: RigidBody.infiniteInertia)

    private static func wheel(load: Float = 1000,
                              brake: Float = 0,
                              rollingDirection: float3 = forward,
                              patch: float3 = [0, -1, 0]) -> TireModel.Wheel {
        TireModel.Wheel(patch: patch,
                        groundNormal: groundNormal,
                        rollingDirection: rollingDirection,
                        normalLoad: load,
                        brake: brake)
    }

    /// One solve; returns the forces and the velocities as the solve leaves
    /// them (its bookkeeping: the body's predicted velocities with the
    /// wheels' impulses applied).
    private static func solve(wheels: [TireModel.Wheel],
                              body: TireModel.Body = body,
                              velocity: float3,
                              angularVelocity: float3 = .zero)
        -> (forces: [float3], velocity: float3, angularVelocity: float3) {
        var velocity = velocity
        var angularVelocity = angularVelocity
        var forces = [float3](repeating: .zero, count: wheels.count)
        TireModel.solve(wheels: wheels,
                        body: body,
                        velocity: &velocity,
                        angularVelocity: &angularVelocity,
                        substepDelta: h,
                        forces: &forces)
        return (forces, velocity, angularVelocity)
    }

    // MARK: - Unloaded and degenerate wheels

    @Test("an unloaded wheel produces no force and leaves the velocities untouched")
    func unloadedWheelIsSkipped() {
        let result = Self.solve(wheels: [Self.wheel(load: 0)], velocity: [1, 0, 2], angularVelocity: [0, 3, 0])
        #expect(result.forces == [.zero])
        #expect(result.velocity == [1, 0, 2])
        #expect(result.angularVelocity == [0, 3, 0])
    }

    @Test("a rolling direction along the ground normal has no ground frame: no force")
    func rollingAxisAlongNormalIsSkipped() {
        let result = Self.solve(wheels: [Self.wheel(rollingDirection: Self.groundNormal)], velocity: [3, 0, 7])
        #expect(result.forces == [.zero])
        #expect(result.velocity == [3, 0, 7])
    }

    // MARK: - Lateral grip: saturated and holding

    @Test("a 2 m/s crab saturates the lateral limit: −800·side (0.8 × 1000 N)")
    func lateralSaturates() {
        // The demand is m·v/h = 100 · 2 · 120 = 24 kN; the tire carries 800 N.
        let result = Self.solve(wheels: [Self.wheel()], velocity: Self.side * 2)
        #expect(approxEqual(result.forces[0], Self.side * -800))
    }

    @Test("a 1 mm/s crab is held exactly: −12·side (100 · 0.001 · 120) and the returned velocity is zero")
    func lateralHolds() {
        // The holding region: the impulse that stops the patch, m·v = 0.1 N·s,
        // is under the 800/120 N·s limit, so it is applied whole and no more.
        let result = Self.solve(wheels: [Self.wheel()], velocity: Self.side * 0.001)
        #expect(result.forces[0] == Self.side * -12)
        #expect(result.velocity == .zero)
    }

    @Test("two wheels, one demand: the first takes all of it (−12·side), the second nothing — a sequence, not a share")
    func sequentialWheelsShareNothing() {
        let wheels = [Self.wheel(), Self.wheel(patch: [1, -1, 0])]
        let result = Self.solve(wheels: wheels, velocity: Self.side * 0.001)
        #expect(result.forces[0] == Self.side * -12)
        #expect(result.forces[1] == .zero, "the first wheel's impulse already stopped the patch it shares")
        #expect(result.velocity == .zero)
    }

    // MARK: - Rolling resistance and brakes

    @Test("rolling at 20 m/s with no brake: rolling resistance only, −20·forward (0.02 × 1000 N)")
    func rollingResistance() {
        let result = Self.solve(wheels: [Self.wheel()], velocity: Self.forward * 20)
        #expect(result.forces[0] == Self.forward * -20)
    }

    @Test("rolling at 20 m/s with the brake on: −520·forward ((0.02 + 0.5) × 1000 N)")
    func brakeRaisesTheLongitudinalLimit() {
        let result = Self.solve(wheels: [Self.wheel(brake: 1)], velocity: Self.forward * 20)
        #expect(result.forces[0] == Self.forward * -520)
    }

    @Test("a 1 mm/s forward drift with no brake is held exactly: −12·forward, under the 20 N rolling limit")
    func smallForwardDriftIsHeld() {
        let result = Self.solve(wheels: [Self.wheel()], velocity: Self.forward * 0.001)
        #expect(result.forces[0] == Self.forward * -12)
        #expect(result.velocity == .zero)
    }

    @Test("a 5 mm/s forward drift asks for 60 N, over the 20 N rolling limit: the wheel creeps at −20·forward")
    func forwardDriftOverTheRollingLimitCreeps() {
        let result = Self.solve(wheels: [Self.wheel()], velocity: Self.forward * 0.005)
        #expect(result.forces[0] == Self.forward * -20)
        #expect(result.velocity.z > 0, "the limit binds: some of the drift is left")
    }

    // MARK: - The friction circle and the ground plane

    @Test("saturated lateral plus saturated brake: magnitude 800 (the circle), not the 954 of the two limits in quadrature")
    func frictionCircleClampsBothTogether() {
        // 20 m/s forward and 20 m/s sideways with the brake on: the along
        // part clamps to 520 and the across part to 800 separately; the
        // circle scales the pair back to 800 = 0.8 × N.
        let result = Self.solve(wheels: [Self.wheel(brake: 1)], velocity: Self.forward * 20 + Self.side * 20)
        #expect(approxEqual(simd_length(result.forces[0]), 800, tolerance: 1e-2))
        #expect(simd_length(result.forces[0]) < (520 * 520 + 800 * 800).squareRoot())
    }

    @Test("the tire force lies in the ground plane: no component along the normal")
    func forceHasNoNormalComponent() {
        let result = Self.solve(wheels: [Self.wheel()], velocity: [3, 5, 7])
        #expect(dot(result.forces[0], Self.groundNormal) == 0)
        #expect(simd_length(result.forces[0]) > 0)
    }

    // MARK: - The limit hands the demand on (the D.2 rig)

    /// The F-22 at 30 t as a body that cannot pitch: loads 32, 131, and
    /// 131 kN in strut order (nose first), brakes on the mains only.
    private static let f22Body = TireModel.Body(origin: .zero,
                                                inverseMass: 1.0 / 30_000,
                                                inverseInertiaWorld: RigidBody.infiniteInertia)
    private static func f22Wheels(brake: Float) -> [TireModel.Wheel] {
        [wheel(load: 32_000, brake: 0, patch: [0, -2, 5.2]),
         wheel(load: 131_000, brake: brake, patch: [-1.62, -2, -0.9]),
         wheel(load: 131_000, brake: brake, patch: [1.62, -2, -0.9])]
    }
    /// The predicted velocity 100 kN of thrust would leave after one substep.
    private static let thrustVelocity: float3 = forward * (100_000 / 30_000 / 120)

    @Test("brakes on: three wheels oppose all 100 kN — nose 640, mains 68 120 and 31 240 in order — and the jet does not move")
    func limitHandsTheDemandOn() {
        let result = Self.solve(wheels: Self.f22Wheels(brake: 1), body: Self.f22Body, velocity: Self.thrustVelocity)
        let total = result.forces.reduce(float3.zero, +)
        #expect(approxEqual(total, Self.forward * -100_000, tolerance: 1),
                "each wheel takes what the ones before it left")
        #expect(approxEqual(result.forces[0], Self.forward * -640, tolerance: 1), "the nose at its rolling-resistance limit")
        #expect(approxEqual(result.forces[1], Self.forward * -68_120, tolerance: 1), "the first main at its brake limit")
        #expect(approxEqual(result.forces[2], Self.forward * -31_240, tolerance: 1), "the second main takes the rest, unsaturated")
        #expect(simd_length(result.velocity) <= 1e-6)
    }

    @Test("brakes off: the same wheels carry only rolling resistance, 5 880 N (0.02 × 294 kN), and the jet creeps")
    func withoutBrakesTheRollingLimitBinds() {
        let result = Self.solve(wheels: Self.f22Wheels(brake: 0), body: Self.f22Body, velocity: Self.thrustVelocity)
        let total = result.forces.reduce(float3.zero, +)
        #expect(approxEqual(total, Self.forward * -5_880, tolerance: 1))
        #expect(simd_length(result.velocity) > 1e-3, "every wheel is at its limit; the rest of the drift stays")
    }

    // MARK: - Finite inertia

    @Test("finite inertia: the effective mass at the patch is 0.4, the force −48·forward, and the patch comes to rest while the origin keeps 0.8 m/s")
    func finiteInertiaCouplesThePatchThroughRotation() {
        // Mass 2, I⁻¹ = diag(0.5), one wheel 2 m below the origin with the
        // brake on, predicted [0, 0, 1] along its forward. r × d = [−2, 0, 0],
        // so 1 / (1/m + (r × d)·I⁻¹(r × d)) = 1 / (0.5 + 2) = 0.4: an impulse
        // of 0.4 N·s (48 N over the substep), which leaves the origin at
        // 0.8 m/s and spins the body at 0.4 rad/s about X — together, zero
        // at the patch. Under the 0.52 × 1000 / 120 N·s brake limit.
        let body = TireModel.Body(origin: .zero,
                                  inverseMass: 0.5,
                                  inverseInertiaWorld: float3x3(diagonal: [0.5, 0.5, 0.5]))
        let patch: float3 = [0, -2, 0]
        let result = Self.solve(wheels: [Self.wheel(brake: 1, patch: patch)], body: body, velocity: [0, 0, 1])
        #expect(result.forces[0] == Self.forward * -48)
        #expect(result.velocity == [0, 0, 0.8])
        #expect(result.angularVelocity == [0.4, 0, 0])
        let patchVelocity = result.velocity + cross(result.angularVelocity, patch)
        #expect(simd_length(patchVelocity) <= 1e-6, "v + ω × r at the patch is what the solve brought to rest")
    }
}
