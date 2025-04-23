//
//  TFSAudioSystem.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 3/20/25.
//

import Foundation
@preconcurrency import AVFoundation

public final class TFSAudioSystem: @unchecked Sendable {
    private let audioEngine: AVAudioEngine
    private let audioPlayer: AVAudioPlayerNode
    
    public init() {
        self.audioEngine = AVAudioEngine()
        self.audioPlayer = AVAudioPlayerNode()
        
        audioEngine.attach(audioPlayer)
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: nil)
        audioEngine.prepare()
    }
    
    public func start() {
        print("[TFSAudioSystem] Starting audio engine...")
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("[TFSAudioSystem] Failed to start audio engine; error: \(error.localizedDescription)")
                return
            }
        }
        print("[TFSAudioSystem] Audio engine started.")
    }
    
    private func scheduleFile(url: URL) {
        print("[TFSAudioSystem] Scheduling audio file URL: \(url.lastPathComponent)")
        do {
            let audioFile = try AVAudioFile(forReading: url)
            audioPlayer.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                print("File \(url.lastPathComponent) has finished playing.")
            }
        } catch {
            print("[TFSAudioSystem] Error reading audio file at URL: \(url.path()); error: \(error.localizedDescription)")
            return
        }
        
        print("[TFSAudioSystem] File URL \(url.lastPathComponent) scheduled for playback.")
    }
    
    private func play(url: URL) {
        self.stop()
        
        scheduleFile(url: url)
        
        print("[TFSAudioSystem] Playing audio URL: \(url.lastPathComponent)...")
        audioPlayer.play()
    }
    
    public func play(filename: String, fileExtension: String = "mp3") {
        guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
            print("[TFSAudioSystem] Could not find audio file: \(filename).\(fileExtension)")
            return
        }
        
        play(url: fileURL)
    }
    
    public func stop() {
        if audioPlayer.isPlaying {
            print("[TFSAudioSystem] Stopping audio playback and resetting player...")
            audioPlayer.stop()
            audioPlayer.reset()
        }
    }
    
    public func setVolume(_ volume: Float) {
        audioPlayer.volume = max(0.0, min(1.0, volume))
    }
    
    deinit {
        if audioEngine.isRunning {
            self.stop()
            audioEngine.stop()
        }
    }
}
