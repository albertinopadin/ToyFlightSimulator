//
//  AngularIntegration.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/11/26.
//

/// Rotation step shared by both solvers: semi-implicit Euler in two halves,
/// ω += I⁻¹_world · τ · h with the forces and a rotation by ω · h with the
/// positions, so the contact response between them sees this substep's
/// torques (Box2D and Jolt order it this way: velocities, constraints,
/// poses). Bodies with infinite inertia (the default) are skipped, so their
/// step is unchanged. No gyroscopic term (ω × Iω): small at aircraft rates,
/// and without it the explicit update has no stability condition of its own.
enum AngularIntegration {
    static func integrateAngularVelocity(entities: [RigidBody], deltaTime: Float) {
        for entity in entities where !entity.isStatic && entity.hasFiniteInertia {
            entity.angularVelocity += entity.inverseInertiaWorld() * entity.torque * deltaTime
        }
    }
    
    static func integrateOrientation(entities: [RigidBody], deltaTime: Float) {
        for entity in entities where !entity.isStatic && entity.hasFiniteInertia {
            entity.rotate(by: entity.angularVelocity * deltaTime)
        }
    }
}
