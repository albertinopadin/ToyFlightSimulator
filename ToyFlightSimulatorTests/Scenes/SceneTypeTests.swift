//
//  SceneTypeTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 11/23/26.
//

import Testing
@testable import ToyFlightSimulator

/// `SceneType` drives the menu's `ScenePicker`: `allCases` is the list of rows,
/// `id` is the `ForEach` identity and `rawValue` is the text of each row. These
/// tests are Metal-free: they never build a scene, so they do not touch
/// `SceneManager`'s live state in the app-hosted suite.
@Suite("SceneType", .tags(.scenes))
struct SceneTypeTests {

    @Test("Exposes exactly the eight expected cases via CaseIterable")
    func allCasesArePresent() {
        #expect(SceneType.allCases.count == 8)
        #expect(Set(SceneType.allCases) == [.Sandbox,
                                            .Flightbox,
                                            .FreeCamFlightbox,
                                            .FlightboxWithTerrain,
                                            .FlightboxWithPhysics,
                                            .BallPhysics,
                                            .PhysicsStressTest,
                                            .Debug])
    }

    @Test("Identifiable id is the raw value (drives the SwiftUI Picker tag/ForEach)")
    func idEqualsRawValue() {
        for sceneType in SceneType.allCases {
            #expect(sceneType.id == sceneType.rawValue)
        }
    }

    // Two rows with the same id would make ForEach reuse one row for both
    // scenes, and two rows with the same text could not be told apart in the menu.
    @Test("Every menu label is non-empty and unique")
    func rawValuesAreNonEmptyAndUnique() {
        let rawValues = SceneType.allCases.map(\.rawValue)
        #expect(rawValues.allSatisfy { !$0.isEmpty })
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("Raw values round-trip back to their case")
    func rawValueRoundTrips() {
        for sceneType in SceneType.allCases {
            #expect(SceneType(rawValue: sceneType.rawValue) == sceneType)
        }
    }
}
