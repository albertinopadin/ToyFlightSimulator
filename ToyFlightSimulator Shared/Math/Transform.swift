//
//  Transform.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/24/23.
//

import simd

// From: https://developer.apple.com/documentation/metal/metal_sample_code_library/rendering_a_scene_with_deferred_lighting_in_swift
enum Transform {
    /// A 4x4 translation matrix specified by x, y, and z components.
    static func translationMatrix(_ translation: SIMD3<Float>) -> simd_float4x4 {
        let col0 = SIMD4<Float>(1, 0, 0, 0)
        let col1 = SIMD4<Float>(0, 1, 0, 0)
        let col2 = SIMD4<Float>(0, 0, 1, 0)
        let col3 = SIMD4<Float>(translation, 1)
        return .init(col0, col1, col2, col3)
    }
    
    /// A 4x4 rotation matrix specified by an angle and an axis or rotation.
    static func rotationMatrix(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        let normalizedAxis = simd_normalize(axis)
        
        let ct = cosf(radians)
        let st = sinf(radians)
        let ci = 1 - ct
        let x = normalizedAxis.x
        let y = normalizedAxis.y
        let z = normalizedAxis.z
        
        let col0 = SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0)
        let col1 = SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0)
        let col2 = SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0)
        let col3 = SIMD4<Float>(0, 0, 0, 1)
        
        return .init(col0, col1, col2, col3)
    }
    
    /// A 4x4 uniform scale matrix specified by x, y, and z components.
    static func scaleMatrix(_ scale: SIMD3<Float>) -> simd_float4x4 {
        let col0 = SIMD4<Float>(scale.x, 0, 0, 0)
        let col1 = SIMD4<Float>(0, scale.y, 0, 0)
        let col2 = SIMD4<Float>(0, 0, scale.z, 0)
        let col3 = SIMD4<Float>(0, 0, 0, 1)
        
        return .init(col0, col1, col2, col3)
    }
    
    /// Returns a 3x3 normal matrix from a 4x4 model matrix
    static func normalMatrix(from modelMatrix: simd_float4x4) -> simd_float3x3 {
        let col0 = modelMatrix.columns.0.xyz
        let col1 = modelMatrix.columns.1.xyz
        let col2 = modelMatrix.columns.2.xyz
        return .init(col0, col1, col2)
    }
    
    /// A left-handed orthographic projection
    static func orthographicProjection(_ left: Float,
                                       _ right: Float,
                                       _ bottom: Float,
                                       _ top: Float,
                                       _ nearZ: Float,
                                       _ farZ: Float) -> simd_float4x4 {
        
        let col0 = SIMD4<Float>(2 / (right - left), 0, 0, 0)
        let col1 = SIMD4<Float>(0, 2 / (top - bottom), 0, 0)
        let col2 = SIMD4<Float>(0, 0, 1 / (farZ - nearZ), 0)
        let col3 = SIMD4<Float>((left + right) / (left - right), (top + bottom) / (bottom - top), nearZ / (nearZ - farZ), 1)
        return .init(col0, col1, col2, col3)
    }
    
    /// A left-handed perspective projection
    static func perspectiveProjection(_ fovyRadians: Float,
                                      _ aspectRatio: Float,
                                      _ nearZ: Float,
                                      _ farZ: Float) -> simd_float4x4 {
        let ys = 1 / tanf(fovyRadians * 0.5)
        let xs = ys / aspectRatio
        let zs = farZ / (farZ - nearZ)
        
        let col0 = SIMD4<Float>(xs, 0, 0, 0)
        let col1 = SIMD4<Float>(0, ys, 0, 0)
        let col2 = SIMD4<Float>(0, 0, zs, 1)
        let col3 = SIMD4<Float>(0, 0, -nearZ * zs, 0)
        
        return .init(col0, col1, col2, col3)
    }
    
    /// Returns a left-handed matrix which looks from a point (the "eye") at a target point, given the up vector.
    static func look(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        
        let z = normalize(target - eye)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        let t = SIMD3<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye))
        
        let col0 = SIMD4<Float>(x.x, y.x, z.x, 0)
        let col1 = SIMD4<Float>(x.y, y.y, z.y, 0)
        let col2 = SIMD4<Float>(x.z, y.z, z.z, 0)
        let col3 = SIMD4<Float>(t.x, t.y, t.z, 1)
        
        return .init(col0, col1, col2, col3)
    }
    
    // Adapted from ChatGPT-4:
    static func decomposeToEulers(_ rotationMatrix: matrix_float4x4) -> float3 {
        let _v = rotationMatrix.columns.0.x * rotationMatrix.columns.0.x + rotationMatrix.columns.1.x * rotationMatrix.columns.1.x
        let sy = sqrt(_v)
        let isSingular = sy < 1e-6
        var x, y, z: Float
        if !isSingular {
            x = atan2(rotationMatrix.columns.2.y, rotationMatrix.columns.2.z)
            y = atan2(-rotationMatrix.columns.2.x, sy)
            z = atan2(rotationMatrix.columns.1.x, rotationMatrix.columns.0.x)
        } else {
            x = atan2(-rotationMatrix.columns.1.z, rotationMatrix.columns.1.y)
            y = atan2(-rotationMatrix.columns.2.x, sy)
            z = 0
        }
//        return float3(x: x, y: y, z: z)  // Right-handed coordinate system
//        return float3(x: -x, y: -y, z: z)  // Left-handed coordinate system
        return float3(x: -x, y: -y, z: z)
    }
}
