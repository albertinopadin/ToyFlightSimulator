//
//  PhysicsSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/31/24.
//

protocol PhysicsSolver {
    static func step(deltaTime: Float, gravity: float3, entities: inout [PhysicsEntity])
}

extension PhysicsSolver {
    public static func zeroForces(entities: inout [PhysicsEntity]) {
        for i in 0..<entities.count {
            entities[i].zeroForce()
        }
    }
}
