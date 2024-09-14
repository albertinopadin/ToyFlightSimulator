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
         modelType: ModelType,
         meshType: SingleSMMeshType,
         submeshOrigin: float3 = float3(0, 0, 0)) {
        super.init(name: name, modelType: .None)
        _singleSMMesh = Assets.SingleSMMeshes[meshType]
        _singleSMMesh.setSubmeshOrigin(submeshOrigin)
    }
    
    init(name: String,
         modelName: String,
         submeshName: String,
         submeshOrigin: float3 = float3(0, 0, 0)) {
        super.init(name: name, modelType: .None)
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
}
