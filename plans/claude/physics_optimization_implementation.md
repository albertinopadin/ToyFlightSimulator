# Physics Collision Detection Optimization Implementation Plan

## Executive Summary
Optimize the current O(n²) collision detection algorithm to achieve O(n log n) or better performance using a Single-Axis Sweep and Prune algorithm with static/dynamic entity separation.

## Current State Analysis

### Problems
- **O(n²) complexity** in HeckerCollisionResponse.swift (lines 23-24)
- Nested loops check every entity against every other entity
- Performance degrades rapidly with >50 entities
- No spatial partitioning or broad-phase filtering

### Existing Strengths
- Clean protocol-based design (PhysicsEntity)
- Working narrow-phase collision detection
- Collision tracking to prevent duplicates
- Separate static/dynamic entity handling

## Proposed Solution: Single-Axis Sweep and Prune

### Why This Approach?
1. **Simple to implement** - Much simpler than octrees or BVH
2. **Excellent for flight sims** - Leverages temporal coherence of smooth flight paths
3. **Minimal code changes** - Integrates cleanly with existing system
4. **Proven performance** - O(n log n) setup, O(n) per-frame updates
5. **Extensible** - Can add more axes later if needed

## Implementation Steps

### Phase 1: Foundation (2-3 hours)

#### 1.1 Create AABB Structure
```swift
// New file: ToyFlightSimulator Shared/Physics/BroadPhase/AABB.swift
struct AABB {
    var min: float3
    var max: float3
    
    func overlaps(_ other: AABB) -> Bool
    func overlapsOnAxis(_ other: AABB, axis: Int) -> Bool
    func expandBy(_ radius: Float) -> AABB
}
```

#### 1.2 Extend PhysicsEntity Protocol
```swift
// Add to PhysicsEntity.swift
protocol PhysicsEntity {
    // ... existing properties ...
    
    func getAABB() -> AABB
    var isDynamic: Bool { get }  // Computed from !isStatic
}

// Default implementations for sphere and plane entities
```

#### 1.3 Create BroadPhaseCollisionDetector
```swift
// New file: ToyFlightSimulator Shared/Physics/BroadPhase/BroadPhaseCollisionDetector.swift
class BroadPhaseCollisionDetector {
    private var sortedDynamicEntities: [PhysicsEntity] = []
    private var staticEntities: [PhysicsEntity] = []
    private var lastFramePositions: [String: float3] = [:]
    
    func update(entities: [PhysicsEntity])
    func getPotentialCollisionPairs() -> [(PhysicsEntity, PhysicsEntity)]
    private func sortEntitiesByXAxis()
    private func insertionSort()  // For frame-to-frame updates
}
```

### Phase 2: Core Algorithm (3-4 hours)

#### 2.1 Implement Sweep and Prune
```swift
class BroadPhaseCollisionDetector {
    private let sortThreshold: Float = 5.0  // Re-sort if movement > threshold
    
    func update(entities: [PhysicsEntity]) {
        // Separate static and dynamic
        staticEntities = entities.filter { $0.isStatic }
        let dynamicEntities = entities.filter { !$0.isStatic }
        
        // Check if we need full sort or just insertion sort
        let needsFullSort = checkIfNeedsFullSort(dynamicEntities)
        
        if needsFullSort {
            sortedDynamicEntities = dynamicEntities.sorted { 
                $0.getAABB().min.x < $1.getAABB().min.x 
            }
        } else {
            insertionSortUpdate(dynamicEntities)
        }
        
        updateLastFramePositions(dynamicEntities)
    }
    
    func getPotentialCollisionPairs() -> [(PhysicsEntity, PhysicsEntity)] {
        var pairs: [(PhysicsEntity, PhysicsEntity)] = []
        
        // Dynamic vs Dynamic (with sweep optimization)
        for i in 0..<sortedDynamicEntities.count {
            let entityA = sortedDynamicEntities[i]
            let aabbA = entityA.getAABB()
            
            // Only check entities whose X ranges overlap
            for j in (i+1)..<sortedDynamicEntities.count {
                let entityB = sortedDynamicEntities[j]
                let aabbB = entityB.getAABB()
                
                // Early exit when X ranges no longer overlap
                if aabbB.min.x > aabbA.max.x {
                    break
                }
                
                // Check Y and Z overlap
                if aabbA.overlaps(aabbB) {
                    pairs.append((entityA, entityB))
                }
            }
        }
        
        // Dynamic vs Static (simple AABB checks)
        for dynamic in sortedDynamicEntities {
            let dynamicAABB = dynamic.getAABB()
            for static in staticEntities {
                if dynamicAABB.overlaps(static.getAABB()) {
                    pairs.append((dynamic, static))
                }
            }
        }
        
        return pairs
    }
}
```

