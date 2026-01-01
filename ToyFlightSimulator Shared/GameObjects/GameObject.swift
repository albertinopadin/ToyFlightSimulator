//
//  GameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class GameObject: Node, PhysicsEntity, Renderable, Hashable {
    var id: String {
        return getID()
    }
    
    // Physics stuff:
    var collidedWith: [String : Bool] = [:]
    var collisionShape: CollisionShape = .Sphere
    var isStatic: Bool = false
    var shouldApplyGravity: Bool = true
    var mass: Float = 1.0
    var velocity: float3 = [0, 0, 0]
    var acceleration: float3 = [0, 0, 0]
    var restitution: Float = 1.0
    
    // Default AABB implementation for GameObjects
    func getAABB() -> AABB {
        // Default implementation - can be overridden by subclasses
        // For now, use a simple box based on scale
        let halfExtents = getScale() * 0.5
        return AABB(center: getPosition(), halfExtents: halfExtents)
    }
    
    public var model: Model!
    public var modelConstants = ModelConstants()
    
    static func == (lhs: GameObject, rhs: GameObject) -> Bool {
        return lhs.getID() == rhs.getID()
    }
    
    public var isTransparent: Bool {
        return (modelConstants.useObjectColor && modelConstants.objectColor.w < 1.0)
    }
    
    init(name: String, modelType: ModelType) {
        super.init(name: name)
        model = Assets.Models[modelType]
        // TODO: This actually doesn't make sense because this parent gets overwritten everytime a new object with the same
        //       model is created. Either remove this or if you want to keep track of which GO's are assoicated with what
        //       models use a list you append the GO to.
        model.parent = self
        print("GameObject init; named \(self.getName())")
    }
    
    override func update() {
        super.update()
        modelConstants.modelMatrix = self.modelMatrix
        modelConstants.normalMatrix = Transform.normalMatrix(from: self.modelMatrix)
        
        // TODO: hmm... might want to refactor this later...
        model.update()
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.getID())
    }
    
    public func setColor(_ color: float4) {
        modelConstants.objectColor = color
        modelConstants.useObjectColor = true
    }
    
    public func shouldRenderSubmesh(_ submesh: Submesh) -> Bool {
        return true
    }
    
    public func shouldRenderSubmesh(_ submeshName: String) -> Bool {
        return true
    }
}
