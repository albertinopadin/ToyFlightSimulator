//
//  VerletSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

final class VerletSolver: PhysicsSolver {
    static func step(deltaTime: Float, gravity: float3, entities: inout [any PhysicsEntity]) {
        zeroAcceleration(entities: &entities)
        
        for i in 0..<entities.count {
            let pos = entities[i].getPosition()
            let velo = entities[i].velocity
            let acc = entities[i].acceleration
            
            let nPosEuler: float3 = pos + velo * deltaTime
            let nPos: float3 = nPosEuler + 0.5 * acc * (deltaTime * deltaTime)
            
            let veloDtHalf = velo + 0.5 * acc * deltaTime
            
            let newAcc = acc + Self.applyForces(gravity: gravity)
            
            let nVelo = veloDtHalf + 0.5 * newAcc * deltaTime
            
            entities[i].setPosition(nPos)
            entities[i].velocity = nVelo
            entities[i].acceleration = newAcc
        }
        
        checkEntitiesHitFloor(entities: &entities)
    }
    
    static func zeroAcceleration(entities: inout [any PhysicsEntity]) {
        for i in 0..<entities.count {
            entities[i].acceleration = .zero
        }
    }
    
    static func applyForces(gravity: float3, force: float3 = .zero) -> float3 {
        return gravity + force
    }
    
    // TODO: Remove this once floor is properly modeled in physics
    static func checkEntitiesHitFloor(entities: inout [any PhysicsEntity]) {
        for i in 0..<entities.count {
            let entityPos = entities[i].getPosition()
            let entityRadius = entities[i].radius
            
            if ((entityPos.y - entityRadius) <= 0 && entities[i].velocity.y <= 0) {
                entities[i].acceleration = [entities[i].acceleration.x, 0, entities[i].acceleration.z]
                entities[i].velocity = [entities[i].velocity.x, -entities[i].velocity.y, entities[i].velocity.z]
                entities[i].setPosition([entityPos.x, entityRadius, entityPos.z])
            }
        }
    }
}
