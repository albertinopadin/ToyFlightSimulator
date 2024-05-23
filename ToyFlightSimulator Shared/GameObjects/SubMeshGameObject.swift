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
         submeshOrigin: float3 = float3(0, 0, 0),
         renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        super.init(name: name, meshType: .None, renderPipelineStateType: renderPipelineStateType)
        _singleSMMesh = Assets.SingleSMMeshes[meshType]
        _singleSMMesh.setSubmeshOrigin(submeshOrigin)
    }
    
    init(name: String,
         modelName: String,
         submeshName: String,
         submeshOrigin: float3 = float3(0, 0, 0),
         renderPipelineStateType: RenderPipelineStateType = .Opaque) {
        super.init(name: name, meshType: .None, renderPipelineStateType: renderPipelineStateType)
        self.submeshName = submeshName
        _singleSMMesh = SingleSMMesh.createSingleSMMeshFromModel(modelName: modelName, submeshName: submeshName)
        _singleSMMesh.setSubmeshOrigin(submeshOrigin)
    }
    
    public func getInitialPositionInParentMesh() -> float3 {
        return _singleSMMesh.vertexMetadata.initialPositionInParentMesh
    }
    
    public func setSubmeshOrigin(_ origin: float3) {
        _singleSMMesh.setSubmeshOrigin(origin)
    }
    
    public func getSubmeshVertexMetadata() -> SingleMeshVertexMetadata {
        return _singleSMMesh.vertexMetadata
    }
    
    override func doRender(_ renderEncoder: MTLRenderCommandEncoder,
                           applyMaterials: Bool = true,
                           submeshesToRender: [String: Bool]? = nil) {
        encodeRender(using: renderEncoder, label: "Rendering \(self.getName())") {
            renderEncoder.setVertexBytes(&_modelConstants,
                                         length: ModelConstants.stride,
                                         index: TFSBufferModelConstants.index)
            
            _singleSMMesh.drawPrimitives(renderEncoder,
                                         material: _material,
                                         applyMaterials: applyMaterials,
                                         baseColorTextureType: _baseColorTextureType,
                                         normalMapTextureType: _normalMapTextureType,
                                         specularTextureType: _specularTextureType)
        }
    }
    
    override func doRenderShadow(_ renderEncoder: MTLRenderCommandEncoder, submeshesToRender: [String: Bool]? = nil) {
        encodeRender(using: renderEncoder, label: "Shadow Rendering \(self.getName())") {
            renderEncoder.setVertexBytes(&_modelConstants,
                                         length: ModelConstants.stride,
                                         index: TFSBufferModelConstants.index)
            _singleSMMesh.drawShadowPrimitives(renderEncoder)
        }
    }
}
