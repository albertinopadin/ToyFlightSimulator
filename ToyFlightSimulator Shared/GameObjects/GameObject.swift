//
//  GameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class GameObject: Node, Renderable {
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
        // Vertex Shader
        renderCommandEncoder.setVertexBytes(&_modelConstants, length: ModelConstants.stride, index: 2)
        
        _mesh.drawPrimitives(renderCommandEncoder,
                             material: _material,
                             baseColorTextureType: _baseColorTextureType,
                             normalMapTextureType: _normalMapTextureType)
    }
    
    func doRenderShadow(renderCommandEncoder: MTLRenderCommandEncoder, shadowViewProjectionMatrix: float4x4) {
        var shadowData = ShadowData(modelViewProjectionMatrix: shadowViewProjectionMatrix * modelMatrix)
        renderCommandEncoder.setVertexBytes(&shadowData, length: ShadowData.stride, index: 2)
        _mesh.drawShadowPrimitives(renderCommandEncoder)
    }
    
    func doRenderDepth(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setVertexBytes(&_modelConstants, length: ModelConstants.stride, index: 2)
        _mesh.drawDepthPrimitives(renderCommandEncoder)
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
