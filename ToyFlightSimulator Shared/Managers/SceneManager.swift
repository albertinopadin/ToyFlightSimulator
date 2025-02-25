//
//  SceneManager.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum SceneType {
    case Sandbox
    case Flightbox
    case FreeCamFlightbox
    case BallPhysics
}

final class SceneManager {
    public static var CurrentScene: GameScene?
    
    private static var _paused: Bool = false
    public static var Paused: Bool {
        get {
            return _paused
        }
        
        set {
            _paused = newValue
            _view?.isPaused = newValue
        }
    }
    
    private static var _sceneType: SceneType?
    private static var _view: MTKView?
    private static var _rendererType: RendererType?
    
    public static func SetScene(_ sceneType: SceneType, mtkView: MTKView, rendererType: RendererType) {
        _sceneType = sceneType
        _view = mtkView
        _rendererType = rendererType
        
        // TODO: Is there a more elegant way to do this ???
        switch sceneType {
            case .Sandbox:
                CurrentScene = SandboxScene(name: "Sandbox", rendererType: rendererType)
            case .Flightbox:
                CurrentScene = FlightboxScene(name: "Flightbox", rendererType: rendererType)
            case .FreeCamFlightbox:
                CurrentScene = FreeCamFlightboxScene(name: "FreeCamFlightbox", rendererType: rendererType)
            case .BallPhysics:
                CurrentScene = BallPhysicsScene(name: "BallPhysicsSandbox", rendererType: rendererType)
        }
    }
    
    public static func ResetScene() {
        if let _sceneType, let _view, let _rendererType {
            SetScene(_sceneType, mtkView: _view, rendererType: _rendererType)
        }
    }
    
    public static func TeardownScene() {
        CurrentScene?.teardownScene()
        _sceneType = nil
        _view = nil
        _rendererType = nil
    }
    
    public static func Update(deltaTime: Double) {
        if !Paused {
            GameTime.UpdateTime(deltaTime)
            CurrentScene?.updateCameras(deltaTime: deltaTime)
            CurrentScene?.update()
        }
    }
    
    public static func SetSceneConstants(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setSceneConstants(with: renderEncoder)
    }
    
    public static func SetDirectionalLightConstants(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setDirectionalLightConstants(with: renderEncoder)
    }
    
    public static func SetPointLightConstants(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setPointLightConstants(with: renderEncoder)
    }
    
    public static func SetDirectionalLightData(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setDirectionalLightData(with: renderEncoder)
    }
    
    public static func SetPointLightData(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.setPointLightData(with: renderEncoder)
    }
    
    public static func SetAspectRatio(_ aspectRatio: Float) {
        CurrentScene?.setAspectRatio(aspectRatio)
    }
    
    // TODO: Perhaps should have a ComputeMgr?
    public static func Compute(with computeEncoder: MTLComputeCommandEncoder, threadsPerGroup: MTLSize) {
        CurrentScene?.compute(with: computeEncoder, threadsPerGroup: threadsPerGroup)
    }
}
