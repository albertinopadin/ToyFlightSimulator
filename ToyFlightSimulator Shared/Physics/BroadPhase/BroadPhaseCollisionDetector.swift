//
//  BroadPhaseCollisionDetector.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2025-08-23.
//

import Foundation
import simd

/// Broad-phase collision detector using Single-Axis Sweep and Prune algorithm
final class BroadPhaseCollisionDetector {
    // MARK: - Properties
    
    /// Sorted list of dynamic entities (sorted by X-axis minimum)
    private var sortedDynamicEntities: [PhysicsEntity] = []
    
    /// List of static entities (no need to sort these)
    private var staticEntities: [PhysicsEntity] = []
    
    /// Track last frame positions to detect significant movement
    private var lastFramePositions: [String: float3] = [:]
    
    /// Threshold for triggering a full re-sort (in world units)
    private let resortThreshold: Float = 5.0
    
    /// Track if this is the first frame (needs full sort)
    private var isFirstFrame: Bool = true
    
    /// Statistics for debugging/optimization
    private(set) var lastFrameStats = BroadPhaseStats()
    
    // MARK: - Public Methods
    
    /// Update the broad phase with current entities
    func update(entities: [PhysicsEntity]) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Separate static and dynamic entities
        staticEntities = entities.filter { $0.isStatic }
        let dynamicEntities = entities.filter { $0.isDynamic }
        
        if dynamicEntities.isEmpty {
            return
        }
        
        // Check if we need a full sort or can use insertion sort
        let needsFullSort = shouldPerformFullSort(dynamicEntities)
        
        if needsFullSort {
            performFullSort(dynamicEntities)
            lastFrameStats.didFullSort = true
        } else {
            performInsertionSort(dynamicEntities)
            lastFrameStats.didFullSort = false
        }
        
        // Update position tracking for next frame
        updateLastFramePositions(dynamicEntities)
        
        // Update statistics
        let endTime = CFAbsoluteTimeGetCurrent()
        lastFrameStats.updateTime = endTime - startTime
        lastFrameStats.dynamicEntityCount = dynamicEntities.count
        lastFrameStats.staticEntityCount = staticEntities.count
        
