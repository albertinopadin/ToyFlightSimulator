//
//  Scene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

// Scene is head node of scene graph
class GameScene: Node {
    private var _sceneConstants = SceneConstants()
    
    private var _cmdPressed: Bool = false
    private var _rPressed: Bool = false
    
    internal var _rendererType: RendererType!
    
    override init(name: String) {
        print("[Scene init] Initilizing scene named: \(name)")
        super.init(name: name)
        self._rendererType = .SinglePassDeferredLighting  // Set default
        initScene()
    }
    
    init(name: String, rendererType: RendererType) {
        print("[Scene init] Initilizing scene named: \(name)")
        super.init(name: name)
        self._rendererType = rendererType
        initScene()
    }
    
    override func addChild(_ child: Node) {
        super.addChild(child)
        registerChildObject(child)
    }
    
    func registerChildObject(_ child: Node) {
        if let childObj = child as? GameObject {
            if !(childObj is Camera) {
//                DrawManager.Register(childObj)
                SceneManager.Register(childObj)
            }
        }

        for grandchild in child.children {
            registerChildObject(grandchild)
        }
    }
    
    func initScene() {
        preBuildScene()
        buildScene()
        postBuildScene()
    }
    
    func preBuildScene() {
        SceneManager.Paused = true
    }
    
    // To be overriden by subclasses:
    func buildScene() { }
    
    func postBuildScene() {
        SceneManager.Paused = false
    }
    
    func teardownScene() {
        SceneManager.Paused = true
        LightManager.RemoveAllLights()
        CameraManager.RemoveAllCameras()
        removeAllChildren()
    }
    
    func addCamera(_ camera: Camera, _ isCurrentCamera: Bool = true) {
        CameraManager.RegisterCamera(camera: camera)
        if (isCurrentCamera) {
            CameraManager.SetCamera(camera.cameraType)
        }
    }
    
    func addLight(_ lightObject: LightObject) {
        self.addChild(lightObject)
        LightManager.AddLightObject(lightObject)
    }
    
    func updateCameras(deltaTime: Double) {
        CameraManager.Update(deltaTime: deltaTime)
    }
    
    func setAspectRatio(_ aspectRatio: Float) {
        CameraManager.SetAspectRatio(aspectRatio)
    }
    
    // TODO: Refactor to maybe get rid of this doUpdate method...
    override func doUpdate() {
        InputManager.HandleMouseClickDebounced(command: .ClickSelect) {
            for node in children {
                if node.clickedOnNode(mousePosition: Mouse.GetMouseViewportPosition(),
                                      viewMatrix: CameraManager.CurrentCamera.viewMatrix,
                                      projectionMatrix: CameraManager.CurrentCamera.projectionMatrix) {
                    print("[GameScene doUpdate] Node \(node.getName()) got focus!")
                    node.hasFocus = true
                } else {
                    if node.hasFocus {
                        print("[GameScene doUpdate] Node \(node.getName()) lost focus!")
                        node.hasFocus = false
                    }
                }
            }
        }
        
        InputManager.HasMultiInputCommand(command: .ResetScene) {
            teardownScene()
            initScene()
        }
    }
    
    override func update() {
        super.update()
        _sceneConstants.viewMatrix = CameraManager.CurrentCamera.viewMatrix
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0  // Remove x translation
        _sceneConstants.skyViewMatrix[3][1] = 0  // Remove y translation
        _sceneConstants.skyViewMatrix[3][2] = 0  // Remove z translation
        _sceneConstants.projectionMatrix = CameraManager.CurrentCamera.projectionMatrix
        _sceneConstants.projectionMatrixInverse = CameraManager.CurrentCamera.projectionMatrix.inverse
        _sceneConstants.totalGameTime = Float(GameTime.TotalGameTime)
        _sceneConstants.cameraPosition = CameraManager.CurrentCamera.modelMatrix.columns.3.xyz
    }
    
    func setSceneConstants(with renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setVertexBytes(&_sceneConstants,
                                     length: SceneConstants.stride,
                                     index: TFSBufferIndexSceneConstants.index)
    }
    
    func setDirectionalLightConstants(with renderEncoder: MTLRenderCommandEncoder) {
        var directionalLight = LightManager.GetDirectionalLightData(viewMatrix: _sceneConstants.skyViewMatrix).first!
        renderEncoder.setVertexBytes(&directionalLight,
                                     length: LightData.stride,
                                     index: TFSBufferDirectionalLightData.index)
        renderEncoder.setFragmentBytes(&directionalLight,
                                       length: LightData.stride,
                                       index: TFSBufferDirectionalLightData.index)
    }
    
    func setPointLightConstants(with renderEncoder: MTLRenderCommandEncoder) {
        var pointLights = LightManager.GetPointLightData()
        // Avoid allocating memory in game loop
        // (if you use more than 4KB of data, allocate the buffer on init, instead of creating a new one every frame):
//        let buf = Engine.Device.makeBuffer(bytes: &pointLights, length: LightData.stride(pointLights.count))
//        renderCommandEncoder.setVertexBuffer(buf,
//                                             offset: 0,
//                                             index: TFSBufferIndexLightsData.index)
        
        renderEncoder.setVertexBytes(&pointLights,
                                     length: LightData.stride(pointLights.count),
                                     index: TFSBufferPointLightsData.index)
    }
    
    // TODO: This method could possibly be merged/unified with setDirectionalLightConstants
    func setDirectionalLightData(with renderEncoder: MTLRenderCommandEncoder) {
        LightManager.SetDirectionalLightData(renderEncoder,
                                             cameraPosition: CameraManager.CurrentCamera.modelMatrix.columns.3.xyz,
                                             viewMatrix: CameraManager.CurrentCamera.viewMatrix)
    }
    
    func setPointLightData(with renderEncoder: MTLRenderCommandEncoder) {
        LightManager.SetPointLightData(renderEncoder)
    }
    
//    func renderPointLightMeshes(with renderEncoder: MTLRenderCommandEncoder) {
//        for pointLight in LightManager.GetLightObjects(lightType: Point) {
//            pointLight.render(with: renderEncoder, renderPipelineStateType: .LightMask)
//        }
//    }
    
//    func renderPointLights(with renderEncoder: MTLRenderCommandEncoder) {
//        for pointLight in LightManager.GetLightObjects(lightType: Point) {
//            pointLight.render(with: renderEncoder, renderPipelineStateType: .SinglePassDeferredPointLight)
//        }
//    }
}
