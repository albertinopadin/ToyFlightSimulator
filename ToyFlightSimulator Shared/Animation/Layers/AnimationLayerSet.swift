//
//  AnimationLayerSet.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/19/26.
//

struct AnimationLayerSet {
    let id: String
    let layers: [AnimationLayer]
    
    func update(deltaTime: Float) {
        layers.forEach { $0.update(deltaTime: deltaTime) }
    }
    
    // Hack:
    public var state: BinaryAnimationLayer.State {
        return (layers.first as? BinaryAnimationLayer)?.state ?? .inactive
    }
    
    // Hack:
    public var progress: Float {
        return (layers.first as? BinaryAnimationLayer)?.progress ?? 0.0
    }
    
    // Hack:
    public var transitionDuration: Float {
        return (layers.first as? BinaryAnimationLayer)?.transitionDuration ?? 0.0
    }
    
    // OMG So many hacks:
    public func activate() {
        layers.forEach { ($0 as? BinaryAnimationLayer)?.activate() }
    }
    
    public func deactivate() {
        layers.forEach { ($0 as? BinaryAnimationLayer)?.deactivate() }
    }
    
    public func toggle() {
        layers.forEach { ($0 as? BinaryAnimationLayer)?.toggle() }
    }
    
    public var isAnimating: Bool {
        return (layers.first as? BinaryAnimationLayer)?.isAnimating ?? false
    }
    
    public var isActive: Bool {
        return (layers.first as? BinaryAnimationLayer)?.isActive ?? false
    }
    
    public var isInactive: Bool {
        return (layers.first as? BinaryAnimationLayer)?.isInactive ?? false
    }
}
