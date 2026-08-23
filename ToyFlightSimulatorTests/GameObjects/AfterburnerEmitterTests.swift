//
//  AfterburnerEmitterTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 8/23/26.
//

import Testing
import Foundation
@testable import ToyFlightSimulator

/// Afterburner pools must be per-instance: a shared (static) emitter makes
/// the simulation integrate n·dt per frame with n instances live, lets one
/// nozzle's off() reset every other nozzle, and carries a full plume across
/// scene teardowns and aircraft swaps (the pool outlives its objects).
/// App-hosted only: constructing an Afterburner reaches Assets.Models[.None]
/// and Engine.Device.makeBuffer — but nothing here touches Engine.renderer,
/// so the host-app launch race doesn't apply.
/// See code_reviews/claude/particle_remaining_issues_plan_2026-08-23.md.
@Suite("Afterburner per-instance emitter", .tags(.gameObjects))
struct AfterburnerEmitterTests {
    @Test("two instances own distinct emitters (no shared pool)")
    func emittersAreDistinct() {
        let left = Afterburner(name: "left")
        let right = Afterburner(name: "right")
        #expect(left.emitter !== right.emitter)
        #expect(left.emitter.particleBuffer !== right.emitter.particleBuffer)
    }
    
    @Test("a fresh instance starts with an empty pool even after another has emitted")
    func freshInstanceStartsEmpty() {
        // Models the teardown → rebuild (and aircraft-swap) path: the old
        // scene's afterburner has a populated pool; the new scene's must not
        // inherit it. Under the old shared static this read 40, not 0.
        let oldScene = Afterburner(name: "old scene afterburner")
        oldScene.emitter.emit()
        #expect(oldScene.emitter.currentParticles > 0)
        
        let newScene = Afterburner(name: "new scene afterburner")
        #expect(newScene.emitter.currentParticles == 0)
    }
}
