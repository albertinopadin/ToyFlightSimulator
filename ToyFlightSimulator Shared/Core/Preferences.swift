//
//  Preferences.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

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
    
//    public static let StartingSceneType: SceneType = .Sandbox
//    public static let StartingSceneType: SceneType = .FreeCamFlightbox
    public static let StartingSceneType: SceneType = .Flightbox
//    public static let StartingSceneType: SceneType = .BallPhysics
    
    public static let PlayMusicOnStartup: Bool = false
}
