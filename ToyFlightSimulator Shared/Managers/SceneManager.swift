//
//  SceneManager.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum SceneType {
    case Sandbox
}

class SceneManager {
    private static var _currentScene: Scene!
    
    public static func SetScene(_ sceneType: SceneType) {
        switch sceneType {
        case .Sandbox:
            _currentScene = SandboxScene(name: "Sandbox")
        }
    }
    
    public static func Update(deltaTime: Float) {
        GameTime.UpdateTime(deltaTime)
        _currentScene.updateCameras(deltaTime: deltaTime)
        _currentScene.update()
    }
    
    public static func Render(renderCommandEncoder: MTLRenderCommandEncoder) {
        _currentScene.render(renderCommandEncoder: renderCommandEncoder)
    }
}
