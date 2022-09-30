//
//  Scene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

// Scene is head node of scene graph
class Scene: Node {
    private var _cameraManager = CameraManager()
    private var _lightManager = LightManager()
    private var _sceneConstants = SceneConstants()
    
    override init(name: String) {
        super.init(name: name)
        buildScene()
    }
    
    func buildScene() { }
    
    func addCamera(_ camera: Camera, _ isCurrentCamera: Bool = true) {
        _cameraManager.registerCamera(camera: camera)
        if (isCurrentCamera) {
            _cameraManager.setCamera(camera.cameraType)
        }
    }
    
    func addLight(_ lightObject: LightObject) {
        self.addChild(lightObject)
        _lightManager.addLightObject(lightObject)
    }
    
    func updateCameras(deltaTime: Float) {
        _cameraManager.update(deltaTime: deltaTime)
    }
    
    override func update() {
        _sceneConstants.viewMatrix = _cameraManager.currentCamera.viewMatrix
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0  // Remove x translation
        _sceneConstants.skyViewMatrix[3][1] = 0  // Remove y translation
        _sceneConstants.skyViewMatrix[3][2] = 0  // Remove z translation
//        print("_cameraManager.currentCamera.projectionMatrix: \(_cameraManager.currentCamera.projectionMatrix)")
        _sceneConstants.projectionMatrix = _cameraManager.currentCamera.projectionMatrix
        _sceneConstants.totalGameTime = GameTime.TotalGameTime
        _sceneConstants.cameraPosition = _cameraManager.currentCamera.getPosition()
        super.update()
    }
    
    override func render(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.pushDebugGroup("Rendering Scene")
        renderCommandEncoder.setVertexBytes(&_sceneConstants, length: SceneConstants.stride, index: 1)
        _lightManager.setLightData(renderCommandEncoder)
        super.render(renderCommandEncoder: renderCommandEncoder)
        renderCommandEncoder.popDebugGroup()
    }
}
