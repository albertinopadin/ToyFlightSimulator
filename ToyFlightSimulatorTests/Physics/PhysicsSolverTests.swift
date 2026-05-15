//
//  PhysicsSolverTests.swift
//  ToyFlightSimulatorTests
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

/// Minimal PhysicsEntity stub used by solver tests. Position lives in a
/// `var` so the solver can mutate it through `setPosition`.
final class PhysicsEntityStub: PhysicsEntity {
    let id: String
    var collisionShape: CollisionShape
    var collidedWith: [String : Bool] = [:]
    var mass: Float
    var velocity: float3
    var acceleration: float3
    var force: float3
    var restitution: Float
    var isStatic: Bool
    var shouldApplyGravity: Bool
    private var position: float3

    init(position: float3 = .zero,
         mass: Float = 1.0,
         velocity: float3 = .zero,
         force: float3 = .zero,
         isStatic: Bool = false,
         shouldApplyGravity: Bool = true,
         collisionShape: CollisionShape = .Sphere) {
        self.id = UUID().uuidString
        self.collisionShape = collisionShape
        self.mass = mass
        self.velocity = velocity
        self.acceleration = .zero
        self.force = force
        self.restitution = 1.0
        self.isStatic = isStatic
        self.shouldApplyGravity = shouldApplyGravity
        self.position = position
    }

    func setPosition(_ position: float3) { self.position = position }
    func getPosition() -> float3 { position }
    func getAABB() -> AABB { AABB(center: position, radius: 0.5) }
}

@Suite("EulerSolver", .tags(.physics))
struct EulerSolverTests {

    private static let gravity: float3 = [0, -9.8, 0]

    // MARK: - applyForces

    @Test("applyForces integrates F=ma + gravity into acceleration and velocity")
    func applyForcesIntegratesForceAndGravity() {
        let body = PhysicsEntityStub(mass: 2.0, force: [10, 0, 0])
        var entities: [PhysicsEntity] = [body]

        EulerSolver.applyForces(deltaTime: 0.1, gravity: Self.gravity, entities: &entities)

        // a = F/m + g = [10/2, -9.8, 0] = [5, -9.8, 0]
        #expect(approxEqual(entities[0].acceleration, [5, -9.8, 0]))
        // v += a * dt = [0.5, -0.98, 0]
        #expect(approxEqual(entities[0].velocity, [0.5, -0.98, 0]))
    }

    @Test("applyForces skips static bodies entirely")
    func applyForcesSkipsStaticBodies() {
        let body = PhysicsEntityStub(mass: 1.0, force: [100, 100, 100], isStatic: true)
        var entities: [PhysicsEntity] = [body]

        EulerSolver.applyForces(deltaTime: 1.0, gravity: Self.gravity, entities: &entities)

        #expect(approxEqual(entities[0].velocity, .zero))
        #expect(approxEqual(entities[0].acceleration, .zero))
    }

    @Test("applyForces honours shouldApplyGravity = false")
    func applyForcesRespectsShouldApplyGravity() {
        let body = PhysicsEntityStub(mass: 1.0, force: [0, 0, 0], shouldApplyGravity: false)
        var entities: [PhysicsEntity] = [body]

        EulerSolver.applyForces(deltaTime: 0.1, gravity: Self.gravity, entities: &entities)

        // No gravity, no force → acceleration and velocity remain zero.
        #expect(approxEqual(entities[0].acceleration, .zero))
        #expect(approxEqual(entities[0].velocity, .zero))
    }

    // MARK: - zeroForces

    @Test("zeroForces clears force on every entity (static or dynamic)")
    func zeroForcesClearsAllForces() {
        let dynamic = PhysicsEntityStub(force: [1, 2, 3])
        let staticBody = PhysicsEntityStub(force: [4, 5, 6], isStatic: true)
        var entities: [PhysicsEntity] = [dynamic, staticBody]

        EulerSolver.zeroForces(entities: &entities)

        #expect(approxEqual(entities[0].force, .zero))
        #expect(approxEqual(entities[1].force, .zero))
    }

    // MARK: - Full step semantics

    @Test("step zeroes force after integration so forces do not accumulate across frames")
    func stepClearsForceAfterIntegration() {
        let body = PhysicsEntityStub(mass: 1.0, force: [10, 0, 0], shouldApplyGravity: false)
        var entities: [PhysicsEntity] = [body]

        EulerSolver.step(deltaTime: 0.1, gravity: .zero, entities: &entities)

        // After the step, velocity reflects the force, but force itself is zero.
        #expect(approxEqual(entities[0].velocity, [1, 0, 0]))
        #expect(approxEqual(entities[0].force, .zero))
    }

    @Test("Two consecutive steps without re-applying force do not double-integrate")
    func consecutiveStepsDoNotDoubleIntegrate() {
        let body = PhysicsEntityStub(mass: 1.0, force: [10, 0, 0], shouldApplyGravity: false)
        var entities: [PhysicsEntity] = [body]

        EulerSolver.step(deltaTime: 0.1, gravity: .zero, entities: &entities)
        let velAfterFirst = entities[0].velocity

        EulerSolver.step(deltaTime: 0.1, gravity: .zero, entities: &entities)
        let velAfterSecond = entities[0].velocity

        // Force was cleared at end of step 1; step 2 sees force=0, so velocity is unchanged.
        #expect(approxEqual(velAfterFirst, velAfterSecond))
    }
}

@Suite("VerletSolver", .tags(.physics))
struct VerletSolverTests {

    private static let gravity: float3 = [0, -10, 0]

    @Test("step zeroes force on dynamic entities after integration")
    func stepClearsForceAfterIntegration() {
        let body = PhysicsEntityStub(mass: 1.0, force: [5, 0, 0], shouldApplyGravity: false)
        var entities: [PhysicsEntity] = [body]

        VerletSolver.step(deltaTime: 0.1, gravity: .zero, entities: &entities)

        #expect(approxEqual(entities[0].force, .zero))
    }

    @Test("Static body does not move under gravity")
    func staticBodiesDoNotFall() {
        let body = PhysicsEntityStub(position: [0, 5, 0], isStatic: true)
        var entities: [PhysicsEntity] = [body]

        VerletSolver.step(deltaTime: 0.1, gravity: Self.gravity, entities: &entities)

        #expect(approxEqual(entities[0].getPosition(), [0, 5, 0]))
    }
}
