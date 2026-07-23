//
//  ObjMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

final class ObjModel: Model {
    init(_ modelName: String, basisTransform: float4x4? = nil, realWorldLength: Float? = nil) {
        super.init(modelName, fileExtension: .OBJ, basisTransform: basisTransform, realWorldLength: realWorldLength)
    }
}
