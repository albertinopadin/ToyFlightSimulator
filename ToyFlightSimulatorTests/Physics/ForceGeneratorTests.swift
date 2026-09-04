//
//  ForceGeneratorTests.swift
//  ToyFlightSimulatorTests
//
//  B.2 (B-generators): the per-body force hook PhysicsWorld calls at the top
//  of every substep. Metal-free — detached bodies in real PhysicsWorlds.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Force generators", .tags(.physics))
struct ForceGeneratorTests {
    private static let dt: Float = 1.0 / 60.0

    @Test("the hook runs once per substep with fixedDelta, on both solvers",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func hookRunsOncePerSubstep(_ updateType: PhysicsUpdateType) {
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
        // A 1/60 s update is two 1/120 s substeps (B.3).
        #expect(calls == 10)
        #expect(lastDelta == PhysicsWorld.fixedDelta)
    }

    @Test("a constant force accelerates the body through two full Verlet kicks")
    func constantForceAccelerates() {
        let body = RigidBody(detachedAt: .zero)
        body.mass = 2
        body.shouldApplyGravity = false
        body.forceGenerator = { body, _, _ in body.force += [10, 0, 0] }
        let world = PhysicsWorld(entities: [body], updateType: .HeckerVerlet)
        world.update(deltaTime: Self.dt)
        // The first substep is seeded (B.3b), so both substeps kick the full
        // (F/m)·h: 2 · 5 · h.
        #expect(approxEqual(body.velocity.x, 2 * 5 * PhysicsWorld.fixedDelta))
        #expect(body.force == .zero, "forces are zeroed at the end of the step")
    }

    @Test("force does not persist between substeps: a hook that writes once stops kicking")
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
        world.update(deltaTime: Self.dt)   // substep 1 sees the force, substep 2 does not
        // Trapezoid kicks: ½·(10 + 10)·h on the seeded substep that saw the
        // force, then ½·(10 + 0)·h from the carried a(t): 15·h in total.
        let kicked = body.velocity.x
        #expect(approxEqual(kicked, 1.5 * 10 * PhysicsWorld.fixedDelta))
        for _ in 0..<4 { world.update(deltaTime: Self.dt) }
        #expect(body.velocity.x == kicked, "no force after the first substep, no further change")
    }
}
