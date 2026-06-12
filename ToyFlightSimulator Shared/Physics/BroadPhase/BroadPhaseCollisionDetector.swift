//
//  BroadPhaseCollisionDetector.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2025-08-23.
//

import Foundation
import simd

/// Broad-phase collision detector using single-axis sweep and prune.
///
/// Per-frame flow (all scratch storage reused across frames — zero steady-state
/// allocation):
///   1. Partition entities into static/dynamic and compute every AABB exactly
///      once (one weak-ref dereference per entity per frame).
///   2. Sort an index array by cached `aabb.min.x`. For the entity counts this
///      engine targets (~10²–10³), a full sort over cached Float keys is
///      cheaper than the old "decide whether to re-sort" machinery, which
///      itself cost O(n) getPosition() + String-keyed dictionary work per
///      frame before any sorting happened.
///   3. Sweep the sorted order, emitting candidate pairs.
final class BroadPhaseCollisionDetector {
    // MARK: - Reused per-frame scratch (P3: no per-frame allocations)

    private var staticEntities: [RigidBody] = []
    private var staticAABBs: [AABB] = []
    private var dynamicEntities: [RigidBody] = []
    private var dynamicAABBs: [AABB] = []
    /// Indices into dynamicEntities/dynamicAABBs, sorted by aabb.min.x.
    private var sortedDynamicIndices: [Int] = []
    private var pairsScratch: [(RigidBody, RigidBody)] = []

    /// When false (default), CFAbsoluteTimeGetCurrent() calls and stat
    /// bookkeeping are skipped. PhysicsStressTestScene turns this on.
    var collectStatistics: Bool = false

    /// Statistics for debugging/optimization (only updated when
    /// `collectStatistics` is true)
    private(set) var lastFrameStats = BroadPhaseStats()

    // MARK: - Public Methods

    /// Update the broad phase with current entities
    func update(entities: [RigidBody]) {
        let startTime = collectStatistics ? CFAbsoluteTimeGetCurrent() : 0

        staticEntities.removeAll(keepingCapacity: true)
        staticAABBs.removeAll(keepingCapacity: true)
        dynamicEntities.removeAll(keepingCapacity: true)
        dynamicAABBs.removeAll(keepingCapacity: true)

        // Single partition pass; getAABB() called exactly once per entity.
        for entity in entities {
            if entity.isStatic {
                staticEntities.append(entity)
                staticAABBs.append(entity.getAABB())
            } else {
                dynamicEntities.append(entity)
                dynamicAABBs.append(entity.getAABB())
            }
        }

        // Sort indices by cached min.x — no getAABB() calls in the comparator.
        sortedDynamicIndices.removeAll(keepingCapacity: true)
        sortedDynamicIndices.append(contentsOf: 0..<dynamicEntities.count)
        sortedDynamicIndices.sort { dynamicAABBs[$0].min.x < dynamicAABBs[$1].min.x }

        if collectStatistics {
            lastFrameStats.updateTime = CFAbsoluteTimeGetCurrent() - startTime
            lastFrameStats.dynamicEntityCount = dynamicEntities.count
            lastFrameStats.staticEntityCount = staticEntities.count
            lastFrameStats.didFullSort = true
        }
    }

