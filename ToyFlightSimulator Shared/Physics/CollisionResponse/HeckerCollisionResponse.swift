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
    // New method that accepts collision pairs from broad-phase
    static func resolveCollisions(deltaTime: Float, entities: inout [PhysicsEntity], collisionPairs: [(PhysicsEntity, PhysicsEntity)]) {
        // Create a map for quick entity index lookup
        var entityIndexMap: [String: Int] = [:]
        for (index, entity) in entities.enumerated() {
            entityIndexMap[entity.id] = index
        }
        
        // Process only the potential collision pairs from broad-phase
        for (entityA, entityB) in collisionPairs {
            guard let indexA = entityIndexMap[entityA.id],
                  let indexB = entityIndexMap[entityB.id] else {
                continue
            }
            
            let alreadyCollided = entities[indexA].collidedWith[entities[indexB].id] ?? false
            
            // Perform narrow-phase collision detection
            if !alreadyCollided && PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
                entities[indexA].collidedWith[entityB.id] = true
                entities[indexB].collidedWith[entityA.id] = true
                
                // Apply collision response (same logic as before)
                applyCollisionResponse(indexA: indexA, indexB: indexB, 
                                      entityA: entityA, entityB: entityB,
                                      entities: &entities)
            }
        }
    }
    
    // Original method for backwards compatibility (deprecated)
    static func resolveCollisions(deltaTime: Float, entities: inout [PhysicsEntity]) {
        for a in 0..<entities.count {
            for b in 0..<entities.count {
                if a != b {
                    let entityA = entities[a]
                    let entityB = entities[b]
                    
                    let alreadyCollided = entities[a].collidedWith[entities[b].id] ?? false
                    
                    // TODO: To stop infinite bouncing -> check if relative velocity abs value is below threshold ?
                    if !alreadyCollided && PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
                        entities[a].collidedWith[entityB.id] = true
                        entities[b].collidedWith[entityA.id] = true
                        
                        applyCollisionResponse(indexA: a, indexB: b,
                                             entityA: entityA, entityB: entityB,
                                             entities: &entities)
                    }
                }
            }
        }
    }
    
    // Helper method to apply collision response
    private static func applyCollisionResponse(indexA: Int, indexB: Int,
                                              entityA: PhysicsEntity, entityB: PhysicsEntity,
                                              entities: inout [PhysicsEntity]) {
        // Hack:
        // TODO: This will fail if the static entity is not directly below the non-static
        //       entity. Need to figure out a better way...
        let relVeloMagnitude = (entityA.velocity - entityB.velocity).magnitude
        // TODO: My units seem to be messed up, 'small' collisions seem to be ~ 0.7 m/s
        if relVeloMagnitude < 0.55 {
            if entityB.isStatic {
                entities[indexA].velocity = .zero
                entities[indexA].acceleration = .zero
                entities[indexA].shouldApplyGravity = false
                
                print("[HeckerCollisionResponse resolveCollisions] Gravity should not apply to entity: \(entityA.id)")
            }
            
            if entityA.isStatic {
                entities[indexB].velocity = .zero
                entities[indexB].acceleration = .zero
                entities[indexB].shouldApplyGravity = false
                
                print("[HeckerCollisionResponse resolveCollisions] Gravity should not apply to entity: \(entityB.id)")
            }
            
            return
        }
        
        let collisionData = PhysicsWorld.getCollisionData(entityA, entityB)
        let penetrationDepth = collisionData.penetrationDepth
        let collisionNormal = collisionData.collisionVector.normalize()
        
        if !entityA.isStatic && !entityB.isStatic {
            entities[indexA].setPosition(entities[indexA].getPosition() + collisionNormal * (penetrationDepth / 2))
            entities[indexB].setPosition(entities[indexB].getPosition() - collisionNormal * (penetrationDepth / 2))
            
            let relativeVelo = entityA.velocity - entityB.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
            j /= ((1.0 / entityA.mass) + (1.0 / entityB.mass))
            
            let entityADeltaVelo = j / entityA.mass * collisionNormal
            let entityBDeltaVelo = j / entityB.mass * collisionNormal
            
            entities[indexA].velocity += entityADeltaVelo.magnitude > 1.0 ? entityADeltaVelo : .zero
            entities[indexB].velocity -= entityBDeltaVelo.magnitude > 1.0 ? entityBDeltaVelo : .zero
            
            return
        }
        
        if !entityA.isStatic && entityB.isStatic {
            entities[indexA].setPosition(entities[indexA].getPosition() + collisionNormal * (penetrationDepth * 2))
            
            let relativeVelo = entityA.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
            j /= 1.0 / entityA.mass
            
            let entityADeltaVelo = j / entityA.mass * collisionNormal
            entities[indexA].velocity += entityADeltaVelo.magnitude > 1.0 ? entityADeltaVelo : .zero
            
            return
        }
        
        if entityA.isStatic && !entityB.isStatic {
            entities[indexB].setPosition(entities[indexB].getPosition() + collisionNormal * (penetrationDepth * 2))
            
            let relativeVelo = entityB.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
            j /= 1.0 / entityB.mass
            
            let entityBDeltaVelo = j / entityB.mass * collisionNormal
            entities[indexB].velocity += entityBDeltaVelo.magnitude > 1.0 ? entityBDeltaVelo : .zero
            
            return
        }
    }
}
