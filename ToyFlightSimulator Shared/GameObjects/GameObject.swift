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
    public var baseColorTextureType: TextureType = .None
    public var normalMapTextureType: TextureType = .None
    public var specularTextureType: TextureType = .None
    
    init(name: String, modelType: ModelType) {
        super.init(name: name)
        model = Assets.Models[modelType]
        model.parent = self
        
        DrawManager.Register(self)
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
}

// Material Properties
extension GameObject {
    public func useBaseColorTexture(_ textureType: TextureType) {
        baseColorTextureType = textureType
    }
    
    public func useNormalMapTexture(_ textureType: TextureType) {
        normalMapTextureType = textureType
    }
    
    public func useSpecularTexture(_ textureType: TextureType) {
        specularTextureType = textureType
    }
    
    public func useMaterial(_ material: MaterialProperties) {
        self.material = material
        model.meshes.forEach { $0.submeshes.forEach { $0.material = Material(material) } }
    }
}
