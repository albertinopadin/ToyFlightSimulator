//
//  TimeItTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import Foundation
@testable import ToyFlightSimulator

@Suite("TimeIt", .tags(.utils))
struct TimeItTests {

    @Test("timeit returns a non-negative duration for a trivial body")
    func nonNegative() {
        let ns = timeit { _ = (0..<1000).reduce(0, +) }
        #expect(ns >= 0)
    }

    @Test("timeit measures at least the requested sleep duration",
          .timeLimit(.minutes(1)))
    func sleepDuration() {
        let ns = timeit {
            Thread.sleep(forTimeInterval: 0.05)  // 50 ms
        }
        // Lower bound only: scheduling jitter can stretch this arbitrarily upward,
        // but the elapsed time should never be under ~40 ms.
        #expect(ns >= 40_000_000)
    }
}
