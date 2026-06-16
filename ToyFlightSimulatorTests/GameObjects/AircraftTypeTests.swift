//
//  AircraftTypeTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 6/16/26.
//

import Testing
@testable import ToyFlightSimulator

@Suite("AircraftType", .tags(.gameObjects))
struct AircraftTypeTests {

    @Test("Exposes exactly the five expected cases via CaseIterable")
    func allCasesArePresent() {
        #expect(AircraftType.allCases.count == 5)
        #expect(Set(AircraftType.allCases) == [.f16, .f18, .f22, .f22_cgtrader, .f35])
    }

    @Test("Identifiable id is the raw value (drives the SwiftUI Picker tag/ForEach)")
    func idEqualsRawValue() {
        for type in AircraftType.allCases {
            #expect(type.id == type.rawValue)
        }
    }

    @Test("Every display name is non-empty and unique")
    func rawValuesAreNonEmptyAndUnique() {
        let rawValues = AircraftType.allCases.map(\.rawValue)
        #expect(rawValues.allSatisfy { !$0.isEmpty })
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("Raw values round-trip back to their case")
    func rawValueRoundTrips() {
        for type in AircraftType.allCases {
            #expect(AircraftType(rawValue: type.rawValue) == type)
        }
    }
}
