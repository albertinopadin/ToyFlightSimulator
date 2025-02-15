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
                    var ei = entities[i]
                    var ej = entities[j]
                    
                    let alreadyCollided = ei.collidedWith[ej.id] ?? false
                    
                    if !alreadyCollided && PhysicsWorld.collided(entityA: ei, entityB: ej) {
                        ei.collidedWith[ej.id] = true
                        ej.collidedWith[ei.id] = true
                        
                        let collisionData = PhysicsWorld.getCollisionData(ei, ej)
                        let collisionVector = collisionData.collisionVector
                        let restitution = min(ei.restitution, ej.restitution)
                        let unormCollisionVector = collisionData.collisionVector * collisionData.penetrationDepth
                        
                        // Hack to prevent infinite bouncing:
                        if abs(collisionData.penetrationDepth) < 0.01 {
                            entities[i].velocity = .zero
                            entities[j].velocity = .zero
                        } else {
                            if !entities[i].isStatic && !entities[j].isStatic {
                                let newPosI = entities[i].getPosition() + unormCollisionVector
                                entities[i].setPosition(newPosI)
                                let eiVelo = (ei.velocity + collisionVector) * restitution
                                entities[i].velocity = eiVelo
                                
                                let newPosJ = entities[j].getPosition() - unormCollisionVector
                                entities[j].setPosition(newPosJ)
                                let ejVelo = (ej.velocity - collisionVector) * restitution
                                entities[j].velocity = ejVelo
                                
                                continue
                            }
                            
                            if !entities[i].isStatic && entities[j].isStatic {
                                let newPos = entities[i].getPosition() + unormCollisionVector * 2
                                entities[i].setPosition(newPos)
                                let vX = collisionVector.x != 0 ? ei.velocity.x * -collisionVector.x * restitution : ei.velocity.x
                                let vY = collisionVector.y != 0 ? ei.velocity.y * -collisionVector.y * restitution : ei.velocity.y
                                let vZ = collisionVector.z != 0 ? ei.velocity.z * -collisionVector.z * restitution : ei.velocity.z
                                let eiVelo: float3 = [vX, vY, vZ]
                                entities[i].velocity = eiVelo
                                
                                continue
                            }
                            
                            if entities[i].isStatic && !entities[j].isStatic {
                                let newPos = entities[j].getPosition() - unormCollisionVector * 2
                                entities[j].setPosition(newPos)
                                let vX = collisionVector.x != 0 ? ej.velocity.x * -collisionVector.x * restitution : ej.velocity.x
                                let vY = collisionVector.y != 0 ? ej.velocity.y * -collisionVector.y * restitution : ej.velocity.y
                                let vZ = collisionVector.z != 0 ? ej.velocity.z * -collisionVector.z * restitution : ej.velocity.z
                                let ejVelo: float3 = [vX, vY, vZ]
                                entities[j].velocity = ejVelo
                                
                                continue
                            }
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
