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
    
//    public static func Render(renderCommandEncoder: MTLRenderCommandEncoder) {
//        _currentScene.render(renderCommandEncoder: renderCommandEncoder)
//    }
    
    //case Base
    //case Material
    //case Instanced
    //case SkySphere
    //case Opaque
    //case OpaqueMaterial
    
//    public static func RenderOpaque(renderCommandEncoder: MTLRenderCommandEncoder) {
////        _currentScene
//        _currentScene.renderOpaque(renderCommandEncoder: renderCommandEncoder)
//    }
//
//    public static func RenderTransparent(renderCommandEncoder: MTLRenderCommandEncoder) {
//        _currentScene.renderTransparent(renderCommandEncoder: renderCommandEncoder)
//    }
    
    public static func SetSceneConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.setSceneConstants(renderCommandEncoder: renderCommandEncoder)
    }
    
    public static func Render(renderCommandEncoder: MTLRenderCommandEncoder, renderPipelineStateType: RenderPipelineStateType) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
        _currentScene.render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: renderPipelineStateType)
    }
}
