//
//  AABB.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2025-08-23.
//

import Foundation
import simd

/// Axis-Aligned Bounding Box for broad-phase collision detection
public struct AABB {
    public var min: float3
    public var max: float3
    
    /// Initialize AABB with min and max points
    public init(min: float3, max: float3) {
        self.min = min
        self.max = max
    }
    
    /// Initialize AABB from center and half-extents
    public init(center: float3, halfExtents: float3) {
        self.min = center - halfExtents
        self.max = center + halfExtents
    }
    
    /// Initialize AABB for a sphere
    public init(center: float3, radius: Float) {
        let radiusVec = float3(radius, radius, radius)
        self.min = center - radiusVec
        self.max = center + radiusVec
    }
    
    /// Check if this AABB overlaps with another AABB
    public func overlaps(_ other: AABB) -> Bool {
        // Two AABBs overlap if they overlap on all three axes
        return (min.x <= other.max.x && max.x >= other.min.x) &&
               (min.y <= other.max.y && max.y >= other.min.y) &&
               (min.z <= other.max.z && max.z >= other.min.z)
    }
    
    /// Check if this AABB overlaps with another on a specific axis
    public func overlapsOnAxis(_ other: AABB, axis: Int) -> Bool {
        switch axis {
        case 0: // X axis
            return min.x <= other.max.x && max.x >= other.min.x
        case 1: // Y axis
            return min.y <= other.max.y && max.y >= other.min.y
        case 2: // Z axis
            return min.z <= other.max.z && max.z >= other.min.z
        default:
            return false
        }
    }
    
    /// Expand the AABB by a given radius in all directions
    public func expandedBy(_ radius: Float) -> AABB {
        let expansion = float3(radius, radius, radius)
        return AABB(min: min - expansion, max: max + expansion)
    }
    
    /// Get the center point of the AABB
    public var center: float3 {
        return (min + max) * 0.5
    }
    
    /// Get the size (dimensions) of the AABB
    public var size: float3 {
        return max - min
    }
    
    /// Get the half-extents of the AABB
    public var halfExtents: float3 {
        return size * 0.5
    }
    
    /// Merge this AABB with another to create a combined AABB
    public func merged(with other: AABB) -> AABB {
        return AABB(
            min: float3(
                Swift.min(min.x, other.min.x),
                Swift.min(min.y, other.min.y),
                Swift.min(min.z, other.min.z)
            ),
            max: float3(
                Swift.max(max.x, other.max.x),
                Swift.max(max.y, other.max.y),
                Swift.max(max.z, other.max.z)
            )
        )
    }
    
    /// Check if a point is contained within this AABB
    public func contains(_ point: float3) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }
}

// MARK: - Equatable
extension AABB: Equatable {
    public static func == (lhs: AABB, rhs: AABB) -> Bool {
        // Use epsilon comparison for floating point equality
        let epsilon: Float = 1e-6
        return simd_distance(lhs.min, rhs.min) < epsilon &&
               simd_distance(lhs.max, rhs.max) < epsilon
    }
}

// MARK: - Debug Description
extension AABB: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "AABB(min: [\(min.x), \(min.y), \(min.z)], max: [\(max.x), \(max.y), \(max.z)])"
    }
}