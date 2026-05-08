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
        
        // TODO: Perhaps a more elegant solution would be to send a 
        //       notification instead of calling Engine directly...?
        Engine.SceneBuildFinished()
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

    /// Adds a static, color-tinted ground plane and returns it.
    /// Defaults match the most common configuration across scenes
    /// (green, restitution 1.0, rotated 270° about Z, scale 1000).
    @discardableResult
    func addGround(color: float4 = float4(0.3, 0.7, 0.1, 1.0),
                   restitution: Float = 1.0,
                   rotationZ: Float = Float(270).toRadians,
                   scale: Float = 1000) -> CollidablePlane {
        let ground = CollidablePlane()
        ground.collisionNormal = [0, 1, 0]
        ground.collisionShape = .Plane
        ground.restitution = restitution
        ground.isStatic = true
        ground.setColor(color)
        ground.rotateZ(rotationZ)
        ground.setScale(scale)
        addChild(ground)
        return ground
    }

    /// Adds the default sky for the active renderer, if one is supported.
    /// OIT → SkySphere (clouds), SinglePassDeferred → SkyBox; other
    /// renderers get no sky (caller can override).
    func setupDefaultSky() {
        switch _rendererType {
            case .OrderIndependentTransparency:
                addChild(SkySphere(textureType: .Clouds_Skysphere))
            case .SinglePassDeferredLighting:
                addChild(SkyBox(textureType: .SkyMap))
            default:
                break
        }
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
            guard let camera = CameraManager.CurrentCamera else { return }
            for node in children {
                if node.clickedOnNode(mousePosition: Mouse.GetMouseViewportPosition(),
                                      viewMatrix: camera.viewMatrix,
                                      projectionMatrix: camera.projectionMatrix) {
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
        guard let camera = CameraManager.CurrentCamera else { return }
        _sceneConstants.viewMatrix = camera.viewMatrix
        _sceneConstants.skyViewMatrix = _sceneConstants.viewMatrix
        _sceneConstants.skyViewMatrix[3][0] = 0  // Remove x translation
        _sceneConstants.skyViewMatrix[3][1] = 0  // Remove y translation
        _sceneConstants.skyViewMatrix[3][2] = 0  // Remove z translation
        _sceneConstants.projectionMatrix = camera.projectionMatrix
        _sceneConstants.projectionMatrixInverse = camera.projectionMatrix.inverse
        _sceneConstants.totalGameTime = Float(GameTime.TotalGameTime)
        _sceneConstants.cameraPosition = CameraManager.GetCurrentCameraPosition()
    }
    
    func setSceneConstants(with renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setVertexBytes(&_sceneConstants,
                                     length: SceneConstants.stride,
                                     index: TFSBufferIndexSceneConstants.index)
    }

    func setDirectionalLightConstants(with renderEncoder: MTLRenderCommandEncoder) {
        guard var directionalLight = LightManager
            .GetDirectionalLightData(viewMatrix: _sceneConstants.skyViewMatrix)
            .first
        else { return }
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
                                             cameraPosition: _sceneConstants.cameraPosition,
                                             viewMatrix: _sceneConstants.viewMatrix)
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
