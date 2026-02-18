//
//  AnimationLayer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/19/26.
//

/// An animation layer groups related animation channels that should animate together
/// to form a discrete animation (e.g., all the channels needed to extend the landing gear).
struct AnimationLayer {
    let id: String
    let channels: [AnimationChannel]

    func update(deltaTime: Float) {
        channels.forEach { $0.update(deltaTime: deltaTime) }
    }

    // Hack:
    public var state: BinaryAnimationChannel.State {
        return (channels.first as? BinaryAnimationChannel)?.state ?? .inactive
    }

    // Hack:
    public var progress: Float {
        return (channels.first as? BinaryAnimationChannel)?.progress ?? 0.0
    }

    // Hack:
    public var transitionDuration: Float {
        return (channels.first as? BinaryAnimationChannel)?.transitionDuration ?? 0.0
    }

    // OMG So many hacks:
    public func activate() {
        channels.forEach { ($0 as? BinaryAnimationChannel)?.activate() }
    }

    public func deactivate() {
        channels.forEach { ($0 as? BinaryAnimationChannel)?.deactivate() }
    }

    public func toggle() {
        channels.forEach { ($0 as? BinaryAnimationChannel)?.toggle() }
    }

    public var isAnimating: Bool {
        return (channels.first as? BinaryAnimationChannel)?.isAnimating ?? false
    }

    public var isActive: Bool {
        return (channels.first as? BinaryAnimationChannel)?.isActive ?? false
    }

    public var isInactive: Bool {
        return (channels.first as? BinaryAnimationChannel)?.isInactive ?? false
    }
}
