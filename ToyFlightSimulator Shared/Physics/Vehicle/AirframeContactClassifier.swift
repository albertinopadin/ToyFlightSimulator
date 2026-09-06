//
//  AirframeContactClassifier.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/6/26.
//

/// Crash-vs-landing vocabulary for airframe ground contacts. Pure.
enum AirframeContactClass {
    /// Gentle airframe contact: a skid, a tail scrape, a soft belly slide.
    case scrape
    /// Hard airframe contact: a crash in gameplay terms.
    case impact
}

enum AirframeContactClassifier {
    /// Normal-speed boundary between scrape and impact. 2 m/s sits between
    /// gentle contact (under 1 m/s) and a hard landing (about 3 m/s sink, on
    /// the gear). Strictly greater; tunable.
    static let impactSpeedThreshold: Float = 2.0
    
    /// Approach speed along the contact normal. `contactNormal` is the
    /// Contact's B→A normal with the aircraft as A, so approach is −dot(v, n);
    /// a separating velocity clamps to 0.
    static func normalSpeed(contactNormal: float3, preImpactVelocity: float3) -> Float {
        max(0, -dot(preImpactVelocity, contactNormal))
    }
    
    static func classification(forNormalSpeed speed: Float) -> AirframeContactClass {
        speed > impactSpeedThreshold ? .impact : .scrape
    }
}
