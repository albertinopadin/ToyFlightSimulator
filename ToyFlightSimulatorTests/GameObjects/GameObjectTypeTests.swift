//
//  GameObjectTypeTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 7/7/26.
//

import Testing
@testable import ToyFlightSimulator

/// `GameObjectType.isManagedBySceneManager` is the single gate deciding
/// whether Register/Unregister track an object at all. `.none` must be the
/// only unmanaged case — every other case maps to a batched collection and
/// relies on the registration-marker cycle (and its double-register assert).
@Suite("GameObjectType SceneManager management", .tags(.gameObjects))
struct GameObjectTypeTests {

    @Test(".none is the unmanaged case")
    func noneIsUnmanaged() {
        #expect(!GameObjectType.none.isManagedBySceneManager)
    }

    @Test("every batched case is managed", arguments: [
        GameObjectType.sky,
        .icosahedrons,
        .lines,
        .particles,
        .tessellatables,
        .renderables(transparent: false),
        .renderables(transparent: true),
    ])
    func batchedCasesAreManaged(type: GameObjectType) {
        #expect(type.isManagedBySceneManager)
    }
}
