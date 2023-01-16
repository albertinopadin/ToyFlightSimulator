//
//  MetalTypes.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import simd


// --- OLD ---
//struct NodeConstants {
//    var modelMatrix: float4x4
//    var color: float4
//}
//
//struct LightConstants {
//    var viewProjectionMatrix: float4x4
//    var intensity: simd_float3
//    var position: simd_float3
//    var direction: simd_float3
//    var type: UInt32
//}
//
//struct FrameConstants {
//    var projectionMatrix: float4x4
//    var viewMatrix: float4x4
//    var inverseViewDirectionMatrix: float3x3
//    var lightCount: UInt32
//}
//
//struct InstanceConstants {
//    var modelMatrix: float4x4
//    var color: float4
//}


// --- NEW ---
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

struct ModelConstants: sizeable {
    var modelMatrix = matrix_identity_float4x4
}

struct SceneConstants: sizeable {
    var totalGameTime: Float = 0
    var viewMatrix = matrix_identity_float4x4
    var skyViewMatrix = matrix_identity_float4x4
    var projectionMatrix = matrix_identity_float4x4
    var cameraPosition = float3(0, 0, 0)
}

struct Material: sizeable {
    private var _color = float4(0, 0, 0, 0)
    var color: float4 {
        get {
            return _color
        }
        
        set {
            _color = newValue
            useMaterialColor = true
        }
    }
    
    var useMaterialColor: Bool = false
    var isLit: Bool = true
    
    // For GPU bugfix:
    var useBaseTexture: Bool = false
    var useNormalMapTexture: Bool = false
    
    var ambient: float3 = float3(0.1, 0.1, 0.1)
    var diffuse: float3 = float3(1, 1, 1)
    var specular: float3 = float3(1, 1, 1)
    var shininess: Float = 2
}

struct LightData: sizeable {
    var type: UInt32 = 0  // Warren Moore / 30 Days of Metal
    var viewProjectionMatrix: float4x4 = matrix_identity_float4x4  // Warren Moore / 30 Days of Metal
    var lightSpaceMatrix = matrix_identity_float4x4  // 2etime
    var translation: float3 = float3(0, 0, 0)
    var position: float3 = float3(0, 0, 0)
    var color: float3 = float3(0, 0, 0)
    var brightness: Float = 1.0
    
    var ambientIntensity: Float = 1.0
    var diffuseIntensity: Float = 1.0
    var specularIntensity: Float = 1.0
}

struct ShadowData: sizeable {
    var modelViewProjectionMatrix: simd_float4x4
}
