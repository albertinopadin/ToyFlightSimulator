//
//  AngularIntegrationTests.swift
//  ToyFlightSimulatorTests
//
//  D.1 (D-angular-plumbing): the rotation step shared by both solvers —
//  ω += I⁻¹_world · τ · h with the forces and before the contact response, a
//  rotation by ω · h with the positions — on detached bodies stepped through
//  real PhysicsWorlds, one 1/120 s substep per update. Metal-free. Every
//  expected value was reproduced by hand from the listing before the tests
//  ran; the exact comparisons are exact in Float, the others carry their
//  tolerance.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Angular integration", .tags(.physics))
struct AngularIntegrationTests {
    /// One substep.
    private static let h = PhysicsWorld.fixedDelta

    /// I⁻¹ = diag(0.5): a torque of [2, 0, 0] gives dω/dt = [1, 0, 0].
    private static let halfInverseInertia = float3x3(diagonal: [0.5, 0.5, 0.5])

    /// A detached body with gravity off and a hook that adds the same
    /// torque on every substep; the tensor is the caller's.
    private func makeTorquedBody(inverseInertiaLocal: float3x3,
                                 torque: float3 = [2, 0, 0],
                                 at position: float3 = .zero) -> RigidBody {
        let body = RigidBody(detachedAt: position)
        body.shouldApplyGravity = false
        body.inverseInertiaLocal = inverseInertiaLocal
        body.forceGenerator = { body, _, _ in body.torque += torque }
        return body
    }

    /// Rotation about +X by `angle`, written out so the check does not share
    /// the code's quaternion path: columns are the rotated basis axes.
    private func rotationAboutX(_ angle: Float) -> float3x3 {
        float3x3(columns: ([1, 0, 0],
                           [0, cos(angle), sin(angle)],
                           [0, -sin(angle), cos(angle)]))
    }

