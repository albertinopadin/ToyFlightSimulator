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
    /// collided, respond at the deepest contact, then fire onContact for every
    /// contact (handlers see post-response state). Shared with EulerSolver.
    /// D.3 replaces the single impulse with a solve over the pair's contacts.
    static func resolvePair(_ entityA: RigidBody, _ entityB: RigidBody, contacts: inout [Contact]) {
        guard entityA.shouldCollide(with: entityB), !entityA.collidedWith.contains(ObjectIdentifier(entityB)) else { return }
        
        let firstNew = contacts.count
        guard let deepest = NarrowPhase.generateContacts(entityA, entityB, into: &contacts) else { return }
        
        entityA.collidedWith.insert(ObjectIdentifier(entityB))
        entityB.collidedWith.insert(ObjectIdentifier(entityA))
        
        // Position, then impulse, at the deepest contact: the Phase A
        // sequence, now in two functions so D.3 can iterate the impulse. The
        // inverse masses are a property of the pair, computed once for both.
        let invMassStats = getInverseMassStats(entityA, entityB)
        correctPosition(entityA, entityB, contact: contacts[deepest], inverseMassStats: invMassStats)
        applyImpulse(entityA, entityB, contact: contacts[deepest], inverseMassStats: invMassStats)
        
        for contact in contacts[firstNew...] {
            entityA.onContact?(contact, entityB)
            entityB.onContact?(contact.flipped, entityA)
        }
    }
    
    /// A pair's inverse masses and their sum: the split both halves of the
    /// response use. A static body has inverse mass 0, so it neither moves
    /// nor changes velocity; a zero sum (two statics) means nothing to do.
    typealias InverseMassStats = (inverseMassA: Float, inverseMassB: Float, inverseMassSum: Float)
    
    /// Computed once per pair in resolvePair rather than in each half: D.3
    /// iterates applyImpulse over a pair's contacts, and the masses do not
    /// change between iterations.
    static func getInverseMassStats(_ entityA: RigidBody, _ entityB: RigidBody) -> InverseMassStats {
        let invMassA: Float = entityA.isStatic ? 0 : 1 / entityA.mass
        let invMassB: Float = entityB.isStatic ? 0 : 1 / entityB.mass
        let invMassSum = invMassA + invMassB
        return (invMassA, invMassB, invMassSum)
    }
    
    /// Moves the bodies apart along the normal by β × (depth − slop), split by
    /// inverse mass: only the penetration beyond the slop, and only a
    /// β-fraction of it per step. Linear only: the angular share of position
    /// correction belongs to a manifold solver (D.4), if one is ever built.
    static func correctPosition(_ entityA: RigidBody,
                                _ entityB: RigidBody,
                                contact: Contact,
                                inverseMassStats: InverseMassStats) {
        let n = contact.normal                       // unit, from B toward A
        guard inverseMassStats.inverseMassSum > 0 else { return }         // two statics: nothing to move

        let correction = positionCorrectionBeta * max(0, contact.depth - penetrationSlop) / inverseMassStats.inverseMassSum
        guard correction > 0 else { return }
        if !entityA.isStatic {
            entityA.setPosition(entityA.getPosition() + n * (correction * inverseMassStats.inverseMassA))
        }
        if !entityB.isStatic {
            entityB.setPosition(entityB.getPosition() - n * (correction * inverseMassStats.inverseMassB))
        }
    }
    
    /// Normal impulse at the contact point, Hecker's full form: the relative
    /// velocity and the effective mass include the lever arms r = point −
    /// origin through each body's world inverse inertia. A pair with no
    /// finite inertia on either side takes the linear path first: the Phase A
    /// block verbatim, so its arithmetic is unchanged by construction. (The
    /// general form's angular terms are exactly zero for such a pair too, but
    /// the fast path skips two position reads, eight cross products, and four
    /// matrix products per sphere contact, and makes the golden argument a
    /// reading exercise.) Symmetric in inverse mass: a static body neither
    /// moves nor changes velocity. In the general path the lever arms are
    /// measured from the post-correction origins; the difference is the
    /// β-fraction of a penetration, millimeters.
    static func applyImpulse(_ entityA: RigidBody,
                             _ entityB: RigidBody,
                             contact: Contact,
                             inverseMassStats: InverseMassStats) {
        let n = contact.normal                       // unit, from B toward A
        guard inverseMassStats.inverseMassSum > 0 else { return }
        
        guard entityA.hasFiniteInertia || entityB.hasFiniteInertia else {
            // Linear fast path: every body before D.3, every ball after it.
            // Impulse only when approaching (n points toward A, so approaching
            // means relative velocity along −n); separating contacts are skipped.
            let relativeVelocity = entityA.velocity - entityB.velocity
            let approach = dot(relativeVelocity, n)
            guard approach < 0 else { return }

            // Restitution only above the threshold; below it e = 0, so the
            // normal velocity is cancelled exactly (the support impulse).
            let e = -approach > restitutionVelocityThreshold ? min(entityA.restitution, entityB.restitution) : 0

            // Always applied: at rest this is the per-step support impulse
            // (about m·g·dt), the normal force integrated over the step.
            let j = -(1 + e) * approach / inverseMassStats.inverseMassSum
            if !entityA.isStatic {
                entityA.velocity += n * (j * inverseMassStats.inverseMassA)
            }
            if !entityB.isStatic {
                entityB.velocity -= n * (j * inverseMassStats.inverseMassB)
            }
            
            return
        }
        
        // Lever arms from each origin to the contact point. Impulse only when
        // approaching AT THE POINT: each body's velocity there is v + ω × r,
        // so a body spinning into the contact counts even if its origin is
        // still (n points toward A, so approaching means along −n).
        let rA = contact.point - entityA.getPosition()
        let rB = contact.point - entityB.getPosition()
        let approach = dot(entityA.velocity(atWorldPoint: contact.point) - entityB.velocity(atWorldPoint: contact.point), n)
        guard approach < 0 else { return }
        
        // Restitution only above the threshold; below it e = 0 and the normal
        // velocity at the point is cancelled exactly (the support impulse).
        let e = -approach > restitutionVelocityThreshold ? min(entityA.restitution, entityB.restitution) : 0
        
        // Effective mass along n at the point: the inverse-mass sum plus each
        // body's angular term ((I⁻¹ (r × n)) × r) · n — how much of a unit
        // impulse at the point goes into spinning the body rather than
        // pushing it. A static body contributes nothing on either count.
        let invInertiaA = entityA.isStatic ? RigidBody.infiniteInertia : entityA.inverseInertiaWorld()
        let invInertiaB = entityB.isStatic ? RigidBody.infiniteInertia : entityB.inverseInertiaWorld()
        
        let angularA = dot(cross(invInertiaA * cross(rA, n), rA), n)
        let angularB = dot(cross(invInertiaB * cross(rB, n), rB), n)
        let j = -(1 + e) * approach / (inverseMassStats.inverseMassSum + angularA + angularB)
        
        // Linear change j/m along n; angular change I⁻¹ (r × j n). B takes
        // the opposite signs because n points toward A.
        if !entityA.isStatic {
            entityA.velocity += n * (j * inverseMassStats.inverseMassA)
            entityA.angularVelocity += invInertiaA * cross(rA, n * j)
        }
        
        if !entityB.isStatic {
            entityB.velocity -= n * (j * inverseMassStats.inverseMassB)
            entityB.angularVelocity -= invInertiaB * cross(rB, n * j)
        }
    }
}
