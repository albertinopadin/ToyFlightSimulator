//
//  EulerSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

import simd

final class EulerSolver: PhysicsSolver {
    /// Below this relative speed, colliding bodies are parked (anti-jitter hack).
    /// LEGACY — read only by applyLegacyEulerResponse below; the live response
    /// (HeckerCollisionResponse.applyCollisionResponse) replaced it with the
    /// restitution velocity threshold in the A-response commit.
    private static let restSpeedThresholdSquared: Float = 0.55 * 0.55
    
    /// PhysicsSolver conformance — allocates a local scratch. Kept for the
    /// protocol and for direct test calls; PhysicsWorld always passes its own
    /// scratch via the overloads below, so no hot path allocates.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        var contacts: [Contact] = []
        step(deltaTime: deltaTime, gravity: gravity, entities: entities, contactsScratch: &contacts)
    }

    /// Legacy O(n²) step — kept as the `useBroadPhase == false` comparison baseline.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody], contactsScratch: inout [Contact]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        contactsScratch.removeAll(keepingCapacity: true)
        resolveCollisionsAllPairs(entities: entities, contacts: &contactsScratch)
        moveObjects(deltaTime: deltaTime, entities: entities)
        zeroForces(entities: entities)
    }

    /// P1: broad-phase-driven step. Same force/move/zero phases; collision
    /// resolution only inspects the candidate pairs.
    public static func step(deltaTime: Float,
                            gravity: float3,
                            entities: [RigidBody],
                            collisionPairs: [(RigidBody, RigidBody)],
                            contactsScratch: inout [Contact]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        contactsScratch.removeAll(keepingCapacity: true)
        for (ei, ej) in collisionPairs {
            resolvePair(ei, ej, contacts: &contactsScratch)
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
    static func resolveCollisionsAllPairs(entities: [RigidBody], contacts: inout [Contact]) {
        for i in 0..<entities.count {
            for j in (i + 1)..<entities.count {
                resolvePair(entities[i], entities[j], contacts: &contacts)
            }
        }
    }

    /// Narrow phase + response for one candidate pair — same routing shape as
    /// HeckerCollisionResponse.resolvePair (guard order preserved exactly).
    /// Since the A-response commit both solvers share the corrected
    /// applyCollisionResponse: the per-axis reflection was an axis-aligned-
    /// plane special case the response-semantics invariants can't hold under
    /// (single_bounce_euler's regolden pins the divergence).
    private static func resolvePair(_ ei: RigidBody, _ ej: RigidBody, contacts: inout [Contact]) {
        guard ei.shouldCollide(with: ej),
              !ei.collidedWith.contains(ObjectIdentifier(ej)) else { return }
        
        let firstNew = contacts.count
        guard let deepest = NarrowPhase.generateContacts(ei, ej, into: &contacts) else { return }

        ei.collidedWith.insert(ObjectIdentifier(ej))
        ej.collidedWith.insert(ObjectIdentifier(ei))
        
        HeckerCollisionResponse.applyCollisionResponse(ei, ej, contact: contacts[deepest])
        
        for contact in contacts[firstNew...] {
            ei.onContact?(contact, ej)
            ej.onContact?(contact.flipped, ei)
        }
    }
    
    /// LEGACY — UNREFERENCED since the A-response commit, kept deliberately as
    /// reference code (project-owner decision; the plan's A.6 File 2 said to
    /// delete it). This is the faithful A-routing transcription of the
    /// original Euler response — per-axis velocity reflection plus the
    /// zero-both-velocities rest hack — preserved so the pre-Phase-A behavior
    /// stays readable next to its replacement. Nothing may call it: the
    /// response-semantics suite (CollisionResponseTests.eulerPathRests) and
    /// the regoldened single_bounce_euler baseline both pin the shared
    /// corrected response as the live path. Delete freely once it stops
    /// earning its keep as documentation.
    private static func applyLegacyEulerResponse(_ ei: RigidBody, _ ej: RigidBody, contact: Contact) {
        let collisionVector = contact.normal      // unit, strict B → A
        let restitution = min(ei.restitution, ej.restitution)
        let unormCollisionVector = contact.normal * contact.depth

        // Hack to prevent infinite bouncing (zeroes BOTH bodies, no static
        // gate — preserved exactly as transcribed in A-routing; squared
        // compare — was .magnitude < 0.55):
        if simd_length_squared(ei.velocity - ej.velocity) < restSpeedThresholdSquared {
            ei.velocity = .zero
            ej.velocity = .zero
            return
        }

        if !ei.isStatic && !ej.isStatic {
            // Legacy normal == strict normal in this branch. Verbatim.
            ei.setPosition(ei.getPosition() + unormCollisionVector)
            ei.velocity = (ei.velocity + collisionVector) * restitution

            ej.setPosition(ej.getPosition() - unormCollisionVector)
            ej.velocity = (ej.velocity - collisionVector) * restitution
            return
        }

        if !ei.isStatic && ej.isStatic {
            // Legacy normal == strict normal here. Verbatim, ×2 included.
            ei.setPosition(ei.getPosition() + unormCollisionVector * 2)
            let vX = collisionVector.x != 0 ? ei.velocity.x * -collisionVector.x * restitution : ei.velocity.x
            let vY = collisionVector.y != 0 ? ei.velocity.y * -collisionVector.y * restitution : ei.velocity.y
            let vZ = collisionVector.z != 0 ? ei.velocity.z * -collisionVector.z * restitution : ei.velocity.z
            ei.velocity = [vX, vY, vZ]
            return
        }

        if ei.isStatic && !ej.isStatic {
            // Convention-divergent branch: reconstruct the legacy
            // static-outward normal (exact negation), then verbatim.
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

    static func moveObjects(deltaTime: Float, entities: [RigidBody]) {
        for entity in entities where !entity.isStatic {
            entity.setPosition(entity.getPosition() + entity.velocity * deltaTime)
        }
    }
}
