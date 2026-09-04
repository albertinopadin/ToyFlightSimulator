//
//  ForceGeneratorTests.swift
//  ToyFlightSimulatorTests
//
//  B.2 (B-generators): the per-body force hook PhysicsWorld calls at the top
//  of every step. Metal-free — detached bodies in real PhysicsWorlds.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Force generators", .tags(.physics))
struct ForceGeneratorTests {
    private static let dt: Float = 1.0 / 60.0

    @Test("the hook runs once per update with the step delta, on both solvers",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func hookRunsOncePerUpdate(_ updateType: PhysicsUpdateType) {
        let body = RigidBody(detachedAt: .zero)
        body.shouldApplyGravity = false
        var calls = 0
        var lastDelta: Float = 0
        body.forceGenerator = { _, delta, _ in
            calls += 1
            lastDelta = delta
        }
        let world = PhysicsWorld(entities: [body], updateType: updateType)
        for _ in 0..<5 { world.update(deltaTime: Self.dt) }
        #expect(calls == 5)               // B.3: 10 (two substeps per update)
        #expect(lastDelta == Self.dt)     // B.3: PhysicsWorld.fixedDelta
    }

    @Test("a constant force accelerates the body through the Verlet half kick")
    func constantForceAccelerates() {
        let body = RigidBody(detachedAt: .zero)
        body.mass = 2
        body.shouldApplyGravity = false
        body.forceGenerator = { body, _, _ in body.force += [10, 0, 0] }
        let world = PhysicsWorld(entities: [body], updateType: .HeckerVerlet)
        world.update(deltaTime: Self.dt)
        // Velocity Verlet starts with a half kick: Δv = ½·(F/m)·dt.
        #expect(approxEqual(body.velocity.x, 0.5 * 5 * Self.dt))   // B.3: 1.5 · 5 · fixedDelta
        #expect(body.force == .zero, "forces are zeroed at the end of the step")
    }

    @Test("force does not persist between steps: a hook that writes once kicks once")
    func forceWrittenOnceKicksOnce() {
        let body = RigidBody(detachedAt: .zero)
        body.shouldApplyGravity = false
        var written = false
        body.forceGenerator = { body, _, _ in
            if !written {
                body.force += [10, 0, 0]
                written = true
            }
        }
        let world = PhysicsWorld(entities: [body], updateType: .HeckerVerlet)
        for _ in 0..<5 { world.update(deltaTime: Self.dt) }
        // The one step that saw the force contributes its half kick, the next
        // step the carried acceleration's other half, then nothing:
        // Δv = (F/m)·dt, not five steps' worth.
        #expect(approxEqual(body.velocity.x, 10 * Self.dt))   // B.3: 10 · fixedDelta
    }
}
