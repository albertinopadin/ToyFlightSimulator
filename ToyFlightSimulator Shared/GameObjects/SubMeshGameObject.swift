//
//  SubMeshGameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit

class SubMeshGameObject: GameObject {
    private var _singleSMMesh: SingleSubmeshMesh!
    var submeshName: String = ""
    
    init(name: String,
         modelType: ModelType,
         meshType: SingleSMMeshType,
         submeshOrigin: float3 = float3(0, 0, 0)) {
        super.init(name: name, modelType: modelType)
        _singleSMMesh = Assets.SingleSMMeshes[meshType]
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
