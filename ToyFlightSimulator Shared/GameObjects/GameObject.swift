//
//  GameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class GameObject: Node, Renderable, Hashable {
    static func == (lhs: GameObject, rhs: GameObject) -> Bool {
        return lhs.getID() == rhs.getID()
    }
    
    public var model: Model!
    public var modelConstants = ModelConstants()
    public var material: MaterialProperties? = nil
    
    init(name: String, modelType: ModelType, materialProperties: MaterialProperties? = nil) {
        super.init(name: name)
        model = Assets.Models[modelType]
        model.parent = self
        
        if let materialProperties {
            useMaterial(materialProperties)
        }
        
//        DrawManager.Register(self)
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
    
    public func useMaterial(_ material: MaterialProperties) {
        self.material = material
        modelConstants.useObjectMaterial = true
    }
}
