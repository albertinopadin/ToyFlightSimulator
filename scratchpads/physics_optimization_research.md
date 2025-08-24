# Physics Optimization Research Scratchpad

## Current Implementation Analysis
- **Date**: 2025-08-23
- **Current Complexity**: O(n²) in HeckerCollisionResponse.swift (lines 23-24)
- **Problem**: Nested loops checking every entity against every other entity
- **Current Collision Types**: Sphere-Sphere, Sphere-Plane, Plane-Plane
- **Physics Solvers**: Euler and Verlet integration
- **Collision Response**: Hecker's method with penetration depth calculation

## Key Discoveries
- Using Swift/Metal for rendering
- Physics entities use protocol-based design
- Already tracks collision pairs to prevent duplicate processing
- Has static vs dynamic entity distinction
- Supports restitution and mass-based collision response

## Questions to Research
1. What are the best spatial partitioning methods for 3D physics?
2. How to implement broad-phase vs narrow-phase collision detection?
3. What's the best approach for a flight simulator with mostly airborne objects?
4. How to handle mixed static/dynamic objects efficiently?

## Research Findings

### 1. Spatial Partitioning Options

#### Octrees
- **Pros**: Good for static scenes, hierarchical structure
- **Cons**: Expensive to rebuild each frame for dynamic objects
- **Loose Octrees**: Better variant with overlapping boundaries (2x size)
- **Complexity**: O(nhk) where h=tree height (~10), k=max primitives per node

#### BVH (Bounding Volume Hierarchy)
- **Pros**: Good for complex meshes, GPU-friendly
- **Cons**: Complex to implement, needs dynamic updating
- **Use Case**: Better for polygon-level collision, not object-object

#### Sweep and Prune (Sort and Sweep)
- **Pros**: Excellent for dynamic objects with temporal coherence
- **Complexity**: O(n log n) first sort, then O(n) for mostly sorted
- **Implementation**: Track min/max bounds on axes, use insertion sort
- **Best For**: When objects move small amounts between frames
- **Used By**: Bullet Physics (btAxisSweep3)

#### Uniform Grid / Spatial Hashing
- **Pros**: Simple, fast lookups, good for uniform object distribution
- **Cons**: Teapot-in-stadium problem (size disparity issues)
- **Cell Size**: Should be ≥ largest object's bounding volume
- **Complexity**: O(n) average case
- **Implementation**: Hash objects to grid cells, check neighboring cells

### 2. Flight Simulator Specific Considerations
- Objects are often spread out in 3D space (low density)
- Mix of static (terrain) and dynamic (aircraft) objects
- Size disparity (small bullets vs large terrain)
- Most objects are airborne (not clustered on ground)
- Temporal coherence is high (smooth flight paths)

### 3. Recommended Approach for ToyFlightSimulator

**Primary Choice: Sweep and Prune**
- Best for dynamic scenes with temporal coherence
- Simple to implement compared to hierarchical structures
- Works well with existing sphere-sphere and sphere-plane collisions
- Can maintain sorted lists between frames

**Alternative: Uniform Grid with Hierarchical Levels**
- Use coarse grid for large objects (terrain)
- Fine grid for small objects (projectiles)
- Good for sparse aerial environments

### 4. Implementation Strategy
1. Start with single-axis sweep and prune (X or Y axis)
2. Use AABB (Axis-Aligned Bounding Boxes) for broad phase
3. Keep existing narrow phase collision detection
4. Add insertion sort for maintaining sorted lists
5. Track overlapping pairs to avoid redundant checks

### 5. Performance Targets
- Current: O(n²) for n entities
- Target: O(n log n) initial sort, O(n) per frame update
- Expected speedup: 10-100x for 100+ entities

## Ultrathinking Solution Design

### Chosen Approach: Single-Axis Sweep and Prune with Static/Dynamic Separation

After careful analysis, the optimal solution for ToyFlightSimulator is:

1. **Broad Phase Algorithm**: Single-axis (X) Sweep and Prune
   - Simple to implement and debug
   - Excellent performance for flight simulator scenarios
   - Leverages temporal coherence (smooth flight paths)
   - Minimal changes to existing codebase

2. **Static/Dynamic Separation**
   - Static entities (terrain, buildings) in separate list
   - Dynamic entities (aircraft, projectiles) in sorted list
   - Skip static-static checks entirely
   - Optimize dynamic-static with simple AABB checks

