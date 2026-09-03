//
//  HeckerCollisionResponse.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

// From https://www.chrishecker.com/images/e/e7/Gdmphys3.pdf
// and: https://www.youtube.com/watch?v=vQO_hPOE-1Y

import simd

enum HeckerCollisionResponse {
    /// Below this approach speed restitution is 0: the impulse cancels the
    /// normal velocity instead of bouncing, so a resting body is re-supported
    /// every step and gravity stays on. Box2D and Jolt use about 1 m/s.
    private static let restitutionVelocityThreshold: Float = 1.0
    /// Penetration allowed before position correction starts (meters).
    private static let penetrationSlop: Float = 0.005
    /// Fraction of the penetration beyond the slop corrected per step.
    private static let positionCorrectionBeta: Float = 0.2

    /// Resolves every candidate pair. `contactsScratch` is cleared and
    /// refilled; it is reused scratch, not storage.
    static func resolveCollisions(collisionPairs: [(RigidBody, RigidBody)],
                                  contactsScratch: inout [Contact]) {
        contactsScratch.removeAll(keepingCapacity: true)
        for (entityA, entityB) in collisionPairs {
            resolvePair(entityA, entityB, contacts: &contactsScratch)
        }
    }

    /// One narrow phase per pair: filter, generate contacts, mark the pair as
    /// collided, respond to the deepest contact, then fire onContact for every
    /// contact (handlers see post-response state). Shared with EulerSolver.
    static func resolvePair(_ entityA: RigidBody, _ entityB: RigidBody, contacts: inout [Contact]) {
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

    /// Linear contact response for the deepest contact of a pair: position
    /// correction with slop and β, then an impulse with restitution above a
    /// speed threshold. Symmetric in inverse mass, so a static body (inverse
    /// mass 0) neither moves nor changes velocity. Shared by both solvers.
    static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody, contact: Contact) {
        let n = contact.normal                       // unit, from B toward A
        let invMassA: Float = entityA.isStatic ? 0 : 1 / entityA.mass
        let invMassB: Float = entityB.isStatic ? 0 : 1 / entityB.mass
        let invMassSum = invMassA + invMassB
        guard invMassSum > 0 else { return }         // two statics: nothing to move

        // 1) Position correction with slop, split by inverse mass: only the
        //    penetration beyond the slop, and only a β-fraction of it per step.
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
        //    means relative velocity along −n). Separating contacts are skipped.
        let relativeVelocity = entityA.velocity - entityB.velocity
        let approach = dot(relativeVelocity, n)
        guard approach < 0 else { return }

        // 3) Restitution only above the threshold; below it e = 0, so the
        //    normal velocity is cancelled exactly (the support impulse).
        let e = -approach > restitutionVelocityThreshold ? min(entityA.restitution, entityB.restitution) : 0

        // 4) Always applied: at rest this is the per-step support impulse
        //    (about m·g·dt), the normal force integrated over the step.
        let j = -(1 + e) * approach / invMassSum
        if !entityA.isStatic {
            entityA.velocity += n * (j * invMassA)
        }
        if !entityB.isStatic {
            entityB.velocity -= n * (j * invMassB)
        }
    }
}
