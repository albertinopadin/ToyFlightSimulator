//
//  AudioThread.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/29/25.
//

import Foundation

final class AudioThread: TFSThread {
    private var shouldStartAudio: Bool = false
    override func main() {
        while !shouldStartAudio {
            Thread.sleep(forTimeInterval: 0.25)
        }
        
        AudioManager.StartGameMusic()
    }
    
    public func startAudio() {
        shouldStartAudio = true
    }
}
