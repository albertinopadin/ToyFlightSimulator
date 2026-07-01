//
//  AudioManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/22/25.
//

import Foundation

final class AudioManager {
    private static let audioSystem = TFSAudioSystem()
    private static let sunsetGlowTrack = "SunsetGlow"
    
    public static func StartGameMusic() {
        audioSystem.start()
        audioSystem.setVolume(0.15)
        audioSystem.play(filename: sunsetGlowTrack)
    }
    
    public static func StopGameMusic() {
        audioSystem.stop()
    }
    
    public static func SetVolume(_ volume: Float) {
        audioSystem.setVolume(volume)
    }

    public static func Prepare() {
        // Force the lazy AVAudioEngine graph to build here (off the main thread)
        // so the first volume change from the UI doesn't stall the main thread.
        _ = audioSystem
    }
}
