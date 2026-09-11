//
//  StructureContactTests.swift
//  ToyFlightSimulatorTests
//
//  C.2 (C-structures): the airfield's static bodies driving the full pipeline
//  Metal-free. A structure's body is what StaticStructure.init builds, minus
//  the node and mesh: a detached RigidBody with one .structure collider,
//  static, no gravity, restitution 0.3. The aircraft is the detached F-22
//  compound from CompoundBodyTests. The broad phase stays ON, as in the app:
//  structures reach the narrow phase through its dynamic-vs-static loop, and
//  two statics (a tree and the ground) never pair.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Structure contacts (world)", .tags(.physics))
struct StructureContactTests {
    private static let dt: Float = 1.0 / 60.0

    /// Nose-to-origin reach of the F-22's fuselage capsule: local z 0.6 plus
    /// half height 8.1 plus radius 1.35 (AircraftColliderSpec).
    private static let fuselageNoseReach: Float = 0.6 + 8.1 + 1.35

    /// StaticStructure's body on a detached body: the shape's collider,
    /// named so contacts can name the part.
    private func makeStructure(_ name: String, shape: StaticStructure.Shape, at position: float3) -> RigidBody {
        let body = RigidBody(detachedAt: position)
        body.colliders = [LocalCollider(name: name, shape: shape.collider, group: .structure)]
        body.isStatic = true
        body.shouldApplyGravity = false
        body.restitution = 0.3
        body.categoryMask = CollisionCategory.structure
        return body
    }

    /// The live F-22 compound (fuselage capsule, wings box, empennage box) on
    /// a detached body: identity rotation, so the airframe is level and its
    /// local axes are the world's.
    private func makeF22(at position: float3, velocity: float3, gravity: Bool) -> RigidBody {
        let body = RigidBody(detachedAt: position)
        body.mass = 30_000
        body.restitution = 0.2
        body.velocity = velocity
        body.shouldApplyGravity = gravity
        body.colliders = AircraftColliderSpec.spec(for: .f22_cgtrader)
        return body
    }

    @Test("wall strike: the fuselage hits the wall by name as an impact at the approach speed; the wall never moves; the jet stops or rebounds")
    func wallStrike() throws {
        // A 40 × 12 × 3 m wall centered at [0, 6, 1.5]: x −20…20, y 0…12,
        // near face at z 0. The F-22 at [0, 5, −20] flying +Z at 30 m/s
        // (0.25 m per substep), gravity off for a clean read: the nose,
        // 10.05 m ahead of the origin, reaches the face after 40 substeps
        // with the wings (z −13.9…−8.5 then) still clear.
        let wall = makeStructure("wall", shape: .box(size: [40, 12, 3]), at: [0, 6, 1.5])
        let wallStart = wall.getPosition()
        let jet = makeF22(at: [0, 5, -20], velocity: [0, 0, 30], gravity: false)
        let world = PhysicsWorld(entities: [jet, wall], updateType: .HeckerVerlet)

        var contacts: [(part: String, against: String, speed: Float, cls: AirframeContactClass)] = []
        jet.onContact = { [unowned jet] contact, _ in
            let speed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal,
                                                              preImpactVelocity: jet.stepStartVelocity)
            contacts.append((contact.colliderNameA ?? "?",
                             contact.colliderNameB ?? "?",
                             speed,
                             AirframeContactClassifier.classification(forNormalSpeed: speed)))
        }

        for _ in 0..<60 { world.update(deltaTime: Self.dt) }   // 1 s

        let first = try #require(contacts.first)
        #expect(first.part == "fuselage")
        #expect(first.against == "wall")
        #expect(first.cls == .impact)
        #expect(abs(first.speed - 30) <= 0.5, "stepStartVelocity carries the 30 m/s approach")
        // e = min(0.2, 0.3) on a 30 m/s approach sends the jet back at 6 m/s,
        // 5 cm per substep: the nose clears the face on the next step, so
        // there is one impact and no scrape.
        #expect(contacts.filter { $0.cls == .impact }.count == 1)

        #expect(wall.getPosition() == wallStart, "statics never move")

