//
//  AircraftTelemetryStore.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/17/26.
//

import Observation

/// Main-actor mailbox between the UpdateThread and SwiftUI. `GameScene.update`
/// hops the player aircraft's latest `AircraftTelemetry` here (a Sendable
/// value copy) at its publish interval; views read `latestSnapshot` inside
/// `body` and re-render through Observation. Holds no engine object, so
/// aircraft swaps and scene resets need no re-pointing.
@MainActor
@Observable
final class AircraftTelemetryStore {
    public static let sharedInstance = AircraftTelemetryStore()
    
    /// What the store holds while no player aircraft is publishing: before the
    /// first publish, and again from every scene teardown
    /// (`SceneManager.TeardownScene`) until the next scene's first publish,
    /// which never comes in a scene without a player aircraft. `aircraftType`
    /// nil reads as "Undefined" in the panel rather than naming a jet that is
    /// not there, and hides the HUD tapes.
    static let noAircraftSnapshot = AircraftTelemetry(aircraftType: nil,
                                                      heading: 0,
                                                      altitudeInMeters: 0,
                                                      forwardSpeedInMetersPerSecond: 0,
                                                      pitchAngle: 0,
                                                      rollAngle: 0)

    var latestSnapshot = AircraftTelemetryStore.noAircraftSnapshot

    private init() {}
}