3. **Implementation Components**
   - AABB struct with min/max bounds
   - BroadPhaseCollisionDetector class
   - Insertion sort for frame-to-frame updates
   - Collision pair generation for narrow phase

4. **Why This Solution**
   - **Simplicity**: Much simpler than octrees or full 3-axis sweep
   - **Performance**: O(n log n) setup, O(n) updates for sorted lists
   - **Compatibility**: Works seamlessly with existing collision code
   - **Extensibility**: Can add Y/Z axes later if needed
   - **Robustness**: Graceful degradation, no complex edge cases

5. **Expected Results**
   - 50-90% reduction in collision checks for typical scenarios
   - Near-linear performance for frame updates
   - Maintains all existing collision response behavior

## Implementation Gotchas & Discoveries

### Key Discoveries
1. The existing code already tracks collision pairs to prevent duplicates - we can leverage this
2. Swift's built-in sort is highly optimized (Introsort) - use it for initial sorting
3. Insertion sort is ideal for nearly-sorted arrays (frame-to-frame updates)
4. Separating static/dynamic entities provides huge wins (no static-static checks needed)

### Important Gotchas
1. **Float precision**: Use epsilon comparisons for AABB overlaps to avoid edge cases
2. **Entity movement**: Track position changes to decide when to re-sort
3. **Memory allocation**: Pre-allocate arrays to avoid per-frame allocations
4. **Swift specifics**: Use `inout` parameters to avoid copying entity arrays
5. **Thread safety**: PhysicsWorld updates on separate thread - need synchronization

### Questions Answered
1. **Q: Should we use all 3 axes?** A: Start with X-axis only for simplicity, add Y/Z later if needed
2. **Q: What about fast-moving objects?** A: Separate issue (tunneling) - handle in future with CCD
3. **Q: How to handle size disparity?** A: AABB naturally handles different sizes, no special case needed
4. **Q: When to re-sort?** A: Use movement threshold (~5 units) to trigger full re-sort

### Performance Tips
1. Use structure-of-arrays for better cache locality if needed
2. Consider SIMD operations for AABB overlap checks
3. Profile before optimizing further - current solution should be sufficient
4. Metal compute shaders could parallelize broad phase in future

### Testing Strategy
1. Create scene with 100+ spheres falling under gravity
2. Verify no collisions are missed
3. Measure frame time improvement
4. Test edge cases: all entities in same location, spread far apart, mixed sizes

## Phase 1 Implementation Notes

### Completed
1. Created AABB struct with overlap detection methods
2. Extended PhysicsEntity protocol with getAABB() method
3. Implemented default AABB calculation for spheres and planes
4. Created BroadPhaseCollisionDetector with sweep and prune
5. Added GameObject default AABB implementation

### Manual Steps Required
**IMPORTANT**: You need to add these files to the Xcode project:
1. Open ToyFlightSimulator.xcodeproj in Xcode
2. Right-click on "ToyFlightSimulator Shared/Physics" folder
3. Select "Add Files to ToyFlightSimulator..."
4. Navigate to the BroadPhase folder and add:
   - BroadPhaseTypes.swift (contains all new code in one file)
   OR if you prefer separate files:
   - AABB.swift
   - BroadPhaseCollisionDetector.swift
5. Make sure "Copy items if needed" is unchecked
6. Select all targets (macOS, iOS, tvOS)

### Key Design Decisions
1. Single-axis (X) sorting for simplicity
2. Insertion sort for frame-to-frame updates (leverages temporal coherence)
3. Static/dynamic separation to skip unnecessary checks
4. 5-unit movement threshold for re-sorting
5. Statistics tracking for performance monitoring

### Phase 1 Completion Status ✅

**Build Status**: BUILD SUCCEEDED

**Files Created**:
- `BroadPhaseTypes.swift` - Contains all broad-phase code (AABB + BroadPhaseCollisionDetector)
- Empty placeholder files for AABB.swift and BroadPhaseCollisionDetector.swift (for Xcode)

**Key Implementation Details**:
- All AABB members made public for module visibility
- Foundation import added for CFAbsoluteTimeGetCurrent
- Single-axis (X) sweep and prune implemented
- Static/dynamic entity separation working
- Performance statistics tracking included

### Next Steps (Phase 2)
1. Integrate BroadPhaseCollisionDetector into PhysicsWorld
2. Modify HeckerCollisionResponse to accept collision pairs
3. Update narrow-phase to work with broad-phase output
4. Test and measure performance improvements
