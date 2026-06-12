//
//  VerletSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

final class VerletSolver: PhysicsSolver {
    static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        for entity in entities {
            // P8: zeroAcceleration() was a separate full pass over all entities;
            // merged here. Static entities still get their acceleration cleared,
            // exactly as the old pre-pass did.
            entity.acceleration = .zero
            guard !entity.isStatic else { continue }

            let pos = entity.getPosition()
            let velo = entity.velocity
            // NOTE: acceleration was just zeroed above, so the 0.5·a·dt² and
            // 0.5·a·dt history terms below are always zero. That matches the
            // pre-existing behavior (the old code zeroed all accelerations
            // before reading them); true velocity-Verlet would carry last
            // frame's acceleration into these terms. Kept bit-identical on
            // purpose — integration fidelity is a separate physics follow-up.
            let acc: float3 = .zero

            let nPosEuler: float3 = pos + velo * deltaTime
            let nPos: float3 = nPosEuler + 0.5 * acc * (deltaTime * deltaTime)

            let veloDtHalf = velo + 0.5 * acc * deltaTime

            var newAcc = acc

            if entity.shouldApplyGravity {
                newAcc += Self.applyForces(gravity: gravity, force: entity.force)
            } else {
                newAcc += Self.applyForces(gravity: .zero, force: entity.force)
            }

            let nVelo = veloDtHalf + 0.5 * newAcc * deltaTime

            entity.setPosition(nPos)
            entity.velocity = nVelo
            entity.acceleration = newAcc
        }

        zeroForces(entities: entities)
    }

    static func applyForces(gravity: float3, force: float3 = .zero) -> float3 {
        return gravity + force
    }
}
