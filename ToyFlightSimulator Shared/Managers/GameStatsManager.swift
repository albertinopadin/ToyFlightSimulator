//
//  GameStatsManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/5/24.
//

import Foundation

final class GameStatsManager: ObservableObject {
    static let sharedInstance = GameStatsManager()
    
    @Published public var rollingAverageFPS: Double = 0.0
    
    private let maxFrames = 60
    private var frame = 0
    private var lastXFrameDeltaTime = [Double]()
    
    private init() {}
    
    // TODO: Optimize this method using a true ring buffer (or better data structure)
    public func recordDeltaTime(_ deltaTime: Double) {
        if lastXFrameDeltaTime.count >= maxFrames {
            lastXFrameDeltaTime.removeFirst()
        }
        
        lastXFrameDeltaTime.append(deltaTime)
        
        frame += 1
        
        if frame >= maxFrames {
            let avgDeltaTime: Double = lastXFrameDeltaTime.reduce(0.0) { $0 + $1 } / Double(maxFrames)
            rollingAverageFPS = 1 / avgDeltaTime
            frame = 0
        }
    }
}
