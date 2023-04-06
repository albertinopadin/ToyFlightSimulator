//
//  SubMeshGameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit

class SubMeshGameObject: GameObject {
    private var _singleSMMesh: SingleSMMesh!
    
    init(name: String, meshType: SingleSMMeshType, renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        super.init(name: name, meshType: .None)
        _singleSMMesh = Assets.SingleSMMeshes[meshType]
    }
    
    override func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder, applyMaterials: Bool = true) {
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
    
    override func doRenderShadow(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        encodeRender(using: renderCommandEncoder, label: "Shadow Rendering \(self.getName())") {
            renderCommandEncoder.setVertexBytes(&_modelConstants,
                                                length: ModelConstants.stride,
                                                index: Int(TFSBufferModelConstants.rawValue))
            _singleSMMesh.drawShadowPrimitives(renderCommandEncoder)
        }
    }
}
