//
//  HeckerCollisionResponse.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

// From https://www.chrishecker.com/images/e/e7/Gdmphys3.pdf
// and: https://www.youtube.com/watch?v=vQO_hPOE-1Y

extension float3 {
    var magnitude: Float {
        sqrt(x * x + y * y + z * z)
    }
    
    func normalize() -> float3 {
        return self / magnitude
    }
}

final class HeckerCollisionResponse {
    static func resolveCollisions(deltaTime: Float, entities: inout [PhysicsEntity]) {
        for a in 0..<entities.count {
            for b in 0..<entities.count {
                if a != b {
                    var entityA = entities[a]
                    var entityB = entities[b]
                    
                    let alreadyCollided = entityA.collidedWith[entityB.id] ?? false
                    
                    if !alreadyCollided && PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
                        entityA.collidedWith[entityB.id] = true
                        entityB.collidedWith[entityA.id] = true
                        
                        let collisionData = PhysicsWorld.getCollisionData(entityA, entityB)
                        let penetrationDepth = collisionData.penetrationDepth
                        let collisionNormal = collisionData.collisionVector.normalize()
                        
                        if !entityA.isStatic && !entityB.isStatic {
                            entities[a].setPosition(entities[a].getPosition() + collisionNormal * (penetrationDepth / 2))
                            entities[b].setPosition(entities[b].getPosition() - collisionNormal * (penetrationDepth / 2))
                            
                            let relativeVelo = entityA.velocity - entityB.velocity
                            let e = min(entityA.restitution, entityB.restitution)
                            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
                            j /= ((1.0 / entityA.mass) + (1.0 / entityB.mass))
                            
                            let entityADeltaVelo = j / entityA.mass * collisionNormal
                            let entityBDeltaVelo = j / entityB.mass * collisionNormal
                            
                            entities[a].velocity += entityADeltaVelo.magnitude > 1.0 ? entityADeltaVelo : .zero
                            entities[b].velocity -= entityBDeltaVelo.magnitude > 1.0 ? entityBDeltaVelo : .zero
                            
                            continue
                        }
                        
                        if !entityA.isStatic && entityB.isStatic {
                            entities[a].setPosition(entities[a].getPosition() + collisionNormal * (penetrationDepth * 2))
                            
                            let relativeVelo = entityA.velocity
                            let e = min(entityA.restitution, entityB.restitution)
                            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
                            j /= 1.0 / entityA.mass
                            
                            let entityADeltaVelo = j / entityA.mass * collisionNormal
                            entities[a].velocity += entityADeltaVelo.magnitude > 1.0 ? entityADeltaVelo : .zero
                            
                            continue
                        }
                        
                        if entityA.isStatic && !entityB.isStatic {
                            entities[b].setPosition(entities[b].getPosition() + collisionNormal * (penetrationDepth * 2))
                            
                            let relativeVelo = entityB.velocity
                            let e = min(entityA.restitution, entityB.restitution)
                            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
                            j /= 1.0 / entityB.mass
                            
                            let entityBDeltaVelo = j / entityB.mass * collisionNormal
                            entities[b].velocity += entityBDeltaVelo.magnitude > 1.0 ? entityBDeltaVelo : .zero
                            
                            continue
                        }
                    }
                }
            }
        }
    }
}
