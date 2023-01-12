//
//  GameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class GameObject: Node, Renderable {
//    var renderPipelineStateType: RenderPipelineStateType
    
    private var _modelConstants = ModelConstants()
    private var _mesh: Mesh!
    
    private var _material: Material? = nil
    private var _baseColorTextureType: TextureType = .None
    private var _normalMapTextureType: TextureType = .None
    
    var mesh: Mesh!
    
    init(name: String, meshType: MeshType, renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        super.init(name: name)
        self._renderPipelineStateType = renderPipelineStateType
        _mesh = Assets.Meshes[meshType]
        print("GameObject named \(self.getName()) render pipeline state type: \(self._renderPipelineStateType)")
    }
    
    override func update() {
        _modelConstants.modelMatrix = self.modelMatrix
        super.update()
    }
    
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
//        if renderPipelineStateType == .OpaqueMaterial || renderPipelineStateType == .SkySphere {
//            renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
//        }
        
        // TODO: Set this before rendering all objects using specific RPST:
//        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
        
        // Vertex Shader
        renderCommandEncoder.setVertexBytes(&_modelConstants, length: ModelConstants.stride, index: 2)
        
        _mesh.drawPrimitives(renderCommandEncoder,
                             material: _material,
                             baseColorTextureType: _baseColorTextureType,
                             normalMapTextureType: _normalMapTextureType)
    }
}

// Material Properties
extension GameObject {
    public func useBaseColorTexture(_ textureType: TextureType) {
        self._baseColorTextureType = textureType
    }
    
    public func useNormalMapTexture(_ textureType: TextureType) {
        self._normalMapTextureType = textureType
    }
    
    public func useMaterial(_ material: Material) {
        if material.color.w < 1.0 {
            _renderPipelineStateType = .OrderIndependentTransparent
        } else {
            _renderPipelineStateType = .OpaqueMaterial
        }
        
        _material = material
    }
}
