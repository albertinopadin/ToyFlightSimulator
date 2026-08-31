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
    static func resolveCollisions(deltaTime: Float,
                                  collisionPairs: [(RigidBody, RigidBody)],
                                  contactsScratch: inout [Contact]) {
        contactsScratch.removeAll(keepingCapacity: true)
        for (entityA, entityB) in collisionPairs {
            resolvePair(entityA, entityB, contacts: &contactsScratch)
        }
    }

    /// Legacy O(n²) path for `useBroadPhase == false`. Visits each unordered
    /// pair once — the old (j, i) revisit was already suppressed by the
    /// collidedWith guard.
    static func resolveCollisions(deltaTime: Float, entities: [RigidBody], contactsScratch: inout [Contact]) {
        contactsScratch.removeAll(keepingCapacity: true)
        for a in 0..<entities.count {
            for b in (a + 1)..<entities.count {
                resolvePair(entities[a], entities[b], contacts: &contactsScratch)
            }
        }
    }
    
    /// ONE narrow phase per pair (the old flow ran geometry twice — collided()
    /// then getCollisionData()). Bookkeeping order preserved exactly: the
    /// already-collided guard, then narrow phase, then symmetric insertion,
    /// then response. New and inert-by-default: the filtering guard (A.4) and
    /// the per-contact events (nobody registered until A.7).
    private static func resolvePair(_ entityA: RigidBody, _ entityB: RigidBody, contacts: inout [Contact]) {
        guard entityA.shouldCollide(with: entityB), !entityA.collidedWith.contains(ObjectIdentifier(entityB)) else { return }
        
        let firstNew = contacts.count
        guard let deepest = NarrowPhase.generateContacts(entityA, entityB, into: &contacts) else { return }
        
        entityA.collidedWith.insert(ObjectIdentifier(entityB))
        entityB.collidedWith.insert(ObjectIdentifier(entityA))
        
        applyCollisionResponse(entityA, entityB, contact: contacts[deepest])
        
        for contact in contacts[firstNew...] {
            entityA.onContact?(contact, entityB)
            entityB.onContact?(contact.flipped, entityA)
        }
    }

    /// A-ROUTING TRANSCRIPTION — behavior-frozen. This is the pre-routing
    /// response verbatim (rest latch, minDeltaVelo impulse discard, ×2 static
    /// corrections and all), consuming the pair's deepest Contact instead of
    /// re-running geometry through PhysicsWorld.getCollisionData. Where the
    /// strict B→A normal differs from the legacy shape-dependent normal,
    /// `legacyNormal` reconstructs the old value exactly (IEEE negation is
    /// exact — see the plan's sign-symmetry note). Do NOT clean anything up
    /// here: A.6 replaces this body deliberately, against regenerated goldens.
    private static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody, contact: Contact) {
        // Hack (dies in A.6): the one-way rest latch, preserved bit-for-bit.
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

        let penetrationDepth = contact.depth
        let collisionNormal = contact.normal   // unit, strict B → A

        if !entityA.isStatic && !entityB.isStatic {
            // Legacy normal == strict normal in this branch (sphere-sphere was
            // already B→A; dynamic planes don't exist). Verbatim.
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
            // Legacy normal == strict normal here too: with B static, B is
            // the plane (normal toward A) or a static sphere (B→A formula
            // either way). Verbatim, ×2 overshoot included.
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
            // The one convention-divergent branch. The legacy normal here was
            // the static body's OUTWARD normal (the plane's normal, pointing
            // toward B — not B→A); strict B→A is its exact negation, so
            // reconstruct it and keep the body verbatim. For the unreachable
            // static-SPHERE-as-A configuration this silently fixes the legacy
            // inverted position correction (impulse term is bit-identical in
            // both configurations — the sign symmetry note has the algebra).
            let legacyNormal = -collisionNormal
            entityB.setPosition(entityB.getPosition() + legacyNormal * (penetrationDepth * 2))

            let relativeVelo = entityB.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, legacyNormal)
            j /= 1.0 / entityB.mass

            let entityBDeltaVelo = j / entityB.mass * legacyNormal
            entityB.velocity += simd_length_squared(entityBDeltaVelo) > minDeltaVeloSquared ? entityBDeltaVelo : .zero

            return
        }
    }
}
