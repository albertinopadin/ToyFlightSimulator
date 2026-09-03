//
//  EulerSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

import simd

final class EulerSolver: PhysicsSolver {
    /// PhysicsSolver conformance and direct test entry: every pair is a
    /// candidate. PhysicsWorld uses the overload below with its own scratch.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        var pairs: [(RigidBody, RigidBody)] = []
        PhysicsWorld.appendAllPairs(of: entities, into: &pairs)
        var contacts: [Contact] = []
        step(deltaTime: deltaTime, gravity: gravity, entities: entities,
             collisionPairs: pairs, contactsScratch: &contacts)
    }

    /// Semi-implicit Euler: forces, then contacts on the candidate pairs,
    /// then integration.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody],
                            collisionPairs: [(RigidBody, RigidBody)],
                            contactsScratch: inout [Contact]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        contactsScratch.removeAll(keepingCapacity: true)
        for (a, b) in collisionPairs {
            HeckerCollisionResponse.resolvePair(a, b, contacts: &contactsScratch)
        }
        moveObjects(deltaTime: deltaTime, entities: entities)
        zeroForces(entities: entities)
    }

    public static func applyForces(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        for entity in entities where !entity.isStatic {
            let appliedGravity: float3 = entity.shouldApplyGravity ? gravity : .zero
            let acceleration: float3 = entity.force / entity.mass + appliedGravity
            entity.acceleration = acceleration
            entity.velocity += acceleration * deltaTime
        }
    }

    static func moveObjects(deltaTime: Float, entities: [RigidBody]) {
        for entity in entities where !entity.isStatic {
            entity.setPosition(entity.getPosition() + entity.velocity * deltaTime)
        }
    }

    // MARK: - Legacy reference code (unreferenced)

    /// Legacy per-axis response, unreferenced since A-response; kept as
    /// reference code. Below this relative speed it parked both bodies.
    private static let restSpeedThresholdSquared: Float = 0.55 * 0.55

    /// Legacy per-axis response, unreferenced since A-response; kept as
    /// reference code. Nothing may call it: both solvers share
    /// HeckerCollisionResponse.applyCollisionResponse.
    private static func applyLegacyEulerResponse(_ ei: RigidBody, _ ej: RigidBody, contact: Contact) {
        let collisionVector = contact.normal      // unit, from B toward A
        let restitution = min(ei.restitution, ej.restitution)
        let unormCollisionVector = contact.normal * contact.depth

        // Rest hack: park both bodies below the threshold, static or not.
        if simd_length_squared(ei.velocity - ej.velocity) < restSpeedThresholdSquared {
            ei.velocity = .zero
            ej.velocity = .zero
            return
        }

        if !ei.isStatic && !ej.isStatic {
            // Both dynamic: full-depth teleport apart, then reflect.
            ei.setPosition(ei.getPosition() + unormCollisionVector)
            ei.velocity = (ei.velocity + collisionVector) * restitution

            ej.setPosition(ej.getPosition() - unormCollisionVector)
            ej.velocity = (ej.velocity - collisionVector) * restitution
            return
        }

        if !ei.isStatic && ej.isStatic {
            // Dynamic A against static B: ×2 teleport, per-axis reflection.
            ei.setPosition(ei.getPosition() + unormCollisionVector * 2)
            let vX = collisionVector.x != 0 ? ei.velocity.x * -collisionVector.x * restitution : ei.velocity.x
            let vY = collisionVector.y != 0 ? ei.velocity.y * -collisionVector.y * restitution : ei.velocity.y
            let vZ = collisionVector.z != 0 ? ei.velocity.z * -collisionVector.z * restitution : ei.velocity.z
            ei.velocity = [vX, vY, vZ]
            return
        }

        if ei.isStatic && !ej.isStatic {
            // Static A against dynamic B: the legacy normal pointed away from
            // the static body, so negate before the same per-axis reflection.
            let legacyVector = -collisionVector
            let legacyUnorm = legacyVector * contact.depth
            ej.setPosition(ej.getPosition() + legacyUnorm * 2)
            let vX = legacyVector.x != 0 ? ej.velocity.x * -legacyVector.x * restitution : ej.velocity.x
            let vY = legacyVector.y != 0 ? ej.velocity.y * -legacyVector.y * restitution : ej.velocity.y
            let vZ = legacyVector.z != 0 ? ej.velocity.z * -legacyVector.z * restitution : ej.velocity.z
            ej.velocity = [vX, vY, vZ]
            return
        }
    }
}
