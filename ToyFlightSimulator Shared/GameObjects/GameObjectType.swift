//
//  GameObjectType.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/4/26.
//

/// The registration category of a GameObject — which SceneManager collection it
/// batches into. This is the single source of truth consulted by BOTH
/// `SceneManager.Register` and `SceneManager.Unregister`: `add(_:to:)` and
/// `remove(_:from:)` switch exhaustively over these cases with NO `default`,
/// so adding a case here without handling both directions is a compile error.
enum GameObjectType {
    /// Not batched by SceneManager (cameras; lights live in LightManager).
    case none
    /// The singleton sky slot (`skyData`). Reset wholesale in TeardownScene.
    case sky
    case icosahedrons
    case lines
    case particles
    case tessellatables
    /// `modelDatas` / `transparentObjectDatas`, split by `transparent`.
    case renderables(transparent: Bool)
}
