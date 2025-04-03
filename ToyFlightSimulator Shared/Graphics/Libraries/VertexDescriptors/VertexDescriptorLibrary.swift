//
//  VertexDescriptorLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

extension TFSVertexAttributes: CaseIterable {
    // allCases must return sorted to make adding vertex attributes easy:
    public static var allCases: [TFSVertexAttributes] {
        return [
            TFSVertexAttributePosition,
            TFSVertexAttributeTexcoord,
            TFSVertexAttributeNormal,
            TFSVertexAttributeTangent,
            TFSVertexAttributeBitangent,
            TFSVertexAttributeColor
        ].sorted(by: { $0.rawValue < $1.rawValue })
    }
}

enum VertexDescriptorType {
    case Base
    case PositionOnly
    case Skybox
}

final class VertexDescriptorLibrary: Library<VertexDescriptorType, MTLVertexDescriptor>, @unchecked Sendable {
    private var _library: [VertexDescriptorType: VertexDescriptor] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseVertexDescriptor(), forKey: .Base)
        _library.updateValue(PositionOnlyVertexDescriptor(), forKey: .PositionOnly)
        _library.updateValue(SkyboxVertexDescriptor(), forKey: .Skybox)
    }
    
    override subscript(type: VertexDescriptorType) -> MTLVertexDescriptor {
        return _library[type]!.vertexDescriptor
    }
}
