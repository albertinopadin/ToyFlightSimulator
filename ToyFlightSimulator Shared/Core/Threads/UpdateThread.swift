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

    override func main() {
        while true {
            _ = updateSemaphore.wait(timeout: .distantFuture)

            let currentTime = DispatchTime.now().uptimeNanoseconds
            let updateDeltaTime = Double(currentTime - updatePreviousTime) / 1e9
            updatePreviousTime = currentTime
            SceneManager.Update(deltaTime: updateDeltaTime)
            GameStatsManager.sharedInstance.sceneUpdated()
            updateDoneSemaphore.signal()
        }
    }
}
