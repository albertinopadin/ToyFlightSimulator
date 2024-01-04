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
    private var _lightManager = LightManager()
    private var _sceneConstants = SceneConstants()
    
    private var _cmdPressed: Bool = false
    private var _rPressed: Bool = false
    
    internal var _rendererType: RendererType!
    
    private var _meshesForRenderPipelineStates = [RenderPipelineStateType: [MeshType: [Node]]]()
                                                
    
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
    
    override func addChild(_ child: Node) {
        // TODO: This will only work for nodes added directly to Scene.
        //       Need to figure out how to get node's children, and what happens if a
        //       node is first added to a scene and THEN a child is added to said node...
        if child is GameObject {
            _meshesForRenderPipelineStates[child._renderPipelineStateType, 
                                           default: [:]][(child as! GameObject)._mesh.type,
                                                         default: []].append(child)
        }
        super.addChild(child)
    }
    
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
    
    func setSceneConstants(with renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setVertexBytes(&_sceneConstants,
                                            length: SceneConstants.stride,
                                            index: Int(TFSBufferIndexSceneConstants.rawValue))
    }
    
    func setDirectionalLightConstants(with renderCommandEncoder: MTLRenderCommandEncoder) {
        var directionalLight = _lightManager.getDirectionalLightData().first!
        renderCommandEncoder.setVertexBytes(&directionalLight,
                                            length: LightData.stride,
                                            index: Int(TFSBufferDirectionalLightData.rawValue))
        renderCommandEncoder.setFragmentBytes(&directionalLight,
                                              length: LightData.stride,
                                              index: Int(TFSBufferDirectionalLightData.rawValue))
    }
    
    func setPointLightConstants(with renderCommandEncoder: MTLRenderCommandEncoder) {
        var pointLights = _lightManager.getPointLightData()
        // Avoid allocating memory in game loop
        // (if you use more than 4KB of data, allocate the buffer on init, instead of creating a new one every frame):
//        let buf = Engine.Device.makeBuffer(bytes: &pointLights, length: LightData.stride(pointLights.count))
//        renderCommandEncoder.setVertexBuffer(buf,
//                                             offset: 0,
//                                             index: Int(TFSBufferIndexLightsData.rawValue))
        
        renderCommandEncoder.setVertexBytes(&pointLights,
                                            length: LightData.stride(pointLights.count),
                                            index: Int(TFSBufferPointLightsData.rawValue))
    }
    
    // TODO: This method could possibly be merged/unified with setDirectionalLightConstants
    func setDirectionalLightData(with renderCommandEncoder: MTLRenderCommandEncoder) {
        _lightManager.setDirectionalLightData(renderCommandEncoder)
    }
    
    func setPointLightData(with renderCommandEncoder: MTLRenderCommandEncoder) {
        _lightManager.setPointLightData(renderCommandEncoder)
    }
    
    func renderNodes(with renderCommandEncoder: MTLRenderCommandEncoder,
                     meshTypesNodes: [MeshType : [Node]],
                     applyMaterials: Bool,
                     filterFunc: (Node) -> Bool,
                     gameObjectFunc: (GameObject) -> Void = {_ in }){
        for (_, nodes) in meshTypesNodes {
            var modelConstants = [ModelConstants]()  // <--- Don't allocate here
            
            // Collect node ModelConstants
            for node in nodes {
                if filterFunc(node) {
                    modelConstants.append(ModelConstants(modelMatrix: node.modelMatrix, normalMatrix: node.normalMatrix))
                }
            }
            
            renderCommandEncoder.setVertexBytes(&modelConstants,
                                                length: ModelConstants.size(modelConstants.count),
                                                index: Int(TFSBufferModelConstants.rawValue))
            
            if modelConstants.count > 0, let anObject = nodes.first as? GameObject {
                gameObjectFunc(anObject)
                
                // Ugh, hack:
                anObject._mesh.setInstanceCount(modelConstants.count)
                anObject._mesh.drawPrimitives(renderCommandEncoder,
                                              material: anObject._material,
                                              applyMaterials: applyMaterials,
                                              baseColorTextureType: anObject._baseColorTextureType,
                                              normalMapTextureType: anObject._normalMapTextureType,
                                              specularTextureType: anObject._specularTextureType)
            }
            
        }
    }
    
    func renderGBuffer(with renderCommandEncoder: MTLRenderCommandEncoder, gBufferRPS: RenderPipelineStateType) {
        for meshTypesNodes in _meshesForRenderPipelineStates.values {
            renderNodes(with: renderCommandEncoder, meshTypesNodes: meshTypesNodes, applyMaterials: true) { node in
                return node.shouldRenderGBuffer(gBufferRPS: gBufferRPS)
            }
        }
    }
    
    func render(with renderCommandEncoder: MTLRenderCommandEncoder,
                renderPipelineStateType: RenderPipelineStateType,
                applyMaterials: Bool = true) {
        renderCommandEncoder.pushDebugGroup("Rendering \(renderPipelineStateType) Scene")
        
        if let meshTypesNodes = _meshesForRenderPipelineStates[renderPipelineStateType] {
            renderNodes(with: renderCommandEncoder, 
                        meshTypesNodes: meshTypesNodes,
                        applyMaterials: applyMaterials,
                        filterFunc: { node in return node.shouldRender(with: renderPipelineStateType) },
                        gameObjectFunc: { gameObject in
                            if gameObject is SkyBox {
                                renderCommandEncoder.setFragmentTexture(Assets.Textures[.SkyMap],
                                                                        index: Int(TFSTextureIndexBaseColor.rawValue))
                            }
                            
                            if gameObject is SkySphere {
                                renderCommandEncoder.setFragmentTexture(Assets.Textures[.Clouds_Skysphere],
                                                                        index: 10)
                            }
                        })
        }
        
        renderCommandEncoder.popDebugGroup()
    }
    
    func renderShadows(with renderCommandEncoder: MTLRenderCommandEncoder) {
        for meshTypesNodes in _meshesForRenderPipelineStates.values {
            renderNodes(with: renderCommandEncoder, meshTypesNodes: meshTypesNodes, applyMaterials: false) { node in
                return node.shouldRenderShadows()
            }
        }
    }
}
