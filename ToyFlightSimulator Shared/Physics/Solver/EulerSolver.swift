//
//  EulerSolver.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

final class EulerSolver: PhysicsSolver {
    public static func step(deltaTime: Float, gravity: float3, entities: inout [any PhysicsEntity]) {
        applyGravity(deltaTime: deltaTime, gravity: gravity, entities: &entities)
        resolveCollisions(deltaTime: deltaTime, entities: &entities)
        moveObjects(deltaTime: deltaTime, entities: &entities)
    }
    
    public static func applyGravity(deltaTime: Float, gravity: float3, entities: inout [PhysicsEntity]) {
        for i in 0..<entities.count {
            if !entities[i].isStatic {
                let entityVelo: float3 = [entities[i].velocity.x + gravity.x * deltaTime,
                                          entities[i].velocity.y + gravity.y * deltaTime,
                                          entities[i].velocity.z + gravity.z * deltaTime]
                
                entities[i].velocity = entityVelo
            }
        }
    }
    
    static func resolveCollisions(deltaTime: Float, entities: inout [PhysicsEntity]) {
        for i in 0..<entities.count {
            for j in 0..<entities.count {
                if i != j {
                    let ei = entities[i]
                    let ej = entities[j]
                    
                    if PhysicsWorld.collided(entityA: ei, entityB: ej) {
                        let collisionVector = PhysicsWorld.getCollisionVector(ei.getPosition(), ej.getPosition())
                        
                        if !entities[i].isStatic {
                            let eiVelo = ei.velocity + collisionVector
                            entities[i].velocity = eiVelo
                        }
                        
                        if !entities[j].isStatic {
                            let ejVelo = ej.velocity - collisionVector
                            entities[j].velocity = ejVelo
                        }
                    }
                }
            }
        }
    }
    
    static func moveObjects(deltaTime: Float, entities: inout [PhysicsEntity]) {
        for i in 0..<entities.count {
            if !entities[i].isStatic {
                let entityPos: float3 = [entities[i].getPosition().x + entities[i].velocity.x * deltaTime,
                                         entities[i].getPosition().y + entities[i].velocity.y * deltaTime,
                                         entities[i].getPosition().z + entities[i].velocity.z * deltaTime]
                
                entities[i].setPosition(entityPos)
            }
        }
    }
}
