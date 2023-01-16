//
//  Math.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

import MetalKit

public var X_AXIS: float3 {
    return float3(1, 0, 0)
}

public var Y_AXIS: float3 {
    return float3(0, 1, 0)
}

public var Z_AXIS: float3 {
    return float3(0, 0, 1)
}

extension Float {
    var toRadians: Float {
        return (self / 180.0) * Float.pi
    }
    
    var toDegrees: Float {
        return self * (180.0 / Float.pi)
    }
    
    static var randomZeroToOne: Float {
        return Float(arc4random()) / Float(UINT32_MAX)
    }
}

extension matrix_float4x4 {
    mutating func translate(direction: float3) {
        var result = matrix_identity_float4x4
        
        let x: Float = direction.x
        let y: Float = direction.y
        let z: Float = direction.z
        
        result.columns = (
            float4(1, 0, 0, 0),
            float4(0, 1, 0, 0),
            float4(0, 0, 1, 0),
            float4(x, y, z, 1)
        )
        
        self = matrix_multiply(self, result)
    }
    
    mutating func scale(axis: float3) {
        var result = matrix_identity_float4x4
        
        let x: Float = axis.x
        let y: Float = axis.y
        let z: Float = axis.z
        
        result.columns = (
            float4(x, 0, 0, 0),
            float4(0, y, 0, 0),
            float4(0, 0, z, 0),
            float4(0, 0, 0, 1)
        )
        
        self = matrix_multiply(self, result)
    }
    
    // TODO: Better rotation function? Using quaternions perhaps...
    mutating func rotate(angle: Float, axis: float3) {
        var result = matrix_identity_float4x4
        
        let x: Float = axis.x
        let y: Float = axis.y
        let z: Float = axis.z
        
        let c: Float = cos(angle)
        let s: Float = sin(angle)
        
        let mc: Float = (1 - c)
        
        let r1c1: Float = x * x * mc + c
        let r2c1: Float = x * y * mc + z * s
        let r3c1: Float = x * z * mc - y * s
        let r4c1: Float = 0.0
        
        let r1c2: Float = y * x * mc - z * s
        let r2c2: Float = y * y * mc + c
        let r3c2: Float = y * z * mc + x * s
        let r4c2: Float = 0.0
        
        let r1c3: Float = z * x * mc + y * s
        let r2c3: Float = z * y * mc - x * s
        let r3c3: Float = z * z * mc + c
        let r4c3: Float = 0.0
        
        let r1c4: Float = 0.0
        let r2c4: Float = 0.0
        let r3c4: Float = 0.0
        let r4c4: Float = 1.0
        
        result.columns = (
            float4(r1c1, r2c1, r3c1, r4c1),
            float4(r1c2, r2c2, r3c2, r4c2),
            float4(r1c3, r2c3, r3c3, r4c3),
            float4(r1c4, r2c4, r3c4, r4c4)
        )
        
        self = matrix_multiply(self, result)
    }
    
    // https://gamedev.stackexchange.com/questions/120338/what-does-a-perspective-projection-matrix-look-like-in-opengl
    static func perspective(degreesFov: Float, aspectRatio: Float, near: Float, far: Float) -> matrix_float4x4 {
        let fov = degreesFov.toRadians
        
        let t: Float = tan(fov / 2)
        
        let x: Float = 1 / (aspectRatio * t)
        let y: Float = 1 / t
        let z: Float = -((far + near) / (far - near))
        let w: Float = -((2 * far * near) / (far - near))
        
        var result = matrix_identity_float4x4
        result.columns = (
            float4(x,  0,  0,  0),
            float4(0,  y,  0,  0),
            float4(0,  0,  z, -1),
            float4(0,  0,  w,  0)
        )
        return result
    }
    
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        return float4x4(
                [ 2 / (right - left), 0, 0, 0],
                [0, 2 / (top - bottom), 0, 0],
                [0, 0, 1 / (far - near), 0],
                [(left + right) / (left - right), (top + bottom) / (bottom - top), near / (near - far), 1]
            )
     }
    
    static func orthographic(width: Float, height: Float, length: Float) -> matrix_float4x4 {
        return float4x4 (
            [ Float(2.0) / width,   0,                      0,                      0 ],
            [ 0,                    Float(2.0) / height,    0,                      0 ],
            [ 0,                    0,                      Float(2.0) / length,    0 ],
            [ 0,                    0,                      0,                      Float(1.0) ]
        )
     }
    
    static func lookAt(eye: float3, center: float3, up: float3) -> matrix_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        let w = float3(dot(x, -eye), dot(y, -eye), dot(z, -eye))

        let X = float4(x.x, y.x, z.x, 0)
        let Y = float4(x.y, y.y, z.y, 0)
        let Z = float4(x.z, y.z, z.z, 0)
        let W = float4(w.x, w.y, x.z, 1)
        
        var result = matrix_identity_float4x4
        result.columns = (X, Y, Z, W)
        return result
    }
}