### Phase 3: Integration (2-3 hours)

#### 3.1 Modify PhysicsWorld
```swift
// PhysicsWorld.swift modifications
class PhysicsWorld {
    private var broadPhase = BroadPhaseCollisionDetector()
    
    func update(deltaTime: Float) {
        // Reset collision tracking
        for var entity in entities {
            entity.reset()
        }
        
        // Broad phase
        broadPhase.update(entities: entities)
        let potentialPairs = broadPhase.getPotentialCollisionPairs()
        
        // Narrow phase (existing code, but only for potential pairs)
        switch self.updateType {
            case .NaiveEuler:
                naiveUpdateWithPairs(deltaTime: deltaTime, pairs: potentialPairs)
            case .HeckerVerlet:
                heckerVerletUpdateWithPairs(deltaTime: deltaTime, pairs: potentialPairs)
        }
    }
}
```

#### 3.2 Refactor HeckerCollisionResponse
```swift
// Modify to accept collision pairs instead of checking all entities
static func resolveCollisions(deltaTime: Float, 
                              entities: inout [PhysicsEntity],
                              collisionPairs: [(PhysicsEntity, PhysicsEntity)]) {
    for (entityA, entityB) in collisionPairs {
        // Existing collision resolution code
        // (Move the inner loop content here)
    }
}
```

### Phase 4: Testing & Optimization (2-3 hours)

#### 4.1 Create Performance Tests
- Test with 10, 50, 100, 500, 1000 entities
- Measure frame time before and after optimization
- Verify collision detection accuracy

#### 4.2 Fine-tune Parameters
- Adjust sort threshold for optimal performance
- Consider adding Y-axis check for vertical separation
- Profile insertion sort vs full sort frequency

#### 4.3 Debug Visualization (Optional)
- Add debug rendering for AABBs
- Visualize broad-phase filtering effectiveness
- Show collision pair count in stats

## File Structure

```
ToyFlightSimulator Shared/Physics/
├── BroadPhase/                    (NEW)
│   ├── AABB.swift                 (NEW)
│   └── BroadPhaseCollisionDetector.swift (NEW)
├── CollisionResponse/
│   └── HeckerCollisionResponse.swift (MODIFY)
├── Solver/
│   ├── EulerSolver.swift
│   ├── PhysicsSolver.swift
│   └── VerletSolver.swift
└── World/
    ├── PhysicsEntity.swift (MODIFY)
    └── PhysicsWorld.swift (MODIFY)
```

## Performance Expectations

### Complexity Analysis
- **Current**: O(n²) for all entities
- **New Broad Phase**: O(n log n) initial sort, O(n) per frame
- **Overall**: O(k) narrow phase where k << n²

### Expected Improvements
- **50 entities**: ~5x speedup
- **100 entities**: ~20x speedup
- **500 entities**: ~100x speedup

### Memory Impact
- Additional ~100 bytes per entity for AABB storage
- Sorted entity list (pointer array, minimal overhead)
- Position tracking map for movement detection

## Risk Mitigation

### Potential Issues & Solutions
1. **Fast-moving objects**: Consider continuous collision detection later
2. **Large objects**: May span many regions, but AABB handles this
3. **Degenerate cases**: Falls back to O(n²) if all objects overlap on X

### Rollback Plan
- Keep original nested loop code commented
- Add feature flag to toggle broad phase on/off
- Maintain backward compatibility with existing collision response

## Success Criteria
- [ ] Collision detection remains accurate
- [ ] Performance improves by >5x for 50+ entities
- [ ] No visual artifacts or missed collisions
- [ ] Code remains clean and maintainable
- [ ] All existing tests pass

## Timeline
- **Phase 1**: 2-3 hours (Foundation)
- **Phase 2**: 3-4 hours (Core Algorithm)
- **Phase 3**: 2-3 hours (Integration)
- **Phase 4**: 2-3 hours (Testing & Optimization)
- **Total**: 10-13 hours

## Future Enhancements (Post-Implementation)
1. Add Y and Z axis sorting for full 3-axis sweep
2. Implement continuous collision detection for fast objects
3. Add spatial hashing for very large worlds
4. GPU acceleration using Metal compute shaders
5. Hierarchical grids for extreme size disparities

## Notes for Implementation
- Start simple, optimize later
- Maintain existing collision response behavior exactly
- Focus on correctness first, then performance
- Keep debug output to verify broad phase effectiveness
- Document all magic numbers and thresholds