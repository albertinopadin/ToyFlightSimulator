//
//  EulerSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

import simd

final class EulerSolver: PhysicsSolver {
    /// Below this relative speed, colliding bodies are parked (anti-jitter hack).
    /// Stored squared so the hot path compares length_squared with no sqrt.
    private static let restSpeedThresholdSquared: Float = 0.55 * 0.55

    /// Legacy O(n²) step — kept as the `useBroadPhase == false` comparison baseline.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        resolveCollisionsAllPairs(entities: entities)
        moveObjects(deltaTime: deltaTime, entities: entities)
        zeroForces(entities: entities)
    }

    /// P1: broad-phase-driven step. Same force/move/zero phases; collision
    /// resolution only inspects the candidate pairs.
    public static func step(deltaTime: Float,
                            gravity: float3,
                            entities: [RigidBody],
                            collisionPairs: [(RigidBody, RigidBody)]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        for (ei, ej) in collisionPairs {
            resolvePair(ei, ej)
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

    /// O(n²) all-pairs resolve for the no-broad-phase path. Visits each
    /// unordered pair once — the old i≠j double visit's second leg was already
    /// a no-op thanks to the collidedWith guard, so this just skips it outright.
    static func resolveCollisionsAllPairs(entities: [RigidBody]) {
        for i in 0..<entities.count {
            for j in (i + 1)..<entities.count {
                resolvePair(entities[i], entities[j])
            }
        }
    }

    /// Narrow phase + response for one candidate pair.
    private static func resolvePair(_ ei: RigidBody, _ ej: RigidBody) {
        guard !ei.collidedWith.contains(ObjectIdentifier(ej)),
              PhysicsWorld.collided(entityA: ei, entityB: ej) else { return }

        ei.collidedWith.insert(ObjectIdentifier(ej))
        ej.collidedWith.insert(ObjectIdentifier(ei))

        let collisionData = PhysicsWorld.getCollisionData(ei, ej)
        let collisionVector = collisionData.collisionVector
        let restitution = min(ei.restitution, ej.restitution)
        let unormCollisionVector = collisionData.collisionVector * collisionData.penetrationDepth

        // Hack to prevent infinite bouncing (squared compare — was .magnitude < 0.55):
        if simd_length_squared(ei.velocity - ej.velocity) < restSpeedThresholdSquared {
            ei.velocity = .zero
            ej.velocity = .zero
            return
        }

        if !ei.isStatic && !ej.isStatic {
            ei.setPosition(ei.getPosition() + unormCollisionVector)
            ei.velocity = (ei.velocity + collisionVector) * restitution

            ej.setPosition(ej.getPosition() - unormCollisionVector)
            ej.velocity = (ej.velocity - collisionVector) * restitution
            return
        }

        if !ei.isStatic && ej.isStatic {
            ei.setPosition(ei.getPosition() + unormCollisionVector * 2)
            let vX = collisionVector.x != 0 ? ei.velocity.x * -collisionVector.x * restitution : ei.velocity.x
            let vY = collisionVector.y != 0 ? ei.velocity.y * -collisionVector.y * restitution : ei.velocity.y
            let vZ = collisionVector.z != 0 ? ei.velocity.z * -collisionVector.z * restitution : ei.velocity.z
            ei.velocity = [vX, vY, vZ]
            return
        }

        if ei.isStatic && !ej.isStatic {
            ej.setPosition(ej.getPosition() + unormCollisionVector * 2)
            let vX = collisionVector.x != 0 ? ej.velocity.x * -collisionVector.x * restitution : ej.velocity.x
            let vY = collisionVector.y != 0 ? ej.velocity.y * -collisionVector.y * restitution : ej.velocity.y
            let vZ = collisionVector.z != 0 ? ej.velocity.z * -collisionVector.z * restitution : ej.velocity.z
            ej.velocity = [vX, vY, vZ]
            return
        }
    }

    static func moveObjects(deltaTime: Float, entities: [RigidBody]) {
        for entity in entities where !entity.isStatic {
            entity.setPosition(entity.getPosition() + entity.velocity * deltaTime)
        }
    }
}
