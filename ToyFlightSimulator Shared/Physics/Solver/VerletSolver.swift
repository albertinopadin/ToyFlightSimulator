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
            if !entities[i].isStatic {
                let pos = entities[i].getPosition()
                let velo = entities[i].velocity
                let acc = entities[i].acceleration
                
                let nPosEuler: float3 = pos + velo * deltaTime
                let nPos: float3 = nPosEuler + 0.5 * acc * (deltaTime * deltaTime)
                
                let veloDtHalf = velo + 0.5 * acc * deltaTime
                
                var newAcc = acc
                
                if entities[i].shouldApplyGravity {
                    newAcc += Self.applyForces(gravity: gravity)
                } else {
                    print("[VerletSolver step] Entity \(entities[i].id) not applying gravity")
                }
                
                let nVelo = veloDtHalf + 0.5 * newAcc * deltaTime
                
                entities[i].setPosition(nPos)
                entities[i].velocity = nVelo
                entities[i].acceleration = newAcc
            }
        }
    }
    
    static func zeroAcceleration(entities: inout [any PhysicsEntity]) {
        for i in 0..<entities.count {
            entities[i].acceleration = .zero
        }
    }
    
    static func applyForces(gravity: float3, force: float3 = .zero) -> float3 {
        return gravity + force
    }
}
