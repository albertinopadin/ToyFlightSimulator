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
    
    private var _cmdPressed: Bool = false
    private var _rPressed: Bool = false
    
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
    
    override func doUpdate() {
        InputManager.handleKeyPressedDebounced(keyCode: .command, keyPressed: &_cmdPressed) {
            print("CMD pressed")
                InputManager.handleKeyPressedDebounced(keyCode: .r, keyPressed: &_rPressed) {
                print("CMD-R pressed")
                // TODO: Figure out how to reset scene
            }
        }
    }
    
    override func update() {
        _sceneConstants.viewMatrix = _cameraManager.currentCamera.viewMatrix
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0  // Remove x translation
        _sceneConstants.skyViewMatrix[3][1] = 0  // Remove y translation
        _sceneConstants.skyViewMatrix[3][2] = 0  // Remove z translation
        _sceneConstants.projectionMatrix = _cameraManager.currentCamera.projectionMatrix
        _sceneConstants.projectionMatrixInverse = _cameraManager.currentCamera.projectionMatrix.inverse
        _sceneConstants.totalGameTime = GameTime.TotalGameTime
        _sceneConstants.cameraPosition = _cameraManager.currentCamera.getPosition()
        super.update()
    }
    
    func setSceneConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setVertexBytes(&_sceneConstants,
                                            length: SceneConstants.stride,
                                            index: Int(TFSBufferIndexSceneConstants.rawValue))
    }
    
    func setDirectionalLightConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        var directionalLight = _lightManager.getDirectionalLightData()!
        renderCommandEncoder.setVertexBytes(&directionalLight,
                                            length: LightData.stride,
                                            index: Int(TFSBufferLightData.rawValue))
        renderCommandEncoder.setFragmentBytes(&directionalLight,
                                              length: LightData.stride,
                                              index: Int(TFSBufferLightData.rawValue))
    }
    
    func setPointLightConstants(renderCommandEncoder: MTLRenderCommandEncoder) {
        var pointLights = _lightManager.getPointLightData()
        let buf = Engine.Device.makeBuffer(bytes: &pointLights, length: LightData.stride(pointLights.count))
        renderCommandEncoder.setVertexBuffer(buf,
                                             offset: 0,
                                             index: Int(TFSBufferIndexLightsData.rawValue))
    }
    
    func setLightData(renderCommandEncoder: MTLRenderCommandEncoder) {
        _lightManager.setLightData(renderCommandEncoder)
    }
    
    override func render(renderCommandEncoder: MTLRenderCommandEncoder,
                         renderPipelineStateType: RenderPipelineStateType,
                         applyMaterials: Bool = true) {
        renderCommandEncoder.pushDebugGroup("Rendering \(renderPipelineStateType) Scene")
        super.render(renderCommandEncoder: renderCommandEncoder,
                     renderPipelineStateType: renderPipelineStateType,
                     applyMaterials: applyMaterials)
        renderCommandEncoder.popDebugGroup()
    }
}
