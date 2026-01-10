//
//  AnimationController.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/10/26.
//

import Foundation

/// Defines the playback state of an animation
enum AnimationPlaybackState {
    case stopped
    case playing
    case paused
}

/// Protocol defining the interface for animation controllers.
/// Animation controllers manage animation playback state and timing,
/// separating playback behavior from animation data (stored in AnimationClip/Skeleton).
protocol AnimationController: AnyObject {
    /// The current playback state
    var playbackState: AnimationPlaybackState { get }

    /// Whether the animation is currently playing
    var isPlaying: Bool { get }

    /// The current playback time in seconds
    var currentTime: Float { get }

    /// The total duration of the current animation
    var duration: Float { get }

    /// The normalized time (0.0 to 1.0) representing progress through the animation
    var normalizedTime: Float { get }

    /// Play an animation clip by name
    /// - Parameters:
    ///   - clipName: The name of the animation clip to play
    ///   - speed: Playback speed multiplier (1.0 = normal, negative = reverse)
    ///   - loop: Whether the animation should loop
    func play(clipName: String, speed: Float, loop: Bool)

    /// Pause the current animation
    func pause()

    /// Stop the animation and reset to the beginning
    func stop()

    /// Set the animation to a specific normalized time
    /// - Parameter t: Normalized time (0.0 = start, 1.0 = end)
    func setNormalizedTime(_ t: Float)

    /// Update the animation state. Called every frame.
    /// - Parameter deltaTime: Time elapsed since last update in seconds
    func update(deltaTime: Float)
}

// MARK: - Default Implementations
extension AnimationController {
    var isPlaying: Bool {
        return playbackState == .playing
    }

    var normalizedTime: Float {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
}
