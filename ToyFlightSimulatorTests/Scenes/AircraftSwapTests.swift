//
//  AircraftSwapTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 6/16/26.
//

import Testing
import simd
@testable import ToyFlightSimulator

// MARK: - PendingAircraftSwap (UI → update-thread hand-off)

@Suite("PendingAircraftSwap", .tags(.scenes))
struct PendingAircraftSwapTests {

    @Test("take() on an empty mailbox returns nil")
    func emptyTakeIsNil() {
        let mailbox = PendingAircraftSwap()
        #expect(mailbox.take() == nil)
    }

    @Test("A requested swap is returned by the next take()")
    func requestThenTake() {
        let mailbox = PendingAircraftSwap()
        mailbox.request(.f18)
        #expect(mailbox.take() == .f18)
    }

    @Test("A request is delivered exactly once — the second take() is nil")
    func takeConsumesTheRequest() {
        let mailbox = PendingAircraftSwap()
        mailbox.request(.f22)
        #expect(mailbox.take() == .f22)
        #expect(mailbox.take() == nil)
    }

    @Test("Coalescing: when several requests arrive before a take, the latest wins")
    func latestRequestWins() {
        let mailbox = PendingAircraftSwap()
        mailbox.request(.f16)
        mailbox.request(.f35)
        mailbox.request(.f22_cgtrader)
        #expect(mailbox.take() == .f22_cgtrader)
        #expect(mailbox.take() == nil)
    }

    @Test("Concurrent requests and takes never tear or crash",
          .tags(.concurrency),
          .timeLimit(.minutes(1)))
    func concurrentAccessIsSafe() async {
        let mailbox = PendingAircraftSwap()
        let cases = AircraftType.allCases

        await withTaskGroup(of: AircraftType?.self) { group in
            for i in 0..<2_000 {
                group.addTask { mailbox.request(cases[i % cases.count]); return nil }
                group.addTask { mailbox.take() }
            }
            // Every value ever observed must be a whole, valid case (no torn reads).
            for await taken in group {
                if let taken {
                    #expect(cases.contains(taken))
                }
            }
        }

        // Drain: after the storm a final take yields a valid case or nil, and
        // the slot is empty thereafter.
        let leftover = mailbox.take()
        if let leftover {
            #expect(cases.contains(leftover))
        }
        #expect(mailbox.take() == nil)
    }
}

// MARK: - Entity bookkeeping for an aircraft swap

@Suite("Aircraft entity swap", .tags(.scenes, .physics))
struct AircraftEntitySwapTests {

    /// Distinct, Metal-free rigid bodies standing in for aircraft / ground.
    private func body() -> RigidBody { TestRigidBody() }

    @Test("With no previous aircraft, the new body is appended")
    func firstSwapAppends() {
        let ground = body()
        let aircraft = body()

        let result = FlightboxWithPhysics.swappedEntities([ground],
                                                          removing: nil,
                                                          adding: aircraft)

        #expect(result.count == 2)
        #expect(result.contains { $0 === ground })
        #expect(result.contains { $0 === aircraft })
    }

    @Test("Swapping removes the previous aircraft body and adds the new one")
    func swapReplacesPreviousBody() {
        let ground = body()
        let oldAircraft = body()
        let newAircraft = body()

        let result = FlightboxWithPhysics.swappedEntities([ground, oldAircraft],
                                                          removing: oldAircraft,
                                                          adding: newAircraft)

        #expect(result.count == 2)
        #expect(result.contains { $0 === ground })
        #expect(result.contains { $0 === newAircraft })
        #expect(!result.contains { $0 === oldAircraft })
    }

    @Test("Repeated swaps never accumulate stale aircraft bodies")
    func repeatedSwapsDoNotAccumulate() {
        let ground = body()
        let acA = body()
        let acB = body()
        let acC = body()

        // Mirror the scene loop: each swap removes the body added by the last.
        var entities: [RigidBody] = [ground]
        entities = FlightboxWithPhysics.swappedEntities(entities, removing: nil, adding: acA)
        entities = FlightboxWithPhysics.swappedEntities(entities, removing: acA, adding: acB)
        entities = FlightboxWithPhysics.swappedEntities(entities, removing: acB, adding: acC)

        #expect(entities.count == 2)
        #expect(entities.contains { $0 === ground })
        #expect(entities.contains { $0 === acC })
        #expect(!entities.contains { $0 === acA })
        #expect(!entities.contains { $0 === acB })
    }

    @Test("Removing a body that isn't present still appends the new one (no crash)")
    func removingAbsentBodyJustAppends() {
        let ground = body()
        let strayAircraft = body()   // never added to the list
        let newAircraft = body()

        let result = FlightboxWithPhysics.swappedEntities([ground],
                                                          removing: strayAircraft,
                                                          adding: newAircraft)

        #expect(result.count == 2)
        #expect(result.contains { $0 === ground })
        #expect(result.contains { $0 === newAircraft })
    }

    @Test("Identity comparison removes only the matching instance, not equal-valued ones")
    func removalIsByIdentity() {
        let ground = body()
        let oldAircraft = body()
        let otherDynamic = body()
        let newAircraft = body()

        let result = FlightboxWithPhysics.swappedEntities([ground, oldAircraft, otherDynamic],
                                                          removing: oldAircraft,
                                                          adding: newAircraft)

        // Only oldAircraft removed; the unrelated dynamic body survives.
        #expect(result.count == 3)
        #expect(result.contains { $0 === otherDynamic })
        #expect(!result.contains { $0 === oldAircraft })
    }
}