    @Test("an infinite-inertia body under a constant torque never rotates and keeps ω = 0",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func infiniteInertiaNeverRotates(_ updateType: PhysicsUpdateType) {
        let body = makeTorquedBody(inverseInertiaLocal: RigidBody.infiniteInertia)
        let world = PhysicsWorld(entities: [body], updateType: updateType)
        for _ in 0..<120 { world.update(deltaTime: Self.h) }   // 1 s
        #expect(body.angularVelocity == .zero)
        #expect(body.pose().rotation == matrix_identity_float3x3)
        #expect(body.getPosition() == .zero)
    }

    @Test("one substep: ω = I⁻¹ τ h exactly, then the body has rotated by the NEW ω · h about X",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func oneSubstepIntegratesTorqueThenOrientation(_ updateType: PhysicsUpdateType) {
        let body = makeTorquedBody(inverseInertiaLocal: Self.halfInverseInertia)
        let world = PhysicsWorld(entities: [body], updateType: updateType)

        world.update(deltaTime: Self.h)

        // 0.5 · 2 · h = h, exact in Float: at the identity pose I⁻¹_world is
        // I⁻¹ itself, and 0.5 · 2 is 1.
        #expect(body.angularVelocity == [Self.h, 0, 0])
        // The orientation half runs after the velocity half (semi-implicit),
        // so the first substep already rotates, by h · h rad about +X.
        #expect(approxEqual(body.pose().rotation, rotationAboutX(Self.h * Self.h), tolerance: 1e-6))
        // A torque alone moves nothing.
        #expect(body.getPosition() == .zero)
        #expect(body.velocity == .zero)
    }

    @Test("a static body with finite inertia and torque does not rotate",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func staticBodyDoesNotRotate(_ updateType: PhysicsUpdateType) {
        let body = makeTorquedBody(inverseInertiaLocal: Self.halfInverseInertia)
        body.isStatic = true
        let world = PhysicsWorld(entities: [body], updateType: updateType)
        for _ in 0..<10 { world.update(deltaTime: Self.h) }
        #expect(body.angularVelocity == .zero)
        #expect(body.pose().rotation == matrix_identity_float3x3)
    }

    @Test("torque is a per-substep accumulator: zero after every step, so a constant hook grows ω linearly",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func torqueIsZeroedEveryStep(_ updateType: PhysicsUpdateType) {
        let body = makeTorquedBody(inverseInertiaLocal: Self.halfInverseInertia)
        let world = PhysicsWorld(entities: [body], updateType: updateType)
        for substeps in 1...5 {
            world.update(deltaTime: Self.h)
            #expect(body.torque == .zero)
            // The hook re-adds [2, 0, 0] each substep. Were the accumulator
            // not zeroed, ω would grow quadratically. (I⁻¹ is isotropic, so
            // the growing rotation about X leaves I⁻¹_world = diag(0.5) up to
            // rounding, hence the tolerance.)
            #expect(approxEqual(body.angularVelocity, [Float(substeps) * Self.h, 0, 0], tolerance: 1e-6))
        }
    }

    @Test("the two halves are separable: the velocity half moves ω and not the pose, the orientation half the pose and not ω")
    func halvesAreSeparable() {
        let body = RigidBody(detachedAt: .zero)
        body.inverseInertiaLocal = Self.halfInverseInertia
        body.torque = [2, 0, 0]

        AngularIntegration.integrateAngularVelocity(entities: [body], deltaTime: Self.h)
        #expect(body.angularVelocity == [Self.h, 0, 0])
        #expect(body.pose().rotation == matrix_identity_float3x3)
        #expect(body.torque == [2, 0, 0], "the halves do not touch the accumulator; zeroForces does")

        AngularIntegration.integrateOrientation(entities: [body], deltaTime: Self.h)
        #expect(body.angularVelocity == [Self.h, 0, 0])
        #expect(approxEqual(body.pose().rotation, rotationAboutX(Self.h * Self.h), tolerance: 1e-6))

        // Both halves skip infinite-inertia bodies and static ones.
        let stiff = RigidBody(detachedAt: .zero)
        stiff.torque = [2, 0, 0]
        let parked = RigidBody(detachedAt: .zero)
        parked.inverseInertiaLocal = Self.halfInverseInertia
        parked.isStatic = true
        parked.torque = [2, 0, 0]
        parked.angularVelocity = [1, 0, 0]
        AngularIntegration.integrateAngularVelocity(entities: [stiff, parked], deltaTime: Self.h)
        AngularIntegration.integrateOrientation(entities: [stiff, parked], deltaTime: Self.h)
        #expect(stiff.angularVelocity == .zero)
        #expect(stiff.pose().rotation == matrix_identity_float3x3)
        #expect(parked.angularVelocity == [1, 0, 0])
        #expect(parked.pose().rotation == matrix_identity_float3x3)
    }

    @Test("the contact response sees this substep's torque: ω is integrated before the pair loop in both solvers",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func responseSeesThisSubstepsTorque(_ updateType: PhysicsUpdateType) throws {
        // A sphere collider resting on a static plane 1 mm deep (under the
        // 5 mm slop, so no position correction), at rest with gravity off
        // (no approach at the point, so no impulse): the contact fires every
        // substep and changes nothing. A sphere's contact has no lever arm in
        // any case — r is along n — so an impulse could not spin it either.
        let body = makeTorquedBody(inverseInertiaLocal: Self.halfInverseInertia, at: [0, 0.499, 0])
        body.colliders = [LocalCollider(name: "ball", shape: .sphere(radius: 0.5))]
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [body, plane], updateType: updateType)
        world.useBroadPhase = false

        var recorded: [float3] = []
        body.onContact = { [unowned body] _, _ in recorded.append(body.angularVelocity) }

        world.update(deltaTime: Self.h)

        let seen = try #require(recorded.first)
        #expect(recorded.count == 1, "one collider against one plane: one contact per substep")
        // 0.5 · 2 · h: the torque's own half-step, already in ω when the
        // handler ran. The second draft's Verlet order (both halves after the
        // response) recorded zero here.
        #expect(seen == [Self.h, 0, 0])
        #expect(body.angularVelocity == [Self.h, 0, 0])
        #expect(approxEqual(body.getPosition(), [0, 0.499, 0]), "no correction under the slop, no impulse at rest")
    }

    @Test("orthonormality soak: 72 000 substeps of free rotation keep R orthonormal within 1e-5",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func orthonormalitySoak(_ updateType: PhysicsUpdateType) {
        // Ten minutes at 120 Hz, a few milliseconds of test time. rotate(by:)
        // composes through a normalised quaternion and rebuilds the matrix,
        // so each substep's output is orthonormal to float precision whatever
        // came before. The bare matrix product Node.rotate uses drifts over
        // the same run to about 5e-5 in column length and 9e-5 in the
        // determinant (reproduced at review), past this test's band.
        let body = RigidBody(detachedAt: .zero)
        body.shouldApplyGravity = false
        body.inverseInertiaLocal = matrix_identity_float3x3
        body.angularVelocity = [0.3, 0.5, 0.7]
        let world = PhysicsWorld(entities: [body], updateType: updateType)

        for _ in 0..<72_000 { world.update(deltaTime: Self.h) }

        let rotation = body.pose().rotation
        let columns = [rotation.columns.0, rotation.columns.1, rotation.columns.2]
        for column in columns {
            #expect(abs(simd_length(column) - 1) <= 1e-5)
        }
        #expect(abs(dot(columns[0], columns[1])) <= 1e-5)
        #expect(abs(dot(columns[1], columns[2])) <= 1e-5)
        #expect(abs(dot(columns[0], columns[2])) <= 1e-5)
        #expect(abs(rotation.determinant - 1) <= 1e-5)
        // Free rotation: no torque, so the velocity half adds exactly zero.
        #expect(body.angularVelocity == [0.3, 0.5, 0.7])
    }
}
