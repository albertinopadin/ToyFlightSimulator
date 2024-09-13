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
        
        switch sceneType {
            case .Sandbox:
                CurrentScene = SandboxScene(name: "Sandbox", rendererType: rendererType)
            case .Flightbox:
                CurrentScene = FlightboxScene(name: "Flightbox", rendererType: rendererType)
            case .FreeCamFlightbox:
                CurrentScene = FreeCamFlightboxScene(name: "FreeCamFlightbox", rendererType: rendererType)
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
    
    public static func Render(with renderEncoder: MTLRenderCommandEncoder,
                              renderPipelineStateType: RenderPipelineStateType,
                              applyMaterials: Bool = true,
                              withTransparency: Bool = false) {
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
        CurrentScene?.render(with: renderEncoder,
                             renderPipelineStateType: renderPipelineStateType,
                             applyMaterials: applyMaterials,
                             withTransparency: withTransparency)
    }
    
    public static func RenderGBuffer(with renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredGBufferBase])
        CurrentScene?.renderGBuffer(with: renderEncoder, gBufferRPS: .SinglePassDeferredGBufferBase)
        
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredGBufferMaterial])
        CurrentScene?.renderGBuffer(with: renderEncoder, gBufferRPS: .SinglePassDeferredGBufferMaterial)
    }
    
    public static func RenderTiledDeferredGBuffer(with renderEncoder: MTLRenderCommandEncoder) {
        // TODO: Take material into account:
        CurrentScene?.renderTiledDeferredGBuffer(with: renderEncoder)
    }
    
    public static func RenderShadows(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.renderShadows(with: renderEncoder)
    }
    
    public static func RenderPointLightMeshes(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.renderPointLightMeshes(with: renderEncoder)
    }
    
    public static func RenderPointLights(with renderEncoder: MTLRenderCommandEncoder) {
        CurrentScene?.renderPointLights(with: renderEncoder)
    }
    
    public static func Compute(with computeEncoder: MTLComputeCommandEncoder, threadsPerGroup: MTLSize) {
        CurrentScene?.compute(with: computeEncoder, threadsPerGroup: threadsPerGroup)
    }
    
    public static func SetAspectRatio(_ aspectRatio: Float) {
        CurrentScene?.setAspectRatio(aspectRatio)
    }
}
