//
//  PendingSceneReset.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/8/26.
//

import os

/// Thread-safe single-shot latch for deferring a scene reset from the UI
/// thread to the update thread — the reset counterpart of
/// `PendingAircraftSwap` (see that type for why mutating the scene graph
/// cross-thread is unsafe). The menus and the Cmd+R handler `request()` a
/// reset; `SceneManager.Update` — on the update thread — `take()`s it and
/// rebuilds the scene at the top of the tick.
///
/// Repeated requests before a take coalesce into a single reset. If a third
/// copy of this hand-off pattern ever appears, fold this and
/// `PendingAircraftSwap` into one generic mailbox.
final class PendingSceneReset: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var pending = false

    /// Records a reset request. Called from the UI thread.
    func request() {
        withLock(lock) { pending = true }
    }

    /// Returns whether a reset was requested and clears the latch.
    /// Consumption is atomic: a given request is delivered exactly once.
    /// Called from the update thread.
    func take() -> Bool {
        withLock(lock) {
            let wasPending = pending
            pending = false
            return wasPending
        }
    }
}
