//
//  PhysicsSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/31/24.
//

protocol PhysicsSolver {
    static func step(deltaTime: Float, gravity: float3, entities: inout [PhysicsEntity])
}
