//
//  UpdateThread.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/29/25.
//

import Foundation

final class UpdateThread: TFSThread {
    public let updateSemaphore = DispatchSemaphore(value: 0)
    private var updatePreviousTime: UInt64 = 0
    
    override func main() {
        while true {
            _ = updateSemaphore.wait(timeout: .distantFuture)
            
            let currentTime = DispatchTime.now().uptimeNanoseconds
            let updateDeltaTime = Double(currentTime - updatePreviousTime) / 1e9
            updatePreviousTime = currentTime
            SceneManager.Update(deltaTime: updateDeltaTime)
            GameStatsManager.sharedInstance.sceneUpdated()
        }
    }
}
