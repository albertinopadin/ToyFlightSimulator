//
//  PhysicsEntity.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/31/24.
//

import Foundation


protocol PhysicsEntity {
    var id: String { get }
    
    var mass: Float { get set }
    var velocity: float3 { get set }
    var acceleration: float3 { get set }
    var radius: Float { get set }
    var restitution: Float { get set }
    var isStatic: Bool { get set }
    
    func setPosition(_ position: float3)
    func getPosition() -> float3
}

extension PhysicsEntity {
    var id: String { UUID().uuidString }
    
    static func ==(lhs: PhysicsEntity, rhs: PhysicsEntity) -> Bool {
        return lhs.id == rhs.id
    }
}
