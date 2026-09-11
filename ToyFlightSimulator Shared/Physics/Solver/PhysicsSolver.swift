//
//  PhysicsSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/31/24.
//

// Solvers operate on concrete [RigidBody] (see PhysicsWorld.entities).
// Entities are classes, so no inout is needed — element mutation goes through
// the reference.
protocol PhysicsSolver {
    static func step(deltaTime: Float, gravity: float3, entities: [RigidBody])
}

extension PhysicsSolver {
    /// End of step: forces and torques are per-substep accumulators.
    public static func zeroForces(entities: [RigidBody]) {
        for entity in entities {
            entity.force = .zero
            entity.torque = .zero
        }
    }
}
