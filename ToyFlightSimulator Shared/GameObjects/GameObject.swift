//
//  GameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class GameObject: Node {
    var renderPipelineStateType: RenderPipelineStateType
    
    private var _modelConstants = ModelConstants()
    private var _mesh: Mesh!
    
    private var _material: Material? = nil
    private var _baseColorTextureType: TextureType = .None
    private var _normalMapTextureType: TextureType = .None
    
    var mesh: Mesh!
    
    init(name: String, meshType: MeshType, renderPipelineStateType: RenderPipelineStateType = .Base) {
        self.renderPipelineStateType = renderPipelineStateType
        super.init(name: name)
        _mesh = Assets.Meshes[meshType]
        print("GameObject named \(self.getName()) render pipeline state type: \(self.renderPipelineStateType)")
    }
    
    override func update() {
        _modelConstants.modelMatrix = self.modelMatrix
        super.update()
    }
}

extension GameObject: Renderable {
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
//        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
//        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
        
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
        _material = material
        renderPipelineStateType = .Material
    }
}
