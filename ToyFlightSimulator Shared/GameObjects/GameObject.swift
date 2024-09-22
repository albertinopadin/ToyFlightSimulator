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
    
    public var isTransparent: Bool {
        return (modelConstants.useObjectColor && modelConstants.objectColor.w < 1.0)
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
