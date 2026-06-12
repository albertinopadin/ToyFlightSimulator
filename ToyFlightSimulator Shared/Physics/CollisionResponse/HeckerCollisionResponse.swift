//
//  HeckerCollisionResponse.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

// From https://www.chrishecker.com/images/e/e7/Gdmphys3.pdf
// and: https://www.youtube.com/watch?v=vQO_hPOE-1Y

import simd

final class HeckerCollisionResponse {
    /// Below this relative speed a contact is treated as resting (squared — no sqrt).
    private static let restSpeedThresholdSquared: Float = 0.55 * 0.55
    /// Impulse delta-v below this squared magnitude is discarded (1.0² == 1.0).
    private static let minDeltaVeloSquared: Float = 1.0

    /// Broad-phase pair path. P7: the per-call [String: Int] index map is gone —
    /// entities are classes, so the response mutates them through the references.
    static func resolveCollisions(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
        for (entityA, entityB) in collisionPairs {
            let alreadyCollided = entityA.collidedWith.contains(ObjectIdentifier(entityB))

            // Perform narrow-phase collision detection
            if !alreadyCollided && PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
                entityA.collidedWith.insert(ObjectIdentifier(entityB))
                entityB.collidedWith.insert(ObjectIdentifier(entityA))

                applyCollisionResponse(entityA, entityB)
            }
        }
    }

    /// Legacy O(n²) path for `useBroadPhase == false`. Visits each unordered
    /// pair once — the old (j, i) revisit was already suppressed by the
    /// collidedWith guard.
    static func resolveCollisions(deltaTime: Float, entities: [RigidBody]) {
        for a in 0..<entities.count {
            for b in (a + 1)..<entities.count {
                let entityA = entities[a]
                let entityB = entities[b]

                let alreadyCollided = entityA.collidedWith.contains(ObjectIdentifier(entityB))

                if !alreadyCollided && PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
                    entityA.collidedWith.insert(ObjectIdentifier(entityB))
                    entityB.collidedWith.insert(ObjectIdentifier(entityA))

                    applyCollisionResponse(entityA, entityB)
                }
            }
        }
    }

    // Helper method to apply collision response
    private static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody) {
        // Hack:
        // TODO: This will fail if the static entity is not directly below the non-static
        //       entity. Need to figure out a better way...
        // TODO: My units seem to be messed up, 'small' collisions seem to be ~ 0.7 m/s
        if simd_length_squared(entityA.velocity - entityB.velocity) < restSpeedThresholdSquared {
            if entityB.isStatic {
                entityA.velocity = .zero
                entityA.acceleration = .zero
                entityA.shouldApplyGravity = false

                print("[HeckerCollisionResponse resolveCollisions] Gravity should not apply to entity: \(ObjectIdentifier(entityA))")
            }

            if entityA.isStatic {
                entityB.velocity = .zero
                entityB.acceleration = .zero
                entityB.shouldApplyGravity = false

                print("[HeckerCollisionResponse resolveCollisions] Gravity should not apply to entity: \(ObjectIdentifier(entityB))")
            }

            return
        }

        let collisionData = PhysicsWorld.getCollisionData(entityA, entityB)
        let penetrationDepth = collisionData.penetrationDepth
        // collisionVector is already unit-length (getCollisionData normalizes
        // every branch; PlaneRigidBody normalizes at init) — the old second
        // normalize() here was a redundant sqrt.
        let collisionNormal = collisionData.collisionVector

        if !entityA.isStatic && !entityB.isStatic {
            entityA.setPosition(entityA.getPosition() + collisionNormal * (penetrationDepth / 2))
            entityB.setPosition(entityB.getPosition() - collisionNormal * (penetrationDepth / 2))

            let relativeVelo = entityA.velocity - entityB.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
            j /= ((1.0 / entityA.mass) + (1.0 / entityB.mass))

            let entityADeltaVelo = j / entityA.mass * collisionNormal
            let entityBDeltaVelo = j / entityB.mass * collisionNormal

            entityA.velocity += simd_length_squared(entityADeltaVelo) > minDeltaVeloSquared ? entityADeltaVelo : .zero
            entityB.velocity -= simd_length_squared(entityBDeltaVelo) > minDeltaVeloSquared ? entityBDeltaVelo : .zero

            return
        }

        if !entityA.isStatic && entityB.isStatic {
            entityA.setPosition(entityA.getPosition() + collisionNormal * (penetrationDepth * 2))

            let relativeVelo = entityA.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
            j /= 1.0 / entityA.mass

            let entityADeltaVelo = j / entityA.mass * collisionNormal
            entityA.velocity += simd_length_squared(entityADeltaVelo) > minDeltaVeloSquared ? entityADeltaVelo : .zero

            return
        }

        if entityA.isStatic && !entityB.isStatic {
            entityB.setPosition(entityB.getPosition() + collisionNormal * (penetrationDepth * 2))

            let relativeVelo = entityB.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
            j /= 1.0 / entityB.mass

            let entityBDeltaVelo = j / entityB.mass * collisionNormal
            entityB.velocity += simd_length_squared(entityBDeltaVelo) > minDeltaVeloSquared ? entityBDeltaVelo : .zero

            return
        }
    }
}
