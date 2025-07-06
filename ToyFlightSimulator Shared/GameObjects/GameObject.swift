//
//  GameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class GameObject: Node, PhysicsEntity, Renderable, Hashable {
    var id: String = UUID().uuidString
    var collidedWith: [String : Bool] = [:]
    var collisionShape: CollisionShape = .Sphere
    var isStatic: Bool = false
    var shouldApplyGravity: Bool = true
    var mass: Float = 1.0
    var velocity: float3 = [0, 0, 0]
    var acceleration: float3 = [0, 0, 0]
    var restitution: Float = 1.0
    
    static func == (lhs: GameObject, rhs: GameObject) -> Bool {
        return lhs.getID() == rhs.getID()
    }
    
    public var model: Model!
    public var modelConstants = ModelConstants()
    public var meshVisibility: [String: Bool] = [:]  // Control which meshes are visible
    
    public var isTransparent: Bool {
        return (modelConstants.useObjectColor && modelConstants.objectColor.w < 1.0)
    }
    
    // Get visible meshes based on meshVisibility settings
    public var visibleMeshes: [Mesh] {
        if meshVisibility.isEmpty {
            return model.meshes  // If no visibility settings, show all
        }
        
        if let usdModel = model as? UsdModel {
            return model.meshes.enumerated().compactMap { index, mesh in
                // Check if this mesh should be visible
                if let isVisible = meshVisibility[mesh.name], !isVisible {
                    return nil
                }
                return mesh
            }
        }
        
        return model.meshes
    }
    
    init(name: String, modelType: ModelType) {
        super.init(name: name)
        model = Assets.Models[modelType]
        model.parent = self
        
        print("GameObject init; named \(self.getName())")
    }
    
    override func update() {
        super.update()
        modelConstants.modelMatrix = self.modelMatrix
        modelConstants.normalMatrix = Transform.normalMatrix(from: self.modelMatrix)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.getID())
    }
    
    public func setColor(_ color: float4) {
        modelConstants.objectColor = color
        modelConstants.useObjectColor = true
    }
}
