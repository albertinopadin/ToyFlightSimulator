//
//  Preferences.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit
import Foundation

public enum ClearColors {
    static let White     = MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    static let Green     = MTLClearColor(red: 0.22, green: 0.55, blue: 0.34, alpha: 1.0)
    static let Grey      = MTLClearColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    static let DarkGrey  = MTLClearColor(red: 0.01, green: 0.01, blue: 0.01, alpha: 1.0)
    static let Black     = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    static let LimeGreen = MTLClearColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1.0)
    static let SkyBlue   = MTLClearColor(red: 0.3, green: 0.4, blue: 0.8, alpha: 1.0)
}

// TODO: Think about how to properly model Game preferences (Graphics, Starting Scene, etc)
struct Preferences {
    public static let ClearColor: MTLClearColor = ClearColors.Black
    
    public static let MainPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
//    public static var MainPixelFormat: MTLPixelFormat = .bgra8Unorm
    
    public static let MainDepthPixelFormat: MTLPixelFormat = .depth32Float

    public static let MainDepthStencilPixelFormat: MTLPixelFormat = .depth32Float_stencil8

    /// Depth value to clear the main-camera depth buffer to. We use reverse-Z
    /// projection (see `Transform.perspectiveProjection`), where `near` maps to 1.0
    /// and `far` maps to 0.0. Clearing to 0.0 means "nothing is in front yet";
    /// any rasterized fragment will be closer than the cleared value.
    public static let MainClearDepth: Double = 0.0
    
//    public static let StartingSceneType: SceneType = .Sandbox
//    public static let StartingSceneType: SceneType = .FreeCamFlightbox
//    public static let StartingSceneType: SceneType = .Flightbox
//    public static let StartingSceneType: SceneType = .BallPhysics
//    public static let StartingSceneType: SceneType = .PhysicsStressTest
//    public static let StartingSceneType: SceneType = .FlightboxWithTerrain
    public static let StartingSceneType: SceneType = .FlightboxWithPhysics
    
    public static let PlayMusicOnStartup: Bool = false

    // MARK: - Persisted graphics settings

    private static let maxAnisotropyKey = "graphics.maxAnisotropy"

    /// Factory default used when the player hasn't chosen an anisotropy level yet.
    public static let DefaultMaxAnisotropy: MaxAnisotropy = .x8

    /// Player-selected max anisotropy for the linear texture sampler, persisted
    /// across launches via UserDefaults. Reads fall back to `DefaultMaxAnisotropy`
    /// when unset or if a stored value is no longer a valid level. Both the engine
    /// (SamplerStateLibrary.makeLibrary) and the menu seed from this at launch.
    public static var SelectedMaxAnisotropy: MaxAnisotropy {
        get {
            MaxAnisotropy(rawValue: UserDefaults.standard.integer(forKey: maxAnisotropyKey))
                ?? DefaultMaxAnisotropy
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: maxAnisotropyKey)
        }
    }
}

// MARK: - Debug logging flags
//
// Top-level Bool constants passed to `DebugLog(_:_:)` to gate per-subsystem
// console spam. Flip to `true` to enable; leave at `false` for normal runs.
// Each flag is scoped to a single subsystem so multiple can be enabled
// independently while debugging an interaction.

public let DEBUG_FORCES:        Bool = false  // F22SimpleFlightModel.computeForce summary per frame
public let DEBUG_LIFT:          Bool = false  // F22SimpleFlightModel.calculateLiftData per frame
public let DEBUG_NODE_ROTATION: Bool = false  // Node.rotationMatrix setter writes
