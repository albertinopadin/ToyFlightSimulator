//
//  FlightModel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/17/26.
//

protocol FlightModel {
    var mass: Float { get }
    
    // TODO: This just computes the force at the rigid body center, need to implement torque at later time:
    func computeForce(state: RigidBody.State, input: ControlInput) -> float3
}
