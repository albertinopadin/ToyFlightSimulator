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
    /// A1: bind matrices never change — inverted once at load instead of per
    /// joint per evaluateWorldPoses() call.
    let inverseBindTransforms: [float4x4]
    /// A2: O(1) jointPath → index lookups at channel-registration time
    /// (replaces firstIndex(of:) linear String scans). First index wins on
    /// duplicate paths, matching firstIndex semantics.
    let jointIndexByPath: [String: Int]
    var currentPose: [float4x4] = []

    /// Persistent local poses, updated incrementally by clip and procedural channels.
    /// Initialized to rest transforms. Clip channels write to joints in their mask,
    /// procedural channels override their targeted joints. evaluateWorldPoses() then
    /// computes the final world-space currentPose from these local poses.
    private(set) var localPoses: [float4x4]

    /// Optional basis transform for coordinate system conversion (e.g., USDZ to game coords)
    let basisTransform: float4x4?
    /// A1: constant per skeleton — computed once instead of per evaluate call.
    private let inverseBasisTransform: float4x4?

    init?(mdlSkeleton: MDLSkeleton?, basisTransform: float4x4? = nil) {
        guard let mdlSkeleton, !mdlSkeleton.jointPaths.isEmpty else { return nil }
        self.basisTransform = basisTransform
        self.inverseBasisTransform = basisTransform?.inverse
        jointPaths = mdlSkeleton.jointPaths
        parentIndices = Skeleton.getParentIndices(jointPaths: jointPaths)
        bindTransforms = mdlSkeleton.jointBindTransforms.float4x4Array
        inverseBindTransforms = bindTransforms.map { $0.inverse }
        restTransforms = mdlSkeleton.jointRestTransforms.float4x4Array
        localPoses = restTransforms
        jointIndexByPath = Dictionary(jointPaths.enumerated().map { ($1, $0) },
                                      uniquingKeysWith: { first, _ in first })
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
            self.jointIndexByPath[jointPath]
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

    /// A3: applies an animation clip to localPoses over registration-resolved
    /// (jointIndex, animation) pairs — no mask Set lookups and no per-joint
    /// dictionary lookups on the per-frame path.
    /// `animation == nil` means the clip has no track for that joint → rest
    /// pose, matching the old `getPose(...) ?? restTransforms[index]` fallback.
    /// Call evaluateWorldPoses() after all channels have applied their data.
    ///
    /// - Parameters:
    ///   - currentTime: The time to sample the clip at
    ///   - animationClip: The clip being sampled (supplies duration/speed)
    ///   - resolvedJoints: Masked joints resolved at channel registration
    func applyClip(at currentTime: Float,
                   animationClip: AnimationClip,
                   resolvedJoints: [(jointIndex: Int, animation: Animation?)]) {
        let time = min(currentTime, animationClip.duration) * animationClip.speed

        for (jointIndex, animation) in resolvedJoints {
            if let animation {
                localPoses[jointIndex] = animation.getPose(at: time)
            } else {
                localPoses[jointIndex] = restTransforms[jointIndex]
            }
        }
    }

    /// A2: applies procedural rotation overrides by pre-resolved joint index.
    /// `jointIndices[i]` pairs with `rotations[i]`; -1 marks a config whose
    /// joint path wasn't found in this skeleton (resolved and warned about at
    /// registration time). Each rotation is applied on top of the joint's rest
    /// transform: localPoses[joint] = restTransform * rotation.
    /// Call evaluateWorldPoses() after all channels have applied their data.
    func applyProceduralOverrides(jointIndices: [Int], rotations: [float4x4]) {
        for i in 0..<jointIndices.count {
            let index = jointIndices[i]
            guard index >= 0 else { continue }
            localPoses[index] = restTransforms[index] * rotations[i]
        }
    }

    /// Computes world-space currentPose from the accumulated localPoses.
    /// Call this once per frame after all clip and procedural channels have written to localPoses.
    /// A1: allocation-free — currentPose is written in place (parents precede
    /// children in joint order, so pass 1 can safely read freshly written
    /// parent poses from the same array), bind inverses are precomputed, and
    /// the basis conjugation is fused into the second pass.
    func evaluateWorldPoses() {
        let count = parentIndices.count
        if currentPose.count != count {
            currentPose = [float4x4](repeating: .identity, count: count)
        }

        // Pass 1: pure world poses.
        for index in 0..<count {
            let localMatrix = localPoses[index]
            if let parentIndex = parentIndices[index] {
                currentPose[index] = currentPose[parentIndex] * localMatrix
            } else {
                currentPose[index] = localMatrix
            }
        }

        // Pass 2: bind-inverse, with the basis conjugation fused in when present.
        // Apply basis transform to convert joint matrices to the game's coordinate system.
        // Mesh vertices are transformed as v_engine = v_model * B (row-vector convention),
        // while the shader skins as v_skinned = J * v (column-vector convention).
        // The correct conjugation is: J_engine = B^-1 * J_model * B
        if let basisTransform, let inverseBasisTransform {
            for index in 0..<count {
                currentPose[index] = inverseBasisTransform * (currentPose[index] * inverseBindTransforms[index]) * basisTransform
            }
        } else {
            for index in 0..<count {
                currentPose[index] *= inverseBindTransforms[index]
            }
        }
    }
}
