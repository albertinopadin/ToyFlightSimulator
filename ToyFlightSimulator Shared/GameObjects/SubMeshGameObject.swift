//
//  SubMeshGameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit

class SubMeshGameObject: GameObject {
    private var _singleSMMesh: SingleSMMesh!
    var submeshName: String = ""
    
    init(name: String,
         meshType: SingleSMMeshType,
         moveToInitialParentMeshPosition: Bool = true,
         renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        super.init(name: name, meshType: .None, renderPipelineStateType: renderPipelineStateType)
        _singleSMMesh = Assets.SingleSMMeshes[meshType]
        
        if moveToInitialParentMeshPosition {
            self.setPosition(_singleSMMesh.vertexMetadata.initialPositionInParentMesh)
        }
    }
    
    init(name: String,
         modelName: String,
         submeshName: String,
         moveToInitialParentMeshPosition: Bool = true,
         renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        super.init(name: name, meshType: .None, renderPipelineStateType: renderPipelineStateType)
        _singleSMMesh = SingleSMMesh.createSingleSMMeshFromModel(modelName: modelName, submeshName: submeshName)
        self.submeshName = submeshName
        
        if moveToInitialParentMeshPosition {
            self.setPosition(_singleSMMesh.vertexMetadata.initialPositionInParentMesh)
        }
    }
    
    public func getInitialPositionInParentMesh() -> float3 {
        return _singleSMMesh.vertexMetadata.initialPositionInParentMesh
    }
    
    override func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder,
                           applyMaterials: Bool = true,
                           submeshesToRender: [String: Bool]? = nil) {
        encodeRender(using: renderCommandEncoder, label: "Rendering \(self.getName())") {
            renderCommandEncoder.setVertexBytes(&_modelConstants,
                                                length: ModelConstants.stride,
                                                index: Int(TFSBufferModelConstants.rawValue))
            
            _singleSMMesh.drawPrimitives(renderCommandEncoder,
                                         material: _material,
                                         applyMaterials: applyMaterials,
                                         baseColorTextureType: _baseColorTextureType,
                                         normalMapTextureType: _normalMapTextureType,
                                         specularTextureType: _specularTextureType)
        }
    }
    
    override func doRenderShadow(_ renderCommandEncoder: MTLRenderCommandEncoder, submeshesToRender: [String: Bool]? = nil) {
        encodeRender(using: renderCommandEncoder, label: "Shadow Rendering \(self.getName())") {
            renderCommandEncoder.setVertexBytes(&_modelConstants,
                                                length: ModelConstants.stride,
                                                index: Int(TFSBufferModelConstants.rawValue))
            _singleSMMesh.drawShadowPrimitives(renderCommandEncoder)
        }
    }
}
