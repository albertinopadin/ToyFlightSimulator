//
//  PendingSceneResetTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 7/8/26.
//

import Testing
@testable import ToyFlightSimulator

// MARK: - PendingSceneReset (UI → update-thread hand-off)

@Suite("PendingSceneReset", .tags(.scenes))
struct PendingSceneResetTests {

    @Test("take() on an empty latch returns false")
    func emptyTakeIsFalse() {
        let latch = PendingSceneReset()
        #expect(latch.take() == false)
    }

    @Test("A requested reset is returned by the next take()")
    func requestThenTake() {
        let latch = PendingSceneReset()
        latch.request()
        #expect(latch.take() == true)
    }

    @Test("A request is delivered exactly once — the second take() is false")
    func takeConsumesTheRequest() {
        let latch = PendingSceneReset()
        latch.request()
        #expect(latch.take() == true)
        #expect(latch.take() == false)
    }

    @Test("Coalescing: several requests before a take collapse into one reset")
    func repeatedRequestsCoalesce() {
        let latch = PendingSceneReset()
        latch.request()
        latch.request()
        latch.request()
        #expect(latch.take() == true)
        #expect(latch.take() == false)
    }

    @Test("Concurrent requests and takes never tear or crash",
          .tags(.concurrency),
          .timeLimit(.minutes(1)))
    func concurrentAccessIsSafe() async {
        let latch = PendingSceneReset()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2_000 {
                group.addTask { latch.request() }
                group.addTask { _ = latch.take() }
            }
        }

        // Drain: after the storm at most one request remains latched, and the
        // latch is empty thereafter.
        _ = latch.take()
        #expect(latch.take() == false)
    }
}
