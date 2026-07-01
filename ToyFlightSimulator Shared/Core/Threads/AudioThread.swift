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

        if Preferences.PlayMusicOnStartup {
            AudioManager.StartGameMusic()
        } else {
            // Still build the audio engine here so the first UI volume change is instant.
            AudioManager.Prepare()
        }
    }
    
    public func startAudio() {
        shouldStartAudio = true
    }
}
