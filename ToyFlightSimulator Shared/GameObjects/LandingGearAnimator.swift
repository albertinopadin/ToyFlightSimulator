//
//  LandingGearAnimator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/20/24.
//

import simd

/// Manages the animation state and timing for a landing gear system
final class LandingGearAnimator {
    enum GearState {
        case deployed
        case retracted
        case deploying
        case retracting
    }

    private(set) var state: GearState = .deployed

    /// Current animation progress (0.0 = deployed, 1.0 = retracted)
    private(set) var progress: Float = 0.0

    /// Animation speed (progress per frame, at 60fps this means ~1.5 seconds for full animation)
    var animationSpeed: Float = 0.015

    /// Maximum rotation angle for strut retraction (degrees)
    let maxStrutRotation: Float = 90.0

    /// Maximum rotation angle for doors (degrees)
    let maxDoorRotation: Float = 90.0

    var isAnimating: Bool {
        return state == .deploying || state == .retracting
    }

    var isDeployed: Bool {
        return state == .deployed
    }

    var isRetracted: Bool {
        return state == .retracted
    }

    func toggle() {
        switch state {
        case .deployed:
            state = .retracting
            print("[LandingGearAnimator] Starting retraction")
        case .retracted:
            state = .deploying
            print("[LandingGearAnimator] Starting deployment")
        case .deploying:
            // Reverse direction
            state = .retracting
            print("[LandingGearAnimator] Reversing to retraction")
        case .retracting:
            // Reverse direction
            state = .deploying
            print("[LandingGearAnimator] Reversing to deployment")
        }
    }

    /// Call each frame to update animation progress
    /// Returns true if animation is in progress
    @discardableResult
    func update() -> Bool {
        switch state {
        case .retracting:
            progress = min(progress + animationSpeed, 1.0)
            if progress >= 1.0 {
                state = .retracted
                print("[LandingGearAnimator] Retraction complete")
                return false
            }
            return true

        case .deploying:
            progress = max(progress - animationSpeed, 0.0)
            if progress <= 0.0 {
                state = .deployed
                print("[LandingGearAnimator] Deployment complete")
                return false
            }
            return true

        default:
            return false
        }
    }

    /// Current strut rotation angle in radians (0 = deployed, 90deg = retracted)
    var strutAngleRadians: Float {
        return (progress * maxStrutRotation).toRadians
    }

    /// Current strut rotation angle in degrees
    var strutAngleDegrees: Float {
        return progress * maxStrutRotation
    }

    /// Door animation progress - doors open first during retraction, close at end
    /// Returns value from 0 (closed) to 1 (fully open)
    var doorOpenProgress: Float {
        // Doors open from 0-30% of animation, stay open 30-70%, close from 70-100%
        if progress < 0.3 {
            // Opening phase: 0 to 1 as progress goes from 0 to 0.3
            return progress / 0.3
        } else if progress < 0.7 {
            // Stay open
            return 1.0
        } else {
            // Closing phase: 1 to 0 as progress goes from 0.7 to 1.0
            return 1.0 - ((progress - 0.7) / 0.3)
        }
    }

    /// Door rotation angle in radians
    var doorAngleRadians: Float {
        return (doorOpenProgress * maxDoorRotation).toRadians
    }

    /// Strut animation progress - struts move during middle of animation
    /// Returns value from 0 (deployed) to 1 (retracted)
    var strutProgress: Float {
        // Struts move from 10-90% of animation
        if progress < 0.1 {
            return 0.0
        } else if progress > 0.9 {
            return 1.0
        } else {
            return (progress - 0.1) / 0.8
        }
    }

    /// Strut rotation angle based on sequenced animation in radians
    var sequencedStrutAngleRadians: Float {
        return (strutProgress * maxStrutRotation).toRadians
    }
}