        // Still on the near side: the nose has not passed the face.
        #expect(jet.getPosition().z + Self.fuselageNoseReach <= 0)
        // Stopped or rebounding, at up to 0.2 × 30 m/s.
        #expect(jet.velocity.z <= 0)
        #expect(jet.velocity.z >= -0.2 * 30 - 1e-3)
    }

    @Test("wing over a wall: the wings box strikes by name, at a point on the wall's face inside the wing's outline")
    func wingOverWall() throws {
        // A 3 × 12 × 40 m wall centered at [13.5, 6, 0]: x 12…15, along z.
        // The F-22's origin at [8.5, 5, −10]: the wings box (half span 6.6)
        // reaches x 15.1, inside the wall's slab; the fuselage capsule
        // (radius 1.35) reaches x 9.85 and the empennage (half span 3.0)
        // x 11.5, both clear. Box-box, not capsule-box.
        let wall = makeStructure("wall", shape: .box(size: [3, 12, 40]), at: [13.5, 6, 0])
        let jet = makeF22(at: [8.5, 5, -10], velocity: [0, 0, 5], gravity: false)
        let world = PhysicsWorld(entities: [jet, wall], updateType: .HeckerVerlet)

        var contacts: [Contact] = []
        jet.onContact = { contact, _ in contacts.append(contact) }

        for _ in 0..<6 { world.update(deltaTime: Self.dt) }

        let first = try #require(contacts.first)
        #expect(first.colliderNameA == "wings")
        #expect(first.colliderNameB == "wall")
        #expect(!contacts.contains { $0.colliderNameA == "fuselage" })
        // Least overlap is along x: (6.6 + 1.5) − 5 = 3.1, the normal from
        // the wall toward the jet.
        #expect(approxEqual(first.normal, [-1, 0, 0]))
        #expect(approxEqual(first.depth, 3.1, tolerance: 1e-3))
        // The wall's inner face (x 12) clipped to the wing's y and z ranges
        // and averaged: centered on the wing box (y 5.15, z −11.2), inside
        // both boxes. The first draft's face-center rule gave [12, 6, 0],
        // 8.5 m from the wing and 10 m ahead of an origin the wing sits
        // behind — the wrong sign for D.3's yaw.
        #expect(approxEqual(first.point, [12, 5.15, -11.2], tolerance: 0.05))
    }

    @Test("ball on a roof: a dropped sphere rests on a box top at roof + radius, gravity on")
    func ballRestsOnRoof() {
        // A 10 × 1 × 10 m slab centered at y 0.5: top at y 1. The ball
        // (radius 0.5) drops from a 3 m center height, bounces at 0.2, and
        // settles at 1.5 minus the response's ≈7 mm rest penetration.
        let roof = makeStructure("roof", shape: .box(size: [10, 1, 10]), at: [0, 0.5, 0])
        let ball = SphereRigidBody(detachedAt: [0, 3, 0], collisionRadius: 0.5)
        ball.restitution = 0.2
        let world = PhysicsWorld(entities: [ball, roof], updateType: .HeckerVerlet)

        var against: Set<String> = []
        ball.onContact = { contact, _ in
            if let name = contact.colliderNameB { against.insert(name) }
        }

        for _ in 0..<300 { world.update(deltaTime: Self.dt) }   // 5 s

        #expect(ball.shouldApplyGravity)
        #expect(abs(ball.getPosition().y - 1.5) <= 0.02)
        #expect(simd_length(ball.velocity) <= 0.1)
        #expect(against == ["roof"])
        #expect(roof.getPosition() == [0, 0.5, 0], "statics never move")
    }

    @Test("ball against a tree: a sliding sphere meets a vertical capsule on a horizontal normal, naming the tree")
    func ballAgainstTree() throws {
        // The ball (radius 0.5) slides along the ground at 3 m/s (no tangent
        // force exists, so it keeps its speed) into a tree: a vertical
        // capsule of radius 0.5 and half height 4.5, centered at y 4.5 so
        // its core (y 0…9) spans the ball's center height and the closest
        // core point is level with it: the normal is exactly horizontal.
        // The scene's trees stand with their cap bottoms on the ground
        // (center y 5), where a resting ball meets the core's lower end
        // 7 mm above its own center — a 0.4° tilt, invisible in play but
        // outside this test's band.
        let ground = PlaneRigidBody(detachedAt: .zero)
        ground.isStatic = true
        let tree = makeStructure("tree", shape: .capsule(radius: 0.5, height: 10), at: [0, 4.5, 0])
        let ball = SphereRigidBody(detachedAt: [-4, 0.5, 0], collisionRadius: 0.5)
        ball.restitution = 0.2
        ball.velocity = [3, 0, 0]
        let world = PhysicsWorld(entities: [ball, ground, tree], updateType: .HeckerVerlet)

        var treeContacts: [Contact] = []
        ball.onContact = { contact, _ in
            if contact.colliderNameB == "tree" { treeContacts.append(contact) }
        }

        for _ in 0..<120 { world.update(deltaTime: Self.dt) }   // 2 s; the tree is 3 m away, reached at 1 s

        let first = try #require(treeContacts.first)
        #expect(first.colliderNameB == "tree")
        #expect(first.colliderNameA == nil, "a SphereRigidBody's view has no name")
        #expect(abs(first.normal.y) < 1e-3)
        #expect(approxEqual(first.normal, [-1, 0, 0], tolerance: 1e-3))
        #expect(tree.getPosition() == [0, 4.5, 0], "statics never move")
        // e = min(0.2, 0.3) on 3 m/s sends the ball back at 0.6 m/s.
        #expect(ball.velocity.x < 0)
    }
}
