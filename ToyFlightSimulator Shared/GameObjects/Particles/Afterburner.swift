//
//  Afterburner.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/16/24.
//

import MetalKit

final class Afterburner: ParticleEmitterObject {
    static let afterburnerEmitter = ParticleEmitter.afterburner(size: CGSize(width: 40, height: 40))
                                                                
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
