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
    
    public static func SetSceneConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.setSceneConstants(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func SetDirectionalLightConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.setDirectionalLightConstants(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func SetPointLightConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.setPointLightConstants(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func SetLightData(renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.setLightData(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func Render(renderCommandEncoder: MTLRenderCommandEncoder,
                              renderPipelineStateType: RenderPipelineStateType,
                              applyMaterials: Bool = true) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
        currentScene?.render(renderCommandEncoder: renderCommandEncoder,
                             renderPipelineStateType: renderPipelineStateType,
                             applyMaterials: applyMaterials)
    }
    
    public static func RenderGBuffer(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.GBufferGenerationBase])
        currentScene?.renderGBuffer(renderCommandEncoder: renderCommandEncoder, gBufferRPS: .GBufferGenerationBase)
        
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.GBufferGenerationMaterial])
        currentScene?.renderGBuffer(renderCommandEncoder: renderCommandEncoder, gBufferRPS: .GBufferGenerationMaterial)
    }
    
    public static func RenderShadows(renderCommandEncoder: MTLRenderCommandEncoder) {
        currentScene?.renderShadows(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func SetAspectRatio(_ aspectRatio: Float) {
        currentScene?.setAspectRatio(aspectRatio)
    }
}
