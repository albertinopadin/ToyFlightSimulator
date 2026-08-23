//
//  UpdateThread.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/29/25.
//

import Foundation

final class UpdateThread: TFSThread {
    public let updateSemaphore = DispatchSemaphore(value: 0)
    /// Signaled after the update finishes writing ring buffer + scene constants,
    /// so the render thread knows it can safely read the freshly written data.
    public let updateDoneSemaphore = DispatchSemaphore(value: 0)
    private var updatePreviousTime: UInt64 = 0

    /// Longest wall-clock gap a single tick may integrate. The thread parks
    /// whenever rendering stops (menu pause via metalView.isPaused, window
    /// occlusion, the debugger) and updatePreviousTime goes stale, so the
    /// first tick after resume would otherwise integrate the entire gap —
    /// the whole pause as one physics/particle step, and on the first-ever
    /// tick the machine's uptime since boot (DispatchTime uptime counts from
    /// boot and updatePreviousTime starts at 0). 100 ms = 3 frames at the
    /// slowest supported refresh rate (FPS_30): real hitches pass through
    /// untouched, stalls are truncated to a normal-sized step. Stalled time
    /// is dropped, not carried — the clock still advances to now.
    private static let maxDeltaTime: Double = 0.1

    override func main() {
        while true {
            _ = updateSemaphore.wait(timeout: .distantFuture)

            let currentTime = DispatchTime.now().uptimeNanoseconds
            let updateDeltaTime = min(Double(currentTime - updatePreviousTime) / 1e9, Self.maxDeltaTime)
            updatePreviousTime = currentTime
            SceneManager.Update(deltaTime: updateDeltaTime)
            GameStatsManager.sharedInstance.sceneUpdated()
            updateDoneSemaphore.signal()
        }
    }
}
