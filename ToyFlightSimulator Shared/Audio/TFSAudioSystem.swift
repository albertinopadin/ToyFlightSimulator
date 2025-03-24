//
//  TFSAudioSystem.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 3/20/25.
//

import Foundation
import AVFoundation

public class TFSAudioSystem {
    private let audioEngine: AVAudioEngine
    private let audioPlayer: AVAudioPlayerNode
    
    public init() {
        self.audioEngine = AVAudioEngine()
        self.audioPlayer = AVAudioPlayerNode()
    }
    
    public func play(url: URL) {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let fileFormat = audioFile.processingFormat
            
            
            // Configure Audio Engine
            audioEngine.attach(audioPlayer)
            audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: fileFormat)
            
            audioEngine.prepare()
            
            do {
                try audioEngine.start()
            } catch {
                print("[TFSAudioSystem] Failed to start audio engine; error: \(error.localizedDescription)")
            }
            
            audioPlayer.scheduleFile(audioFile, at: nil) {
                // Completion block
                print("File \(url.path()) has been scheduled.")
            }
            
            audioPlayer.play()
        } catch {
            print("Error reading audio file at URL: \(url.path()); error: \(error.localizedDescription)")
        }
    }
    
    public func play(filename: String, fileExtension: String = "mp3") {
        guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
          return
        }
        
        play(url: fileURL)
    }
    
    public func stop() {
        audioPlayer.stop()
    }
    
    public func setVolume(_ volume: Float) {
        audioPlayer.volume = volume
    }
}