    /// Get potential collision pairs after broad-phase filtering.
    ///
    /// IMPORTANT: the returned array is internal scratch, reused next frame.
    /// Consume it within the current physics step; do not store it. (A stale
    /// strong reference would silently trigger a CoW copy on the next
    /// removeAll — a perf bug, not a correctness one.)
    func getPotentialCollisionPairs() -> [(RigidBody, RigidBody)] {
        let startTime = collectStatistics ? CFAbsoluteTimeGetCurrent() : 0
        var checksPerformed = 0
        var checksSaved = 0

        pairsScratch.removeAll(keepingCapacity: true)

        // Dynamic vs Dynamic collision pairs (sweep and prune along sorted X):
        let sortedCount = sortedDynamicIndices.count
        for si in 0..<sortedCount {
            let i = sortedDynamicIndices[si]
            let aabbA = dynamicAABBs[i]

            for sj in (si + 1)..<sortedCount {
                let j = sortedDynamicIndices[sj]
                let aabbB = dynamicAABBs[j]

                checksPerformed += 1

                // Early exit when X ranges no longer overlap (key optimization):
                // all remaining entities in the sorted order also fail this test.
                if aabbB.min.x > aabbA.max.x {
                    checksSaved += (sortedCount - sj - 1)
                    break
                }

                // Check full AABB overlap (Y and Z axes)
                if aabbA.overlaps(aabbB) {
                    pairsScratch.append((dynamicEntities[i], dynamicEntities[j]))
                }
            }
        }

        // Dynamic vs Static collision pairs:
        for di in 0..<dynamicEntities.count {
            let dynamicAABB = dynamicAABBs[di]

            for si in 0..<staticEntities.count {
                checksPerformed += 1

                if dynamicAABB.overlaps(staticAABBs[si]) {
                    pairsScratch.append((dynamicEntities[di], staticEntities[si]))
                }
            }
        }

        if collectStatistics {
            let dynamicCount = dynamicEntities.count
            let staticCount = staticEntities.count
            let totalPossibleChecks = (dynamicCount * (dynamicCount - 1)) / 2 + (dynamicCount * staticCount)

            lastFrameStats.pairGenerationTime = CFAbsoluteTimeGetCurrent() - startTime
            lastFrameStats.checksPerformed = checksPerformed
            lastFrameStats.checksSaved = checksSaved + (totalPossibleChecks - checksPerformed)
            lastFrameStats.potentialPairs = pairsScratch.count
        }

        return pairsScratch
    }

    /// Reset the detector (useful for scene changes)
    func reset() {
        staticEntities.removeAll()
        staticAABBs.removeAll()
        dynamicEntities.removeAll()
        dynamicAABBs.removeAll()
        sortedDynamicIndices.removeAll()
        pairsScratch.removeAll()
        lastFrameStats = BroadPhaseStats()
    }

    /// Get statistics for performance analysis
    func getStatistics() -> (totalChecks: Int, checksSaved: Int) {
        return (lastFrameStats.checksPerformed, lastFrameStats.checksSaved)
    }
}

// MARK: - Statistics

/// Statistics for broad-phase performance monitoring
struct BroadPhaseStats {
    var updateTime: Double = 0
    var pairGenerationTime: Double = 0
    var dynamicEntityCount: Int = 0
    var staticEntityCount: Int = 0
    var checksPerformed: Int = 0
    var checksSaved: Int = 0
    var potentialPairs: Int = 0
    var didFullSort: Bool = false

    var totalTime: Double {
        return updateTime + pairGenerationTime
    }

    var compressionRatio: Double {
        let totalEntities = dynamicEntityCount + staticEntityCount
        let totalPossiblePairs = (totalEntities * (totalEntities - 1)) / 2
        guard totalPossiblePairs > 0 else { return 0 }
        return Double(checksSaved) / Double(totalPossiblePairs)
    }
}

// MARK: - Debug Description

extension BroadPhaseCollisionDetector: CustomDebugStringConvertible {
    var debugDescription: String {
        return """
        BroadPhaseCollisionDetector:
          Dynamic Entities: \(dynamicEntities.count)
          Static Entities: \(staticEntities.count)
          Collect Statistics: \(collectStatistics)
          Last Frame Stats:
            - Update Time: \(String(format: "%.3f ms", lastFrameStats.updateTime * 1000))
            - Pair Gen Time: \(String(format: "%.3f ms", lastFrameStats.pairGenerationTime * 1000))
            - Checks Performed: \(lastFrameStats.checksPerformed)
            - Checks Saved: \(lastFrameStats.checksSaved)
            - Compression Ratio: \(String(format: "%.1f%%", lastFrameStats.compressionRatio * 100))
            - Potential Pairs: \(lastFrameStats.potentialPairs)
        """
    }
}
