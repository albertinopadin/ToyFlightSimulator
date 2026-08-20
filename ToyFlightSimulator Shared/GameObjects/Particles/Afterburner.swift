//
//  Afterburner.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/16/24.
//

import MetalKit

final class Afterburner: ParticleEmitterObject {
    // Shared by ALL Afterburner instances (the F-22 mounts two): one pool and
    // buffer, drawn once per instance at that instance's transform — but each
    // instance also dispatches the compute update, so the shared simulation
    // advances n·deltaTime per frame when n instances are live.
    static let afterburnerEmitter = ParticleEmitter.afterburner(size: CGSize(width: 20, height: 20))
                                                                
    init(name: String) {
        super.init(name: name, emitter: Self.afterburnerEmitter)
    }
    
    func on() {
        self.shouldEmit = true
    }
    
    func off() {
        self.shouldEmit = false
        self.emitter.reset()
    }
}
