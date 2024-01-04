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
    
    public static func Update(deltaTime: Float) {
        if !paused {
            GameTime.UpdateTime(deltaTime)
            currentScene?.updateCameras(deltaTime: deltaTime)
            currentScene?.update()
        }
    }
    
    public static func SetSceneConstants(with renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.setSceneConstants(with: renderCommandEncoder)
    }
    
    public static func SetDirectionalLightConstants(with renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.setDirectionalLightConstants(with: renderCommandEncoder)
    }
    
    public static func SetPointLightConstants(with renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.setPointLightConstants(with: renderCommandEncoder)
    }
    
    public static func SetDirectionalLightData(with renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.setDirectionalLightData(with: renderCommandEncoder)
    }
    
    public static func SetPointLightData(with renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.setPointLightData(with: renderCommandEncoder)
    }
    
    public static func Render(with renderCommandEncoder: MTLRenderCommandEncoder,
                              renderPipelineStateType: RenderPipelineStateType,
                              applyMaterials: Bool = true) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
        currentScene?.render(with: renderCommandEncoder,
                             renderPipelineStateType: renderPipelineStateType,
                             applyMaterials: applyMaterials)
    }
    
    public static func RenderGBuffer(with renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.GBufferGenerationBase])
        currentScene?.renderGBuffer(with: renderCommandEncoder, gBufferRPS: .GBufferGenerationBase)
        
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.GBufferGenerationMaterial])
        currentScene?.renderGBuffer(with: renderCommandEncoder, gBufferRPS: .GBufferGenerationMaterial)
    }
    
    public static func RenderShadows(with renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.renderShadows(with: renderCommandEncoder)
    }
    
    public static func RenderPointLightMeshes(with renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.render(with: renderCommandEncoder, renderPipelineStateType: .LightMask)
    }
    
    public static func RenderPointLights(with renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.render(with: renderCommandEncoder, renderPipelineStateType: .PointLight)
    }
    
    public static func SetAspectRatio(_ aspectRatio: Float) {
        currentScene?.setAspectRatio(aspectRatio)
    }
}
