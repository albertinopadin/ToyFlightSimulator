//
//  Afterburner.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/16/24.
//

import MetalKit

final class Afterburner: ParticleEmitterObject {
    init(name: String) {
        // Per-instance emitter (same pattern as Fire): each nozzle owns its
        // pool and buffer, so the simulation advances exactly 1·deltaTime per
        // frame no matter how many afterburners are live, off() resets only
        // this nozzle, and the pool dies with the object at scene teardown /
        // aircraft swap instead of carrying a full plume into the next scene.
        // (A shared static emitter caused all three — see
        // code_reviews/claude/particle_remaining_issues_plan_2026-08-23.md.)
        let afterburnerEmitter = ParticleEmitter.afterburner(size: CGSize(width: 20, height: 20))
        super.init(name: name, emitter: afterburnerEmitter)
    }
    
    func on() {
        self.shouldEmit = true
    }
    
    func off() {
        self.shouldEmit = false
        self.emitter.reset()
    }
}
