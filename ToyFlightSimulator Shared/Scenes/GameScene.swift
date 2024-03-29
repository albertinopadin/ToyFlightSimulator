//
//  Scene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

// Scene is head node of scene graph
class GameScene: Node {
    private var _cameraManager = CameraManager()
    private var _sceneConstants = SceneConstants()
    
    private var _cmdPressed: Bool = false
    private var _rPressed: Bool = false
    
    internal var _rendererType: RendererType!
    
    override init(name: String) {
        print("[Scene init] Initilizing scene named: \(name)")
        super.init(name: name)
        self._rendererType = .SinglePassDeferredLighting  // Set default
        buildScene()
    }
    
    init(name: String, rendererType: RendererType) {
        print("[Scene init] Initilizing scene named: \(name)")
        super.init(name: name)
        self._rendererType = rendererType
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
        LightManager.addLightObject(lightObject)
    }
    
    func updateCameras(deltaTime: Double) {
        _cameraManager.update(deltaTime: deltaTime)
    }
    
    func setAspectRatio(_ aspectRatio: Float) {
        _cameraManager.setAspectRatio(aspectRatio)
    }
    
    override func doUpdate() {
        InputManager.HasMultiInputCommand(command: .ResetScene) {
            print("Commanded to reset scene!")
            // TODO: tear down old scene first
//            buildScene()
        }
    }
    
    override func update() {
        super.update()
        _sceneConstants.viewMatrix = _cameraManager.currentCamera.viewMatrix
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0  // Remove x translation
        _sceneConstants.skyViewMatrix[3][1] = 0  // Remove y translation
        _sceneConstants.skyViewMatrix[3][2] = 0  // Remove z translation
        _sceneConstants.projectionMatrix = _cameraManager.currentCamera.projectionMatrix
        _sceneConstants.projectionMatrixInverse = _cameraManager.currentCamera.projectionMatrix.inverse
        _sceneConstants.totalGameTime = Float(GameTime.TotalGameTime)
        _sceneConstants.cameraPosition = _cameraManager.currentCamera.modelMatrix.columns.3.xyz
    }
    
    func setSceneConstants(with renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setVertexBytes(&_sceneConstants,
                                            length: SceneConstants.stride,
                                            index: TFSBufferIndexSceneConstants.index)
    }
    
    func setDirectionalLightConstants(with renderCommandEncoder: MTLRenderCommandEncoder) {
        var directionalLight = LightManager.getDirectionalLightData(viewMatrix: _sceneConstants.skyViewMatrix).first!
        renderCommandEncoder.setVertexBytes(&directionalLight,
                                            length: LightData.stride,
                                            index: TFSBufferDirectionalLightData.index)
        renderCommandEncoder.setFragmentBytes(&directionalLight,
                                              length: LightData.stride,
                                              index: TFSBufferDirectionalLightData.index)
    }
    
    func setPointLightConstants(with renderCommandEncoder: MTLRenderCommandEncoder) {
        var pointLights = LightManager.getPointLightData()
        // Avoid allocating memory in game loop
        // (if you use more than 4KB of data, allocate the buffer on init, instead of creating a new one every frame):
//        let buf = Engine.Device.makeBuffer(bytes: &pointLights, length: LightData.stride(pointLights.count))
//        renderCommandEncoder.setVertexBuffer(buf,
//                                             offset: 0,
//                                             index: TFSBufferIndexLightsData.index)
        
        renderCommandEncoder.setVertexBytes(&pointLights,
                                            length: LightData.stride(pointLights.count),
                                            index: TFSBufferPointLightsData.index)
    }
    
    // TODO: This method could possibly be merged/unified with setDirectionalLightConstants
    func setDirectionalLightData(with renderCommandEncoder: MTLRenderCommandEncoder) {
//        _lightManager.setDirectionalLightData(renderCommandEncoder,
//                                              cameraPosition: _cameraManager.currentCamera.getPosition())
        
        LightManager.setDirectionalLightData(renderCommandEncoder,
                                             cameraPosition: _cameraManager.currentCamera.modelMatrix.columns.3.xyz,
                                             viewMatrix: _cameraManager.currentCamera.viewMatrix)
    }
    
    func setPointLightData(with renderCommandEncoder: MTLRenderCommandEncoder) {
        LightManager.setPointLightData(renderCommandEncoder)
    }
    
    func renderPointLightMeshes(with renderCommandEncoder: MTLRenderCommandEncoder) {
        for pointLight in LightManager.getLightObjects(lightType: Point) {
            pointLight.render(with: renderCommandEncoder, renderPipelineStateType: .LightMask)
        }
    }
    
    func renderPointLights(with renderCommandEncoder: MTLRenderCommandEncoder) {
        for pointLight in LightManager.getLightObjects(lightType: Point) {
            pointLight.render(with: renderCommandEncoder, renderPipelineStateType: .SinglePassDeferredPointLight)
        }
    }
    
    override func render(with renderCommandEncoder: MTLRenderCommandEncoder,
                         renderPipelineStateType: RenderPipelineStateType,
                         applyMaterials: Bool = true) {
        renderCommandEncoder.pushDebugGroup("Rendering \(renderPipelineStateType) Scene")
        super.render(with: renderCommandEncoder,
                     renderPipelineStateType: renderPipelineStateType,
                     applyMaterials: applyMaterials)
        renderCommandEncoder.popDebugGroup()
    }
}
