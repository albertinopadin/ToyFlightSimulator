//
//  PhysicsWorldSmokeTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("PhysicsWorld smoke", .tags(.physics))
struct PhysicsWorldSmokeTests {

    /// Step a world repeatedly and return the sphere's final Y position
    /// plus a flag saying whether it crossed below the plane during the
    /// run (i.e., whether collision response held it back).
    private func runFallingSphere(updateType: PhysicsUpdateType,
                                  startHeight: Float,
                                  steps: Int,
                                  deltaTime: Float) -> (finalY: Float, hitPlane: Bool) {
        let sphere = Sphere()
        sphere.setPosition([0, startHeight, 0])
        let sphereRB = SphereRigidBody(gameObject: sphere, collisionRadius: 0.5)
        sphereRB.mass = 1.0
        sphereRB.restitution = 0.0  // No bounce — just settle.

        let ground = Quad()
        let groundRB = PlaneRigidBody(gameObject: ground, collisionNormal: [0, 1, 0])
        groundRB.isStatic = true

        let world = PhysicsWorld(entities: [sphereRB, groundRB], updateType: updateType)
        world.useBroadPhase = false  // Avoid broad-phase ordering effects in a 2-body test.

        var minY: Float = .greatestFiniteMagnitude
        for _ in 0..<steps {
            world.update(deltaTime: deltaTime)
            minY = Swift.min(minY, sphere.getPositionY())
        }
        // "hit" means the sphere center dipped to within (or below) one
        // radius of the plane during the run — i.e., the collision logic
        // actually engaged.
        return (sphere.getPositionY(), minY <= sphereRB.collisionRadius + 0.5)
    }

    @Test("Sphere falls toward a static plane under Verlet integration")
    func sphereFallsTowardPlane_Verlet() {
        let (finalY, hitPlane) = runFallingSphere(updateType: .HeckerVerlet,
                                                  startHeight: 20.0,
                                                  steps: 60,
                                                  deltaTime: 1.0 / 60.0)

        #expect(finalY < 20.0, "Sphere should have lost altitude under gravity (final Y = \(finalY))")
        #expect(hitPlane, "Sphere should have reached the plane during a 1-second drop from 20m")
    }

    @Test("Static plane never moves while a dynamic sphere falls onto it")
    func staticPlaneDoesNotMove() {
        let sphere = Sphere()
        sphere.setPosition([0, 10, 0])
        _ = SphereRigidBody(gameObject: sphere, collisionRadius: 0.5)

        let ground = Quad()
        let groundStart = ground.getPosition()
        let groundRB = PlaneRigidBody(gameObject: ground, collisionNormal: [0, 1, 0])
        groundRB.isStatic = true

        let world = PhysicsWorld(entities: [sphere.rigidBody!, groundRB], updateType: .HeckerVerlet)
        world.useBroadPhase = false

        for _ in 0..<60 {
            world.update(deltaTime: 1.0 / 60.0)
        }

        #expect(approxEqual(ground.getPosition(), groundStart),
                "Static ground plane drifted: \(ground.getPosition()) vs \(groundStart)")
    }

    @Test("RigidBody force is zeroed every frame so player input only counts once")
    func forceIsZeroedEveryFrame() {
        let sphere = Sphere()
        sphere.setPosition([0, 50, 0])
        let rb = SphereRigidBody(gameObject: sphere, collisionRadius: 0.5)
        rb.mass = 1.0
        rb.shouldApplyGravity = false

        let world = PhysicsWorld(entities: [rb], updateType: .NaiveEuler)
        world.useBroadPhase = false

        // Apply an upward "engine" force this frame only.
        rb.force = [0, 100, 0]
        world.update(deltaTime: 1.0 / 60.0)
        let velAfterPush = rb.velocity
        #expect(velAfterPush.y > 0, "Upward force should produce upward velocity")
        #expect(approxEqual(rb.force, .zero), "force must be cleared at end of step")

        // Next frame with no input → velocity should not grow.
        world.update(deltaTime: 1.0 / 60.0)
        #expect(approxEqual(rb.velocity, velAfterPush),
                "velocity changed without any new force; force is being re-applied across frames")
    }

    @Test("shouldApplyGravity=false keeps a body in place under EulerSolver")
    func eulerHonoursShouldApplyGravity() {
        let sphere = Sphere()
        sphere.setPosition([0, 50, 0])
        let rb = SphereRigidBody(gameObject: sphere, collisionRadius: 0.5)
        rb.mass = 1.0
        rb.shouldApplyGravity = false

        let world = PhysicsWorld(entities: [rb], updateType: .NaiveEuler)
        world.useBroadPhase = false

        for _ in 0..<60 {
            world.update(deltaTime: 1.0 / 60.0)
        }

        #expect(approxEqual(sphere.getPosition(), [0, 50, 0], tolerance: 1e-3),
                "Body with shouldApplyGravity=false drifted: \(sphere.getPosition())")
    }
}
