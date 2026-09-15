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
    /// Fixed-capacity per-contact scratch for solveManifold: no allocation
    /// on the step path. Sixteen slots cover any pair the specs produce
    /// (fuselage, wings, empennage against a plane or a structure's one
    /// collider, the capsule contributing two; two compounds give nine).
    private struct ManifoldState {
        static let capacity = 16
        var effectiveMass: SIMD16<Float> = .zero
        var target: SIMD16<Float> = .zero
        var accumulated: SIMD16<Float> = .zero
    }
    
    /// Below this approach speed restitution is 0: the impulse cancels the
    /// normal velocity instead of bouncing, so a resting body is re-supported
    /// every step and gravity stays on. Box2D and Jolt use about 1 m/s.
    private static let restitutionVelocityThreshold: Float = 1.0
    /// Penetration allowed before position correction starts (meters).
    private static let penetrationSlop: Float = 0.005
    /// Fraction of the penetration beyond the slop corrected per step.
    private static let positionCorrectionBeta: Float = 0.2
    
    /// Iterations of the pair solve for a pair with more than one contact.
    /// Eight brings the F-22's two-cap belly rest to rest (four leaves 0.008
    /// rad/s of rocking, one 0.029). A single-contact pair keeps the one
    /// pass: a second pass there is not byte-identical (float32 leaves the
    /// residual approach negative in about four contacts in ten).
    static let manifoldIterations = 8

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
    /// collided, correct position at the deepest contact, solve the pair's
    /// contacts for impulses, then fire onContact for every contact (handlers
    /// see post-response state). Shared with EulerSolver.
    static func resolvePair(_ entityA: RigidBody, _ entityB: RigidBody, contacts: inout [Contact]) {
        guard entityA.shouldCollide(with: entityB), !entityA.collidedWith.contains(ObjectIdentifier(entityB)) else { return }
        
        let firstNew = contacts.count
        guard let deepest = NarrowPhase.generateContacts(entityA, entityB, into: &contacts) else { return }
        
        entityA.collidedWith.insert(ObjectIdentifier(entityB))
        entityB.collidedWith.insert(ObjectIdentifier(entityA))
        
        // Position correction at the deepest contact, then the impulses: the
        // Phase A sequence, in two functions. The inverse masses and inertia
        // tensors are a property of the pair, computed once for both.
        let invMassStats = getInverseMassStats(entityA, entityB)
        correctPosition(entityA, entityB, contact: contacts[deepest], inverseMassStats: invMassStats)
        
        if contacts.count - firstNew == 1 {
            // One contact — every sphere pair, so every golden: the Phase A
            // sequence exactly.
            applyImpulse(entityA, entityB, contact: contacts[deepest], inverseMassStats: invMassStats)
        } else {
            solveManifold(entityA, entityB, contacts: contacts[firstNew...], inverseMassStats: invMassStats)
        }
        
        for contact in contacts[firstNew...] {
            entityA.onContact?(contact, entityB)
            entityB.onContact?(contact.flipped, entityA)
        }
    }
    
    /// A pair's inverse masses and their sum, the split both halves of the
    /// response use, plus each body's inverse inertia in world axes for the
    /// impulse's lever-arm terms. A static body has inverse mass 0 and the
    /// infinite-inertia tensor, so it neither moves nor changes velocity; a
    /// zero sum (two statics) means nothing to do.
    typealias InverseMassStats = (inverseMassA: Float,
                                  inverseMassB: Float,
                                  inverseMassSum: Float,
                                  inverseInertiaA: float3x3,
                                  inverseInertiaB: float3x3)
    
    /// Computed once per pair in resolvePair rather than in each half:
    /// solveManifold iterates over a pair's contacts, and neither the masses
    /// nor the tensors change between iterations (inverseInertiaWorld()
    /// rebuilds R · I⁻¹ · Rᵀ from the pose on every call).
    static func getInverseMassStats(_ entityA: RigidBody, _ entityB: RigidBody) -> InverseMassStats {
        let invMassA: Float = entityA.isStatic ? 0 : 1 / entityA.mass
        let invMassB: Float = entityB.isStatic ? 0 : 1 / entityB.mass
        let invMassSum = invMassA + invMassB
        // Effective mass along n at the point: the inverse-mass sum plus each
        // body's angular term ((I⁻¹ (r × n)) × r) · n — how much of a unit
        // impulse at the point goes into spinning the body rather than
        // pushing it. A static body contributes nothing on either count.
        let invInertiaA = entityA.isStatic ? RigidBody.infiniteInertia : entityA.inverseInertiaWorld()
        let invInertiaB = entityB.isStatic ? RigidBody.infiniteInertia : entityB.inverseInertiaWorld()
        return (invMassA, invMassB, invMassSum, invInertiaA, invInertiaB)
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
        
        // Effective mass along n at the point: the inverse-mass sum plus the
        // angular terms (getInverseMassStats explains them).
        let angularA = dot(cross(inverseMassStats.inverseInertiaA * cross(rA, n), rA), n)
        let angularB = dot(cross(inverseMassStats.inverseInertiaB * cross(rB, n), rB), n)
        let j = -(1 + e) * approach / (inverseMassStats.inverseMassSum + angularA + angularB)
        
        // Linear change j/m along n; angular change I⁻¹ (r × j n). B takes
        // the opposite signs because n points toward A.
        if !entityA.isStatic {
            entityA.velocity += n * (j * inverseMassStats.inverseMassA)
            entityA.angularVelocity += inverseMassStats.inverseInertiaA * cross(rA, n * j)
        }
        
        if !entityB.isStatic {
            entityB.velocity -= n * (j * inverseMassStats.inverseMassB)
            entityB.angularVelocity -= inverseMassStats.inverseInertiaB * cross(rB, n * j)
        }
    }
    
    /// Sequential impulses over one pair's contacts (Catto, GDC 2006): each
    /// contact's accumulated impulse is clamped non-negative, so an early
    /// contact can give back what a later one made unnecessary, and the
    /// restitution target is captured from the pre-solve velocities. With
    /// the F-22's pitch inertia the lever arms dominate the effective mass,
    /// so one pass over two caps leaves the first approaching again at about
    /// the speed it arrived; eight passes converge. Position correction
    /// stays linear at the deepest contact (D.4 for the angular share).
    static func solveManifold(_ entityA: RigidBody,
                              _ entityB: RigidBody,
                              contacts: ArraySlice<Contact>,
                              inverseMassStats: InverseMassStats) {
        assert(contacts.count <= ManifoldState.capacity, "more contacts in one pair than the specs can produce")
        guard inverseMassStats.inverseMassSum > 0 else { return }
        let positionA = entityA.getPosition()
        let positionB = entityB.getPosition()
        
        var state = ManifoldState()
        for (slot, contact) in contacts.enumerated() {
            let n = contact.normal
            let rA = contact.point - positionA
            let rB = contact.point - positionB
            let approach = dot(entityA.velocity(atWorldPoint: contact.point) - entityB.velocity(atWorldPoint: contact.point), n)
            let e = -approach > restitutionVelocityThreshold ? min(entityA.restitution, entityB.restitution) : 0
            let angularA = dot(cross(inverseMassStats.inverseInertiaA * cross(rA, n), rA), n)
            let angularB = dot(cross(inverseMassStats.inverseInertiaB * cross(rB, n), rB), n)
            state.effectiveMass[slot] = 1 / (inverseMassStats.inverseMassSum + angularA + angularB)
            // Target normal velocity: −e × the incoming approach (0 below the
            // threshold), the same bounce the single impulse produces.
            state.target[slot] = approach < 0 ? -e * approach : 0
        }
        
        for _ in 0..<manifoldIterations {
            for (slot, contact) in contacts.enumerated() {
                let n = contact.normal
                let rA = contact.point - positionA
                let rB = contact.point - positionB
                let relative = dot(entityA.velocity(atWorldPoint: contact.point) - entityB.velocity(atWorldPoint: contact.point), n)
                let wanted = (state.target[slot] - relative) * state.effectiveMass[slot]
                let previous = state.accumulated[slot]
                state.accumulated[slot] = max(0, previous + wanted)
                let j = state.accumulated[slot] - previous
                guard j != 0 else { continue }
                if !entityA.isStatic {
                    entityA.velocity += n * (j * inverseMassStats.inverseMassA)
                    entityA.angularVelocity += inverseMassStats.inverseInertiaA * cross(rA, n * j)
                }
                
                if !entityB.isStatic {
                    entityB.velocity -= n * (j * inverseMassStats.inverseMassB)
                    entityB.angularVelocity -= inverseMassStats.inverseInertiaB * cross(rB, n * j)
                }
            }
        }
    }
}
