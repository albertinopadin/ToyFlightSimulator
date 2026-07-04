//
//  GameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class GameObject: Node, Renderable, Hashable {
    var id: String {
        return getID()
    }
    
    public var rigidBody: RigidBody?
    
    // TODO: below should be part of a Collider...
    // Default AABB implementation for GameObjects
    func getAABB() -> AABB {
        // Default implementation - can be overridden by subclasses
        // For now, use a simple box based on scale
        let halfExtents = getScale() * 0.5
        return AABB(center: getPosition(), halfExtents: halfExtents)
    }
    
    public let model: Model
    public var modelConstants = ModelConstants()

    // Index into persistent instance buffer. -1 if not registered:
    var instanceBufferIndex: Int = -1

    static func == (lhs: GameObject, rhs: GameObject) -> Bool {
        return lhs.getID() == rhs.getID()
    }

    public var isTransparent: Bool {
        return (modelConstants.useObjectColor && modelConstants.objectColor.w < 1.0)
    }

    /// The registration category of this object — SceneManager batches it into
    /// a collection based on this value. Subclasses that live in a side
    /// collection override this; the base handles Tessellatable conformers and
    /// the opaque/transparent split automatically.
    var objectType: GameObjectType {
        if self is Tessellatable { return .tessellatables }
        return .renderables(transparent: isTransparent)
    }

    /// Set by SceneManager.Register with the objectType actually registered
    /// under; consumed and cleared by Unregister. nil ⇒ not currently
    /// registered. Capturing this at registration means unregistration never
    /// re-derives state that may have changed since (e.g. isTransparent via
    /// setColor).
    var registeredObjectType: GameObjectType?

    /// Removes this object (and its subtree) from both the scene graph and
    /// SceneManager's batched collections. Runtime despawns (fired weapons
    /// reaping themselves) must use this — a bare `parent?.removeChild(self)`
    /// leaves the object registered, so it keeps being drawn at its last
    /// position and never deallocates. Call from the update thread only
    /// (doUpdate), like all scene-graph mutation.
    func removeFromScene() {
        parent?.removeChild(self)
        SceneManager.Unregister(self)
    }

    init(name: String, modelType: ModelType) {
        // ModelLibrary's subscript fatalErrors on missing keys, so this is non-optional.
        self.model = Assets.Models[modelType]
        super.init(name: name)
    }
    
    override func update() {
        super.update()
        
        if worldMatrixDirty {
            let world = self.modelMatrix   // one cached read for both fields
            modelConstants.modelMatrix = world
            modelConstants.normalMatrix = Transform.normalMatrix(from: world)
        }
        
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
