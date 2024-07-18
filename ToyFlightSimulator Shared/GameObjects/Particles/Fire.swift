//
//  Fire.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/24/24.
//

import MetalKit

class Fire: ParticleEmitterObject {
    init(name: String) {
        super.init(name: name, emitter: ParticleEmitter.fire(size: CGSize(width: 80, height: 80)))
    }
}
