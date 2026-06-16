//
//  PendingAircraftSwap.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 6/16/26.
//

import os

/// Thread-safe single-slot mailbox for deferring a player-aircraft swap from
/// the UI thread to the update thread.
///
/// The SwiftUI menu callback runs on the main thread, but the scene graph,
/// physics world, and `SceneManager` registries it would mutate are owned by
/// the `UpdateThread`. Rather than mutate them cross-thread (safe today only
/// by the implicit "rendering runs on the main thread" invariant), the
/// callback `request(_:)`s a swap here and the scene's `doUpdate` — already on
/// the update thread — `take()`s it and applies it at a safe point.
///
/// The lock makes the hand-off race-free regardless of which thread rendering
/// runs on. Contention is limited to swap events (a menu selection), so it
/// never touches the per-frame hot path.
final class PendingAircraftSwap: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var pending: AircraftType?

    /// Records a swap request. Most recent wins — if several requests arrive
    /// before the update thread consumes one, only the latest is applied.
    /// Called from the UI thread.
    func request(_ aircraft: AircraftType) {
        withLock(lock) { pending = aircraft }
    }

    /// Returns and clears the pending request, or `nil` if none is queued.
    /// Consumption is atomic: a given request is delivered exactly once.
    /// Called from the update thread.
    func take() -> AircraftType? {
        withLock(lock) {
            let aircraft = pending
            pending = nil
            return aircraft
        }
    }
}
