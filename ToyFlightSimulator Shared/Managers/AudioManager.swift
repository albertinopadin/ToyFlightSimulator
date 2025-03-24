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
        audioSystem.play(filename: sunsetGlowTrack)
        audioSystem.setVolume(0.15)
    }
    
    public static func StopGameMusic() {
        audioSystem.stop()
    }
}
