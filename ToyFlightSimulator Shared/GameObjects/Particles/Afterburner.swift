//
//  Afterburner.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/16/24.
//

import MetalKit

class Afterburner: ParticleEmitterObject {
    init(name: String) {
        super.init(name: name, emitter: ParticleEmitter.afterburner(size: CGSize(width: 40, height: 40)))
    }
}
