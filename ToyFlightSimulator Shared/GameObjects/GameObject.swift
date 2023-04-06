//
//  GameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

class GameObject: Node, Renderable {
    internal var _modelConstants = ModelConstants()
    private var _mesh: Mesh!
    
    internal var _material: Material? = nil
    internal var _baseColorTextureType: TextureType = .None
    internal var _normalMapTextureType: TextureType = .None
    internal var _specularTextureType: TextureType = .None
    
    init(name: String, meshType: MeshType, renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        super.init(name: name)
        self._renderPipelineStateType = renderPipelineStateType
        if renderPipelineStateType == .OpaqueMaterial {
            self._gBufferRenderPipelineStateType = .GBufferGenerationMaterial
        }
        _mesh = Assets.Meshes[meshType]
        print("GameObject named \(self.getName()) render pipeline state type: \(self._renderPipelineStateType)")
    }
    
    convenience init(name: String,
                     meshType: MeshType,
                     renderPipelineStateType: RenderPipelineStateType = .Opaque,
                     gBufferRPS: RenderPipelineStateType = .GBufferGenerationBase) {
        self.init(name: name, meshType: meshType, renderPipelineStateType: renderPipelineStateType)
        self._gBufferRenderPipelineStateType = gBufferRPS
    }
    
    override func update() {
        _modelConstants.modelMatrix = self.modelMatrix
        _modelConstants.normalMatrix = Transform.normalMatrix(from: self.modelMatrix)
        super.update()
    }
    
    func encodeRender(using renderEncoder: MTLRenderCommandEncoder, label: String, _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder, applyMaterials: Bool = true) {
        encodeRender(using: renderCommandEncoder, label: "Rendering \(self.getName())") {
            // Vertex Shader
            renderCommandEncoder.setVertexBytes(&_modelConstants,
                                                length: ModelConstants.stride,
                                                index: Int(TFSBufferModelConstants.rawValue))
            
            _mesh.drawPrimitives(renderCommandEncoder,
                                 material: _material,
                                 applyMaterials: applyMaterials,
                                 baseColorTextureType: _baseColorTextureType,
                                 normalMapTextureType: _normalMapTextureType,
                                 specularTextureType: _specularTextureType)
        }
    }
    
    func doRenderShadow(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        encodeRender(using: renderCommandEncoder, label: "Shadow Rendering \(self.getName())") {
            renderCommandEncoder.setVertexBytes(&_modelConstants,
                                                length: ModelConstants.stride,
                                                index: Int(TFSBufferModelConstants.rawValue))
            _mesh.drawShadowPrimitives(renderCommandEncoder)
        }
    }
}

// Material Properties
extension GameObject {
    public func useBaseColorTexture(_ textureType: TextureType) {
        _baseColorTextureType = textureType
    }
    
    public func useNormalMapTexture(_ textureType: TextureType) {
        _normalMapTextureType = textureType
    }
    
    public func useSpecularTexture(_ textureType: TextureType) {
        _specularTextureType = textureType
    }
    
    public func useMaterial(_ material: Material) {
        if material.color.w < 1.0 {
            _renderPipelineStateType = .OrderIndependentTransparent
        } else {
            _renderPipelineStateType = .OpaqueMaterial
        }
        
        _gBufferRenderPipelineStateType = .GBufferGenerationMaterial
        
        _material = material
    }
}
