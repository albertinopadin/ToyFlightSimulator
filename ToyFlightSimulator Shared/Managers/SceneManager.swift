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

class SceneManager {
    public static var currentScene: GameScene?
    public static var paused: Bool = false
    
    private static var _sceneType: SceneType?
    private static var _rendererType: RendererType?
    
    public static func SetScene(_ sceneType: SceneType, rendererType: RendererType) {
        _sceneType = sceneType
        _rendererType = rendererType
        
        switch sceneType {
            case .Sandbox:
                currentScene = SandboxScene(name: "Sandbox", rendererType: rendererType)
            case .Flightbox:
                currentScene = FlightboxScene(name: "Flightbox", rendererType: rendererType)
            case .FreeCamFlightbox:
                currentScene = FreeCamFlightboxScene(name: "FreeCamFlightbox", rendererType: rendererType)
        }
    }
    
    public static func ResetScene() {
        if let _sceneType, let _rendererType {
            SetScene(_sceneType, rendererType: _rendererType)
        }
    }
    
    public static func Update(deltaTime: Double) {
        if !paused {
            GameTime.UpdateTime(deltaTime)
            currentScene?.updateCameras(deltaTime: deltaTime)
            currentScene?.update()
        }
    }
    
    public static func SetSceneConstants(with renderEncoder: MTLRenderCommandEncoder) {
        currentScene?.setSceneConstants(with: renderEncoder)
    }
    
    public static func SetDirectionalLightConstants(with renderEncoder: MTLRenderCommandEncoder) {
        currentScene?.setDirectionalLightConstants(with: renderEncoder)
    }
    
    public static func SetPointLightConstants(with renderEncoder: MTLRenderCommandEncoder) {
        currentScene?.setPointLightConstants(with: renderEncoder)
    }
    
    public static func SetDirectionalLightData(with renderEncoder: MTLRenderCommandEncoder) {
        currentScene?.setDirectionalLightData(with: renderEncoder)
    }
    
    public static func SetPointLightData(with renderEncoder: MTLRenderCommandEncoder) {
        currentScene?.setPointLightData(with: renderEncoder)
    }
    
    public static func Render(with renderEncoder: MTLRenderCommandEncoder,
                              renderPipelineStateType: RenderPipelineStateType,
                              applyMaterials: Bool = true) {
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
        currentScene?.render(with: renderEncoder,
                             renderPipelineStateType: renderPipelineStateType,
                             applyMaterials: applyMaterials)
    }
    
    public static func RenderGBuffer(with renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredGBufferBase])
        currentScene?.renderGBuffer(with: renderEncoder, gBufferRPS: .SinglePassDeferredGBufferBase)
        
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredGBufferMaterial])
        currentScene?.renderGBuffer(with: renderEncoder, gBufferRPS: .SinglePassDeferredGBufferMaterial)
    }
    
    public static func RenderTiledDeferredGBuffer(with renderEncoder: MTLRenderCommandEncoder) {
        // TODO: Take material into account:
        currentScene?.renderTiledDeferredGBuffer(with: renderEncoder)
    }
    
    public static func RenderShadows(with renderEncoder: MTLRenderCommandEncoder) {
        currentScene?.renderShadows(with: renderEncoder)
    }
    
    public static func RenderPointLightMeshes(with renderEncoder: MTLRenderCommandEncoder) {
        currentScene?.renderPointLightMeshes(with: renderEncoder)
    }
    
    public static func RenderPointLights(with renderEncoder: MTLRenderCommandEncoder) {
        currentScene?.renderPointLights(with: renderEncoder)
    }
    
    public static func Compute(with computeEncoder: MTLComputeCommandEncoder, threadsPerGroup: MTLSize) {
        currentScene?.compute(with: computeEncoder, threadsPerGroup: threadsPerGroup)
    }
    
    public static func SetAspectRatio(_ aspectRatio: Float) {
        currentScene?.setAspectRatio(aspectRatio)
    }
}
