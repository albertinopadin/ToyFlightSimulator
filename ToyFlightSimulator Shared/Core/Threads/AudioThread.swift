//
//  AudioThread.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/29/25.
//

final class AudioThread: TFSThread {
    override func main() {
        AudioManager.StartGameMusic()
    }
}
