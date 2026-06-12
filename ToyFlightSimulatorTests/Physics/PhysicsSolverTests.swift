//
//  PhysicsSolverTests.swift
//  ToyFlightSimulatorTests
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

/// Minimal RigidBody test double. Position lives in a local `var` so solver
/// position writes don't require an attached GameObject (and the test stays
/// free of Metal/asset loading — `gameObject` is nil).
final class TestRigidBody: RigidBody {
    private var position: float3

    init(position: float3 = .zero,
         mass: Float = 1.0,
         velocity: float3 = .zero,
         force: float3 = .zero,
         isStatic: Bool = false,
         shouldApplyGravity: Bool = true,
         collisionShape: CollisionShape = .Sphere) {
        self.position = position
        super.init(gameObject: nil,
                   collisionShape: collisionShape,
                   mass: mass,
                   velocity: velocity,
                   force: force,
                   isStatic: isStatic,
                   shouldApplyGravity: shouldApplyGravity)
    }

    override func setPosition(_ position: float3) { self.position = position }
    override func getPosition() -> float3 { position }
    override func getAABB() -> AABB { AABB(center: position, radius: 0.5) }
}

@Suite("EulerSolver", .tags(.physics))
struct EulerSolverTests {

    private static let gravity: float3 = [0, -9.8, 0]

    // MARK: - applyForces

    @Test("applyForces integrates F=ma + gravity into acceleration and velocity")
    func applyForcesIntegratesForceAndGravity() {
        let body = TestRigidBody(mass: 2.0, force: [10, 0, 0])
        let entities: [RigidBody] = [body]

        EulerSolver.applyForces(deltaTime: 0.1, gravity: Self.gravity, entities: entities)

        // a = F/m + g = [10/2, -9.8, 0] = [5, -9.8, 0]
        #expect(approxEqual(entities[0].acceleration, [5, -9.8, 0]))
        // v += a * dt = [0.5, -0.98, 0]
        #expect(approxEqual(entities[0].velocity, [0.5, -0.98, 0]))
    }

    @Test("applyForces skips static bodies entirely")
    func applyForcesSkipsStaticBodies() {
        let body = TestRigidBody(mass: 1.0, force: [100, 100, 100], isStatic: true)
        let entities: [RigidBody] = [body]

        EulerSolver.applyForces(deltaTime: 1.0, gravity: Self.gravity, entities: entities)

        #expect(approxEqual(entities[0].velocity, .zero))
        #expect(approxEqual(entities[0].acceleration, .zero))
    }

    @Test("applyForces honours shouldApplyGravity = false")
    func applyForcesRespectsShouldApplyGravity() {
        let body = TestRigidBody(mass: 1.0, force: [0, 0, 0], shouldApplyGravity: false)
        let entities: [RigidBody] = [body]

        EulerSolver.applyForces(deltaTime: 0.1, gravity: Self.gravity, entities: entities)

        // No gravity, no force → acceleration and velocity remain zero.
        #expect(approxEqual(entities[0].acceleration, .zero))
        #expect(approxEqual(entities[0].velocity, .zero))
    }

    // MARK: - zeroForces

    @Test("zeroForces clears force on every entity (static or dynamic)")
    func zeroForcesClearsAllForces() {
        let dynamic = TestRigidBody(force: [1, 2, 3])
        let staticBody = TestRigidBody(force: [4, 5, 6], isStatic: true)
        let entities: [RigidBody] = [dynamic, staticBody]

        EulerSolver.zeroForces(entities: entities)

        #expect(approxEqual(entities[0].force, .zero))
        #expect(approxEqual(entities[1].force, .zero))
    }

    // MARK: - Full step semantics

    @Test("step zeroes force after integration so forces do not accumulate across frames")
    func stepClearsForceAfterIntegration() {
        let body = TestRigidBody(mass: 1.0, force: [10, 0, 0], shouldApplyGravity: false)
        let entities: [RigidBody] = [body]

        EulerSolver.step(deltaTime: 0.1, gravity: .zero, entities: entities)

        // After the step, velocity reflects the force, but force itself is zero.
        #expect(approxEqual(entities[0].velocity, [1, 0, 0]))
        #expect(approxEqual(entities[0].force, .zero))
    }

    @Test("Two consecutive steps without re-applying force do not double-integrate")
    func consecutiveStepsDoNotDoubleIntegrate() {
        let body = TestRigidBody(mass: 1.0, force: [10, 0, 0], shouldApplyGravity: false)
        let entities: [RigidBody] = [body]

        EulerSolver.step(deltaTime: 0.1, gravity: .zero, entities: entities)
        let velAfterFirst = entities[0].velocity

        EulerSolver.step(deltaTime: 0.1, gravity: .zero, entities: entities)
        let velAfterSecond = entities[0].velocity

        // Force was cleared at end of step 1; step 2 sees force=0, so velocity is unchanged.
        #expect(approxEqual(velAfterFirst, velAfterSecond))
    }

    @Test("Pair-consuming step integrates forces and clears them, same as the legacy step")
    func pairConsumingStepMatchesLegacyForceSemantics() {
        let body = TestRigidBody(mass: 1.0, force: [10, 0, 0], shouldApplyGravity: false)
        let entities: [RigidBody] = [body]

        EulerSolver.step(deltaTime: 0.1, gravity: .zero, entities: entities, collisionPairs: [])

        #expect(approxEqual(entities[0].velocity, [1, 0, 0]))
        #expect(approxEqual(entities[0].force, .zero))
    }
}

@Suite("VerletSolver", .tags(.physics))
struct VerletSolverTests {

    private static let gravity: float3 = [0, -10, 0]

    @Test("step zeroes force on dynamic entities after integration")
    func stepClearsForceAfterIntegration() {
        let body = TestRigidBody(mass: 1.0, force: [5, 0, 0], shouldApplyGravity: false)
        let entities: [RigidBody] = [body]

        VerletSolver.step(deltaTime: 0.1, gravity: .zero, entities: entities)

        #expect(approxEqual(entities[0].force, .zero))
    }

    @Test("Static body does not move under gravity")
    func staticBodiesDoNotFall() {
        let body = TestRigidBody(position: [0, 5, 0], isStatic: true)
        let entities: [RigidBody] = [body]

        VerletSolver.step(deltaTime: 0.1, gravity: Self.gravity, entities: entities)

        #expect(approxEqual(entities[0].getPosition(), [0, 5, 0]))
    }
}
