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
    
    public static func getLightObjects() -> [LightObject] {
        return _currentScene.lightManager.lightObjects
    }
    
    public static func SetSceneConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.setSceneConstants(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func Render(renderCommandEncoder: MTLRenderCommandEncoder, renderPipelineStateType: RenderPipelineStateType) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
        _currentScene.render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: renderPipelineStateType)
    }
    
    public static func RenderShadows(renderCommandEncoder: MTLRenderCommandEncoder, shadowViewProjectionMatrix: float4x4) {
        _currentScene.renderShadow(renderCommandEncoder: renderCommandEncoder,
                                   shadowViewProjectionMatrix: shadowViewProjectionMatrix)
    }
    
    public static func RenderDepth(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.lightManager.setLightData(renderCommandEncoder)
        _currentScene.renderDepth(renderCommandEncoder: renderCommandEncoder)
    }
}
