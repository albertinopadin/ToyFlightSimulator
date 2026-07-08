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
    /// `Register`/`Unregister` ignore these entirely — no collection, no
    /// registration marker — so `.none` objects may be re-added or reparented
    /// freely (e.g. the persistent AttachedCamera on aircraft swaps).
    case none
    /// The singleton sky slot (`skyData`). Reset wholesale in TeardownScene.
    case sky
    case icosahedrons
    case lines
    case particles
    case tessellatables
    /// `modelDatas` / `transparentObjectDatas`, split by `transparent`.
    case renderables(transparent: Bool)

    /// Whether SceneManager tracks objects of this type at all. `.none` is
    /// the single unmanaged case; every other case maps to a batched
    /// collection and participates in the register/unregister marker cycle.
    var isManagedBySceneManager: Bool {
        if case .none = self { return false }
        return true
    }
}