        isFirstFrame = false
    }
    
    /// Get potential collision pairs after broad-phase filtering
    func getPotentialCollisionPairs() -> [(PhysicsEntity, PhysicsEntity)] {
        let startTime = CFAbsoluteTimeGetCurrent()
        var pairs: [(PhysicsEntity, PhysicsEntity)] = []
        var checksPerformed = 0
        var checksSaved = 0
        
        // Dynamic vs Dynamic collision pairs (using sweep and prune)
        for i in 0..<sortedDynamicEntities.count {
            let entityA = sortedDynamicEntities[i]
            let aabbA = entityA.getAABB()
            
            // Only check entities whose X ranges might overlap
            for j in (i + 1)..<sortedDynamicEntities.count {
                let entityB = sortedDynamicEntities[j]
                let aabbB = entityB.getAABB()
                
                checksPerformed += 1
                
                // Early exit when X ranges no longer overlap (key optimization)
                if aabbB.min.x > aabbA.max.x {
                    // All remaining entities in the sorted list will also fail this test
                    checksSaved += (sortedDynamicEntities.count - j - 1)
                    break
                }
                
                // Check full AABB overlap (Y and Z axes)
                if aabbA.overlaps(aabbB) {
                    pairs.append((entityA, entityB))
                }
            }
        }
        
        // Dynamic vs Static collision pairs
        for dynamicEntity in sortedDynamicEntities {
            let dynamicAABB = dynamicEntity.getAABB()
            
            for staticEntity in staticEntities {
                checksPerformed += 1
                
                // Simple AABB overlap check
                if dynamicAABB.overlaps(staticEntity.getAABB()) {
                    pairs.append((dynamicEntity, staticEntity))
                }
            }
        }
        
        // Calculate total possible checks for statistics
        let dynamicCount = sortedDynamicEntities.count
        let staticCount = staticEntities.count
        let totalPossibleChecks = (dynamicCount * (dynamicCount - 1)) / 2 + (dynamicCount * staticCount)
        
        // Update statistics
        let endTime = CFAbsoluteTimeGetCurrent()
        lastFrameStats.pairGenerationTime = endTime - startTime
        lastFrameStats.checksPerformed = checksPerformed
        lastFrameStats.checksSaved = checksSaved + (totalPossibleChecks - checksPerformed)
        lastFrameStats.potentialPairs = pairs.count
        
        return pairs
    }
    
    /// Reset the detector (useful for scene changes)
    func reset() {
        sortedDynamicEntities.removeAll()
        staticEntities.removeAll()
        lastFramePositions.removeAll()
        isFirstFrame = true
        lastFrameStats = BroadPhaseStats()
    }
    
    /// Get statistics for performance analysis
    func getStatistics() -> (totalChecks: Int, checksSaved: Int) {
        return (lastFrameStats.checksPerformed, lastFrameStats.checksSaved)
    }
    
    // MARK: - Private Methods
    
    /// Check if we need to perform a full sort
    private func shouldPerformFullSort(_ dynamicEntities: [PhysicsEntity]) -> Bool {
        // Always sort on first frame
        if isFirstFrame {
            return true
        }
        
        // Check if entity count changed significantly
        if abs(dynamicEntities.count - sortedDynamicEntities.count) > 5 {
            return true
        }
        
        // Check if any entity moved significantly
        for entity in dynamicEntities {
            if let lastPos = lastFramePositions[entity.id] {
                let currentPos = entity.getPosition()
                let movement = simd_distance(currentPos, lastPos)
                
                if movement > resortThreshold {
                    return true
                }
            } else {
                // New entity added
                return true
            }
        }
        
        return false
    }
    
    /// Perform a full sort of dynamic entities by X-axis minimum
    private func performFullSort(_ dynamicEntities: [PhysicsEntity]) {
        sortedDynamicEntities = dynamicEntities.sorted { entityA, entityB in
            entityA.getAABB().min.x < entityB.getAABB().min.x
        }
    }
    
    /// Perform insertion sort for nearly-sorted list (frame-to-frame updates)
    private func performInsertionSort(_ dynamicEntities: [PhysicsEntity]) {
        // Start with existing sorted list
        var sorted = sortedDynamicEntities
        
        // Update with current entities (handle additions/removals)
        let currentIds = Set(dynamicEntities.map { $0.id })
        let sortedIds = Set(sorted.map { $0.id })
        
        // Remove entities that no longer exist
        sorted.removeAll { !currentIds.contains($0.id) }
        
        // Add new entities
        let newEntities = dynamicEntities.filter { !sortedIds.contains($0.id) }
        for newEntity in newEntities {
            // Insert in sorted position
            let aabb = newEntity.getAABB()
            let insertIndex = sorted.firstIndex { $0.getAABB().min.x > aabb.min.x } ?? sorted.count
            sorted.insert(newEntity, at: insertIndex)
        }
        
        // Update existing entities and maintain sort
        // Use insertion sort since list is nearly sorted
        for i in 1..<sorted.count {
            let entity = sorted[i]
            let aabb = entity.getAABB()
            var j = i - 1
            
            // Move entity left if needed
            while j >= 0 && sorted[j].getAABB().min.x > aabb.min.x {
                sorted[j + 1] = sorted[j]
                j -= 1
            }
            
            if j + 1 != i {
                sorted[j + 1] = entity
            }
        }
        
        sortedDynamicEntities = sorted
    }
    
    /// Update position tracking for movement detection
    private func updateLastFramePositions(_ dynamicEntities: [PhysicsEntity]) {
        lastFramePositions.removeAll()
        
        for entity in dynamicEntities {
            lastFramePositions[entity.id] = entity.getPosition()
        }
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
          Dynamic Entities: \(sortedDynamicEntities.count)
          Static Entities: \(staticEntities.count)
          Last Frame Stats:
            - Update Time: \(String(format: "%.3f ms", lastFrameStats.updateTime * 1000))
            - Pair Gen Time: \(String(format: "%.3f ms", lastFrameStats.pairGenerationTime * 1000))
            - Checks Performed: \(lastFrameStats.checksPerformed)
            - Checks Saved: \(lastFrameStats.checksSaved)
            - Compression Ratio: \(String(format: "%.1f%%", lastFrameStats.compressionRatio * 100))
            - Potential Pairs: \(lastFrameStats.potentialPairs)
            - Did Full Sort: \(lastFrameStats.didFullSort)
        """
    }
}
