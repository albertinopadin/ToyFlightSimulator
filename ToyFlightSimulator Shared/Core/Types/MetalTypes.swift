//
//  MetalTypes.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import simd


public typealias float2 = SIMD2<Float>
public typealias float3 = SIMD3<Float>
public typealias float4 = SIMD4<Float>

protocol sizeable { }

extension sizeable {
    static var size: Int {
        return MemoryLayout<Self>.size
    }
    
    static var stride: Int {
        return MemoryLayout<Self>.stride
    }
    
    static func size(_ count: Int) -> Int {
        return MemoryLayout<Self>.size * count
    }
    
    static func stride(_ count: Int) -> Int {
        return MemoryLayout<Self>.stride * count
    }
}

extension UInt32: sizeable {}
extension Int32:  sizeable {}
extension Float:  sizeable {}
extension SIMD2:  sizeable {}
extension SIMD3:  sizeable {}
extension SIMD4:  sizeable {}

struct Vertex: sizeable {
    var position: float3 = float3(0, 0, 0)
    var color: float4 = float4(0, 0, 0, 1)
    var textureCoordinate: float2 = float2(0, 0)
    var normal: float3 = float3(0, 0, 1)
    var tangent: float3 = float3(1, 0, 0)
    var bitangent: float3 = float3(0, 1, 0)
}

extension ModelConstants: sizeable {}

extension SceneConstants: sizeable {}

extension ShaderMaterial: sizeable {
    init() {
        self.init(color: BLACK_COLOR,
                  useMaterialColor: false,
                  isLit: true,
                  useBaseTexture: false,
                  useNormalMapTexture: false,
                  useSpecularTexture: false,
                  ambient: float3(0.1, 0.1, 0.1),
                  diffuse: float3(1, 1, 1),
                  specular: float3(1, 1, 1),
                  shininess: 2)
    }
    
    mutating func setColor(_ color: float4) {
        self.color = color
        self.useMaterialColor = true
    }
}

extension LightData: sizeable {
    init() {
        self.init(type: Directional,
                  modelMatrix: matrix_identity_float4x4,
                  viewProjectionMatrix: matrix_identity_float4x4,
                  shadowViewProjectionMatrix: matrix_identity_float4x4,
                  shadowTransformMatrix: matrix_identity_float4x4,
                  lightEyeDirection: float3(0, 0, 0),
                  position: float3(0, 0, 0),
                  color: float3(1, 1, 1),
                  brightness: 1.0,
                  radius: 1.0,
                  ambientIntensity: 1.0,
                  diffuseIntensity: 1.0,
                  specularIntensity: 1.0)
    }
}

extension TFSBufferIndices {
    var index: Int {
      return Int(self.rawValue)
    }
}

extension TFSVertexAttributes {
    var index: Int {
      return Int(self.rawValue)
    }
}

extension TFSTextureIndices {
    var index: Int {
      return Int(self.rawValue)
    }
}

extension TFSRenderTargetIndices {
    var index: Int {
      return Int(self.rawValue)
    }
}
