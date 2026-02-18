//
//  AnimationMask.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Defines which joints and meshes an animation layer controls.
/// Used to isolate animation updates to only the affected parts of a model.
struct AnimationMask {
    /// Joint paths that this mask includes (e.g., "Armature/LandingGear/MainGearLeft")
    let jointPaths: Set<String>

    /// Mesh indices that this mask includes (for transform-based animation)
    let meshIndices: Set<Int>

    // MARK: - Initialization

    /// Creates a mask with only joint paths
    /// - Parameter jointPaths: Array of joint path strings to include
    init(jointPaths: [String]) {
        self.jointPaths = Set(jointPaths)
        self.meshIndices = []
    }

    /// Creates a mask with only mesh indices
    /// - Parameter meshIndices: Array of mesh indices to include
    init(meshIndices: [Int]) {
        self.jointPaths = []
        self.meshIndices = Set(meshIndices)
    }

    /// Creates a mask with both joints and meshes
    /// - Parameters:
    ///   - jointPaths: Array of joint path strings to include
    ///   - meshIndices: Array of mesh indices to include
    init(jointPaths: [String], meshIndices: [Int]) {
        self.jointPaths = Set(jointPaths)
        self.meshIndices = Set(meshIndices)
        
        print("[AnimationMask init] jointPaths: \(jointPaths), meshIndices: \(meshIndices)")
    }

    // MARK: - Query Methods

    /// Check if a joint path is included in this mask
    /// - Parameter jointPath: The joint path to check
    /// - Returns: True if the joint is controlled by this mask
    func contains(jointPath: String) -> Bool {
        jointPaths.contains(jointPath)
    }

    /// Check if a mesh index is included in this mask
    /// - Parameter meshIndex: The mesh index to check
    /// - Returns: True if the mesh is controlled by this mask
    func contains(meshIndex: Int) -> Bool {
        meshIndices.contains(meshIndex)
    }

    /// Check if this mask has any joint paths defined
    var hasJoints: Bool {
        !jointPaths.isEmpty
    }

    /// Check if this mask has any mesh indices defined
    var hasMeshes: Bool {
        !meshIndices.isEmpty
    }

    /// Check if this mask is empty (controls nothing)
    var isEmpty: Bool {
        jointPaths.isEmpty && meshIndices.isEmpty
    }

    // MARK: - Static Constructors

    /// An empty mask that affects nothing
    static let empty = AnimationMask(jointPaths: [], meshIndices: [])

    /// Creates a mask that affects all joints in a skeleton and all meshes
    /// - Parameters:
    ///   - jointPaths: All joint paths in the skeleton
    ///   - meshCount: Total number of meshes in the model
    /// - Returns: A mask covering all joints and meshes
    static func all(jointPaths: [String], meshCount: Int) -> AnimationMask {
        AnimationMask(jointPaths: jointPaths, meshIndices: Array(0..<meshCount))
    }

    /// Creates a mask by filtering joint paths that match a predicate
    /// - Parameters:
    ///   - allJointPaths: All available joint paths
    ///   - predicate: Filter function to select joints
    /// - Returns: A mask containing only matching joints
    static func filtered(from allJointPaths: [String], where predicate: (String) -> Bool) -> AnimationMask {
        let filtered = allJointPaths.filter(predicate)
        return AnimationMask(jointPaths: filtered)
    }
}

// MARK: - CustomStringConvertible

extension AnimationMask: CustomStringConvertible {
    var description: String {
        "AnimationMask(joints: \(jointPaths.count), meshes: \(meshIndices.count))"
    }
}

// MARK: - Equatable

extension AnimationMask: Equatable {
    static func == (lhs: AnimationMask, rhs: AnimationMask) -> Bool {
        lhs.jointPaths == rhs.jointPaths && lhs.meshIndices == rhs.meshIndices
    }
}
