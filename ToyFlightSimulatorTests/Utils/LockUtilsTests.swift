//
//  LockUtilsTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import os
@testable import ToyFlightSimulator

@Suite("Locking utilities", .tags(.utils, .concurrency))
struct LockUtilsTests {

    @Test("withLock returns the body's value")
    func withLockReturns() {
        let lock = OSAllocatedUnfairLock()
        let result = withLock(lock) { 7 * 6 }
        #expect(result == 42)
    }

    @Test("withLock releases the lock after body runs (second call succeeds immediately)",
          .timeLimit(.minutes(1)))
    func withLockReleases() {
        let lock = OSAllocatedUnfairLock()
        _ = withLock(lock) { 1 }
        _ = withLock(lock) { 2 }
        // If the lock leaked, the second call would deadlock under the timeLimit.
    }
}
