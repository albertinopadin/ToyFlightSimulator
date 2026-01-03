//
//  VertexDescriptorLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

extension TFSVertexAttributes {
    // allCases must return sorted to make adding vertex attributes easy:
    public static var allCases: [TFSVertexAttributes] {
        return [
            TFSVertexAttributePosition,
            TFSVertexAttributeTexcoord,
            TFSVertexAttributeNormal,
            TFSVertexAttributeTangent,
            TFSVertexAttributeBitangent,
            TFSVertexAttributeColor,
            TFSVertexAttributeJoints,
            TFSVertexAttributeJointWeights
        ].sorted(by: { $0.rawValue < $1.rawValue })
    }
}

enum VertexDescriptorType {
    case Simple
    case PositionOnly
    case Skybox
    case Tessellation
}

final class VertexDescriptorLibrary: Library<VertexDescriptorType, MTLVertexDescriptor>, @unchecked Sendable {
    private var _library: [VertexDescriptorType: VertexDescriptor] = [:]
    
    override func makeLibrary() {
        _library.updateValue(SimpleVertexDescriptor(), forKey: .Simple)
        _library.updateValue(PositionOnlyVertexDescriptor(), forKey: .PositionOnly)
        _library.updateValue(SkyboxVertexDescriptor(), forKey: .Skybox)
        _library.updateValue(SimpleVertexDescriptor(withTessellation: true), forKey: .Tessellation)
//        _library.updateValue(TessellationVertexDescriptor(), forKey: .Tessellation)
    }
    
    override subscript(type: VertexDescriptorType) -> MTLVertexDescriptor {
        return _library[type]!.vertexDescriptor
    }
}
