//
//  SubMeshGameObject.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit

class SubMeshGameObject: GameObject {
    private var _singleSMMesh: SingleSubmeshMesh!
    public var submeshName: String = ""
    public var parentMeshGameObject: GameObject?
    
    init(name: String,
         modelType: ModelType,
         meshType: SingleSMMeshType,
         scale: Float = 1.0,
         submeshOrigin: float3 = float3(0, 0, 0)) {
        super.init(name: name, modelType: modelType)
        _singleSMMesh = Assets.SingleSMMeshes[meshType]
        _singleSMMesh.setSubmeshOrigin(submeshOrigin)
        _singleSMMesh.translateSubmeshVerticesToMatchParentScale(scale)
        submeshName = _singleSMMesh.name
    }
    
    override func setScale(_ scale: Float) {
        _singleSMMesh.translateSubmeshVerticesToMatchParentScale(scale)
        super.setScale(scale)
    }
    
    override func setScale(_ scale: float3) {
        guard scale.x == scale.y, scale.y == scale.z else {
            fatalError("[SubMeshGameObject setScale] Expecting uniform scale: \(scale)")
        }
        
        _singleSMMesh.translateSubmeshVerticesToMatchParentScale(scale.x)
        super.setScale(scale)
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
