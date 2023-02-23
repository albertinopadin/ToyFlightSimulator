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
}

class SceneManager {
    private static var _currentScene: Scene!
    
    public static func SetScene(_ sceneType: SceneType) {
        switch sceneType {
        case .Sandbox:
            _currentScene = SandboxScene(name: "Sandbox")
        case .Flightbox:
            _currentScene = FlightboxScene(name: "Flightbox")
        }
    }
    
    public static func Update(deltaTime: Float) {
        GameTime.UpdateTime(deltaTime)
        _currentScene.updateCameras(deltaTime: deltaTime)
        _currentScene.update()
    }
    
    public static func SetSceneConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.setSceneConstants(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func SetDirectionalLightConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.setDirectionalLightConstants(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func SetPointLightConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.setPointLightConstants(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func SetLightData(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.setLightData(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func Render(renderCommandEncoder: MTLRenderCommandEncoder,
                              renderPipelineStateType: RenderPipelineStateType,
                              applyMaterials: Bool = true) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
        _currentScene.render(renderCommandEncoder: renderCommandEncoder,
                             renderPipelineStateType: renderPipelineStateType,
                             applyMaterials: applyMaterials)
    }
    
    public static func RenderGBuffer(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.GBufferGenerationBase])
        _currentScene.renderGBuffer(renderCommandEncoder: renderCommandEncoder, gBufferRPS: .GBufferGenerationBase)
        
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.GBufferGenerationMaterial])
        _currentScene.renderGBuffer(renderCommandEncoder: renderCommandEncoder, gBufferRPS: .GBufferGenerationMaterial)
    }
    
    public static func RenderShadows(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.renderShadows(renderCommandEncoder: renderCommandEncoder)
    }
}
