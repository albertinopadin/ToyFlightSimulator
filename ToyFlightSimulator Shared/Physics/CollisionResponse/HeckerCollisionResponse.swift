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
    /// Below this normal approach speed, restitution is 0: the impulse solves
    /// the normal velocity to exactly zero instead of bouncing, so resting is
    /// an equilibrium re-established every step — gravity stays ON. (Box2D's
    /// b2_velocityThreshold and Jolt's restitution threshold are both ≈ 1 m/s.)
    private static let restitutionVelocityThreshold: Float = 1.0
    /// Penetration allowed before position correction engages (meters). The
    /// slop keeps persistent contacts measurably touching instead of
    /// oscillating across the surface.
    private static let penetrationSlop: Float = 0.005
    /// Fraction of (depth − slop) corrected per step (Baumgarte-style); damps
    /// correction-induced energy. Replaces the legacy full-depth teleports
    /// and the ×2 static-branch overshoot.
    private static let positionCorrectionBeta: Float = 0.2

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
    /// then response, then the per-contact events (first consumers: A.7's
    /// ContactDebugLogger on the player aircraft, and CompoundBodyTests).
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

    /// Corrected linear contact response (research §3.2; combined doc A5) —
    /// the A-response commit's deliberate behavior change, regoldened. Both
    /// legacy hacks (the one-way rest latch and the minDeltaVelo impulse
    /// discard) are gone: resting is a per-step equilibrium instead of frozen
    /// state, and shouldApplyGravity is never written here. Consumes the
    /// pair's deepest contact; symmetric in inverse mass, so the
    /// static/dynamic branching of the legacy code collapses (a static body
    /// has infinite mass ⇒ inverse mass 0 ⇒ it neither moves nor changes
    /// velocity). deltaTime-independent by design until Phase B's fixed step
    /// (β is per-step, matching the legacy correction's shape). `internal`:
    /// EulerSolver shares it.
    internal static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody, contact: Contact) {
        let n = contact.normal                       // unit, strict B → A
        let invMassA: Float = entityA.isStatic ? 0 : 1 / entityA.mass
        let invMassB: Float = entityB.isStatic ? 0 : 1 / entityB.mass
        let invMassSum = invMassA + invMassB
        guard invMassSum > 0 else { return }         // two statics: nothing to move

        // 1) Position correction with slop, split by inverse mass. Corrects
        //    only the penetration BEYOND the slop, and only a β-fraction of
        //    it per step.
        let correction = positionCorrectionBeta * max(0, contact.depth - penetrationSlop) / invMassSum
        if correction > 0 {
            if !entityA.isStatic {
                entityA.setPosition(entityA.getPosition() + n * (correction * invMassA))
            }
            if !entityB.isStatic {
                entityB.setPosition(entityB.getPosition() - n * (correction * invMassB))
            }
        }

        // 2) Impulse only when approaching (n points toward A, so approaching
        //    means relative velocity along −n). The legacy response applied
        //    impulses to separating contacts too, which can add energy.
        let relativeVelocity = entityA.velocity - entityB.velocity
        let approach = dot(relativeVelocity, n)
        guard approach < 0 else { return }

        // 3) Restitution only above the threshold; below it e = 0 ⇒ the
        //    normal velocity is solved to exactly zero (the support impulse).
        let e = -approach > restitutionVelocityThreshold ? min(entityA.restitution, entityB.restitution) : 0

        // 4) ALWAYS applied — the deleted minDeltaVelo discard threw away the
        //    per-step support impulse (≈ m·g·dt) that resting requires; that
        //    impulse IS the normal force integrated over the step.
        let j = -(1 + e) * approach / invMassSum
        if !entityA.isStatic {
            entityA.velocity += n * (j * invMassA)
        }
        if !entityB.isStatic {
            entityB.velocity -= n * (j * invMassB)
        }
    }
}
