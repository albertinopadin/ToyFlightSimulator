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
    
    init(name: String, meshType: SingleSMMeshType, renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        super.init(name: name, meshType: .None, renderPipelineStateType: renderPipelineStateType)
        _singleSMMesh = Assets.SingleSMMeshes[meshType]
    }
    
    init(name: String,
         modelName: String,
         submeshName: String,
         renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        super.init(name: name, meshType: .None, renderPipelineStateType: renderPipelineStateType)
        _singleSMMesh = SingleSMMesh(modelName: modelName, submeshName: submeshName)
        self.submeshName = submeshName
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
