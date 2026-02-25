//
//  Skeleton.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/31/25.
//  HEAVILY based on Metal by Tutorials v5 from Kodeco: https://www.kodeco.com/books/metal-by-tutorials/v5.0/
//


///// Copyright (c) 2023 Kodeco Inc.
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import MetalKit

class Skeleton {
    let parentIndices: [Int?]
    let jointPaths: [String]
    let bindTransforms: [float4x4]
    let restTransforms: [float4x4]
    var currentPose: [float4x4] = []

    /// Persistent local poses, updated incrementally by clip and procedural channels.
    /// Initialized to rest transforms. Clip channels write to joints in their mask,
    /// procedural channels override their targeted joints. evaluateWorldPoses() then
    /// computes the final world-space currentPose from these local poses.
    private(set) var localPoses: [float4x4]

    /// Optional basis transform for coordinate system conversion (e.g., USDZ to game coords)
    let basisTransform: float4x4?

    init?(mdlSkeleton: MDLSkeleton?, basisTransform: float4x4? = nil) {
        guard let mdlSkeleton, !mdlSkeleton.jointPaths.isEmpty else { return nil }
        self.basisTransform = basisTransform
        jointPaths = mdlSkeleton.jointPaths
        parentIndices = Skeleton.getParentIndices(jointPaths: jointPaths)
        bindTransforms = mdlSkeleton.jointBindTransforms.float4x4Array
        restTransforms = mdlSkeleton.jointRestTransforms.float4x4Array
        localPoses = restTransforms
    }

    static func getParentIndices(jointPaths: [String]) -> [Int?] {
        var parentIndices = [Int?](repeating: nil, count: jointPaths.count)
        for (jointIndex, jointPath) in jointPaths.enumerated() {
            let url = URL(fileURLWithPath: jointPath)
            let parentPath = url.deletingLastPathComponent().relativePath
            parentIndices[jointIndex] = jointPaths.firstIndex {
                $0 == parentPath
            }
        }
        return parentIndices
    }

    func mapJoints(from jointPaths: [String]) -> [Int] {
        jointPaths.compactMap { jointPath in
            self.jointPaths.firstIndex(of: jointPath)
        }
    }

    // MARK: - Legacy Full-Skeleton Update (Backward Compatibility)

    /// Updates the full skeleton pose from an animation clip. Writes all joints to localPoses
    /// and immediately evaluates world poses. Convenience wrapper around applyClip + evaluateWorldPoses.
    func updatePose(at currentTime: Float, animationClip: AnimationClip) {
        let time = min(currentTime, animationClip.duration)

        for index in 0..<jointPaths.count {
            let pose = animationClip.getPose(at: time * animationClip.speed,
                                             jointPath: jointPaths[index]) ?? restTransforms[index]
            localPoses[index] = pose
        }

        evaluateWorldPoses()
    }

    // MARK: - Incremental Pose API

    /// Applies an animation clip to localPoses, filtered by a mask.
    /// Only joints whose paths are in the mask are updated; others are left unchanged.
    /// Call evaluateWorldPoses() after all channels have applied their data.
    ///
    /// - Parameters:
    ///   - currentTime: The time to sample the clip at
    ///   - animationClip: The clip to sample
    ///   - mask: Only joints in this mask are written to localPoses
    func applyClip(at currentTime: Float, animationClip: AnimationClip, mask: AnimationMask) {
        let time = min(currentTime, animationClip.duration)

        for index in 0..<jointPaths.count {
            let jointPath = jointPaths[index]
            guard mask.jointPaths.isEmpty || mask.contains(jointPath: jointPath) else { continue }

            let pose = animationClip.getPose(at: time * animationClip.speed,
                                             jointPath: jointPath) ?? restTransforms[index]
            localPoses[index] = pose
        }
    }

    /// Applies procedural rotation overrides to specific joints in localPoses.
    /// Each override is a rotation matrix that is multiplied with the joint's rest transform:
    ///   localPoses[joint] = restTransform * rotationOverride
    /// Only the specified joints are modified; all others are left unchanged.
    /// Call evaluateWorldPoses() after all channels have applied their data.
    ///
    /// - Parameter overrides: Dictionary of joint path -> local rotation matrix to apply
    func applyProceduralOverrides(_ overrides: [String: float4x4]) {
        for (jointPath, rotationOverride) in overrides {
            guard let index = jointPaths.firstIndex(of: jointPath) else { continue }
            localPoses[index] = restTransforms[index] * rotationOverride
        }
    }

    /// Computes world-space currentPose from the accumulated localPoses.
    /// Call this once per frame after all clip and procedural channels have written to localPoses.
    func evaluateWorldPoses() {
        var worldPose = [float4x4]()
        worldPose.reserveCapacity(parentIndices.count)

        for index in 0..<parentIndices.count {
            let parentIndex = parentIndices[index]
            let localMatrix = localPoses[index]
            if let parentIndex {
                worldPose.append(worldPose[parentIndex] * localMatrix)
            } else {
                worldPose.append(localMatrix)
            }
        }

        for index in 0..<worldPose.count {
            worldPose[index] *= bindTransforms[index].inverse
        }

        // Apply basis transform to convert joint matrices to the game's coordinate system.
        // This is necessary when the mesh vertices have been transformed by basisTransform,
        // so the joint matrices must also be conjugated: B * J * B^(-1)
        if let basisTransform {
            let basisInverse = basisTransform.inverse
            for index in 0..<worldPose.count {
                worldPose[index] = basisTransform * worldPose[index] * basisInverse
            }
        }

        currentPose = worldPose
    }
}
