//
//  VerletSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

/// Velocity Verlet integrator:
///   x(t+dt) = x(t) + v(t)·dt + ½·a(t)·dt²
///   v(t+dt) = v(t) + ½·(a(t) + a(t+dt))·dt
/// `entity.acceleration` carries a(t) across steps (it is NOT zeroed at the
/// top of the step — an earlier implementation did, which dropped the
/// ½·a·dt² curvature term and applied only half of each step's gravity to
/// velocity, i.e. effective g/2 free-fall). A body's first step has no
/// carried a(t), so it is seeded from that step's forces
/// (`accelerationIsWarm`); integrating from .zero instead ran every
/// trajectory exactly dt/2 late (found at the B.3 regeneration).
final class VerletSolver: PhysicsSolver {
    static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        for entity in entities {
            guard !entity.isStatic else {
                // Static bodies never integrate; keep their stored
                // acceleration at zero (parity with the old per-step zeroing)
                // and cold, so a body that later turns dynamic is seeded.
                entity.acceleration = .zero
                entity.accelerationIsWarm = false
                continue
            }

            // a(t+dt) from the forces on the body, written at the top of the
            // step from the state at t (the solver treats them as a(t+dt): a
            // one-substep lag, accepted in B.2). Mass divides the applied
            // force (a = F/m + g), matching EulerSolver.
            let appliedGravity: float3 = entity.shouldApplyGravity ? gravity : .zero
            let newAcc: float3 = entity.force / entity.mass + appliedGravity

            let pos = entity.getPosition()
            let velo = entity.velocity
            // a(t): last step's acceleration, carried in entity.acceleration.
            // On the body's first step there is none, so this step's is used.
            let acc: float3 = entity.accelerationIsWarm ? entity.acceleration : newAcc

            let nPos: float3 = pos + velo * deltaTime + 0.5 * acc * (deltaTime * deltaTime)

            let veloDtHalf = velo + 0.5 * acc * deltaTime

            let nVelo = veloDtHalf + 0.5 * newAcc * deltaTime

            entity.setPosition(nPos)
            entity.velocity = nVelo
            entity.acceleration = newAcc
            entity.accelerationIsWarm = true
        }

        zeroForces(entities: entities)
    }
}
