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
/// velocity, i.e. effective g/2 free-fall). Bodies start with acceleration
/// .zero, so the first step self-bootstraps with a half-kick.
final class VerletSolver: PhysicsSolver {
    static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        for entity in entities {
            guard !entity.isStatic else {
                // Static bodies never integrate; keep their stored
                // acceleration at zero (parity with the old per-step zeroing).
                entity.acceleration = .zero
                continue
            }

            let pos = entity.getPosition()
            let velo = entity.velocity
            // a(t): last step's acceleration, carried in entity.acceleration.
            let acc = entity.acceleration

            let nPos: float3 = pos + velo * deltaTime + 0.5 * acc * (deltaTime * deltaTime)

            let veloDtHalf = velo + 0.5 * acc * deltaTime

            // a(t+dt) from forces at the new state. Mass divides the applied
            // force (a = F/m + g), matching EulerSolver — the previous
            // `gravity + force` form silently treated force as an acceleration.
            let appliedGravity: float3 = entity.shouldApplyGravity ? gravity : .zero
            let newAcc: float3 = entity.force / entity.mass + appliedGravity

            let nVelo = veloDtHalf + 0.5 * newAcc * deltaTime

            entity.setPosition(nPos)
            entity.velocity = nVelo
            entity.acceleration = newAcc
        }

        zeroForces(entities: entities)
    }
}
