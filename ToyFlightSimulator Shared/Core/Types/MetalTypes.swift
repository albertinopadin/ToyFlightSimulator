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

protocol sizeable {}

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

extension Particle: sizeable {}

public protocol HasNormal {
    var normal: float3 { get set }
}

struct Vertex: HasNormal, sizeable {
    var position: float3 = [0, 0, 0]
    var color: float4 = [0, 0, 0, 1]
    var textureCoordinate: float2 = [0, 0]
    var normal: float3 = [0, 0, 1]
    var tangent: float3 = [1, 0, 0]
    var bitangent: float3 = [0, 1, 0]
}

extension ModelConstants: sizeable {}

extension SceneConstants: sizeable {}

extension MaterialProperties: sizeable {
    init() {
        self.init(color: BLACK_COLOR,
                  ambient: [0.1, 0.1, 0.1], 
                  diffuse: [1, 1, 1],
                  specular: [1, 1, 1],
                  shininess: 2.0,
                  opacity: 1.0,
                  useMaterialColor: false,
                  isLit: true)
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
                  lightEyeDirection: [0, 0, 0],
                  position: [0, 0, 0],
                  color: [1, 1, 1],
                  brightness: 1.0,
                  radius: 1.0,
                  attenuation: [1, 1, 1],
                  ambientIntensity: 1.0,
                  diffuseIntensity: 1.0,
                  specularIntensity: 1.0)
    }
}

protocol TFSIndices: RawRepresentable<UInt32> {
    var index: Int { get }
}

extension TFSIndices {
    var index: Int {
        return Int(self.rawValue)
    }
}

extension TFSBufferIndices: TFSIndices { }
extension TFSVertexAttributes: TFSIndices { }
extension TFSTextureIndices: TFSIndices { }
extension TFSRenderTargetIndices: TFSIndices { }
