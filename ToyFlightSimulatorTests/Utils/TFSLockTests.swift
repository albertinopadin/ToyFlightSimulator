//
//  TFSLockTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import os
@testable import ToyFlightSimulator

/// Sendable box for sharing a mutable counter across concurrent tasks.
/// Mutation is guarded by the lock-under-test (TFSLock), not by this wrapper itself.
private final class Counter: @unchecked Sendable {
    var value: Int = 0
}

@Suite("Locking utilities", .tags(.utils, .concurrency))
struct LockTests {

    @Test("TFSLock.lock executes its block")
    func tfsLockRuns() {
        let ran = Counter()
        TFSLock.lock { ran.value = 1 }
        #expect(ran.value == 1)
    }

    @Test("TFSLock serializes concurrent increments of a shared counter",
          .timeLimit(.minutes(1)))
    func tfsLockSerializes() async {
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<500 {
                group.addTask {
                    TFSLock.lock { counter.value += 1 }
                }
            }
        }
        #expect(counter.value == 500)
    }

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
