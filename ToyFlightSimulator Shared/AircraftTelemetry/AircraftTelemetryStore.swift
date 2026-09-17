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
    
    /// Zeroed placeholder until the first publish. `aircraftType` nil reads
    /// as "Undefined" rather than naming a jet that is not there yet.
    var latestSnapshot = AircraftTelemetry(aircraftType: nil,
                                           heading: 0,
                                           altitudeInMeters: 0,
                                           forwardSpeedInMetersPerSecond: 0,
                                           pitchAngle: 0,
                                           rollAngle: 0)
    
    private init() {}
}
