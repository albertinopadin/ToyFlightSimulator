//
//  PhysicsStressTestScene.swift
//  ToyFlightSimulator
//
//  Created for physics optimization testing - Phase 3
//

final class PhysicsStressTestScene: GameScene {
    // Test configuration
    static let sphereCounts = [50, 100, 200, 300, 500]
    private var currentTestIndex = 0
    private var currentSphereCount: Int { Self.sphereCounts[currentTestIndex] }
    
    // Scene objects
    var ground: Quad!
    var groundRigidBody: PlaneRigidBody!
    let debugCamera = DebugCamera()
    var physicsWorld: PhysicsWorld!
    var spheres: [Sphere] = []
    
    // Performance tracking
    var frameCounter: UInt64 = 0
    var timeAccumulator: UInt64 = 0
    var minTime: Double = Double.greatestFiniteMagnitude
    var maxTime: Double = 0
    var useBroadPhase = true
    
    // Test results
    var testResults: [(count: Int, broadPhase: Bool, avgTime: Double, minTime: Double, maxTime: Double)] = []
    
    private func createSpheres(count: Int) -> [Sphere] {
        var sphrs = [Sphere]()
        
        // Create spheres in a grid pattern for more predictable collisions
        let gridSize = Int(sqrt(Double(count))) + 1
        let spacing: Float = 2.0
        let startX = -Float(gridSize) * spacing / 2
        let startZ = -Float(gridSize) * spacing / 2
        
        for i in 0..<count {
            let gridX = i % gridSize
            let gridZ = i / gridSize
            
            // Start positions in a grid, with random height
            let pos = float3(
                x: startX + Float(gridX) * spacing + .random(in: -0.5...0.5),
                y: .random(in: 5...20),
                z: startZ + Float(gridZ) * spacing + .random(in: -0.5...0.5)
            )
            
            let color = randomPaletteColor()

            let sphereRadius: Float = 0.3
            let sphere = Sphere()
            sphere.setScale(sphereRadius)
            sphere.setPosition(pos)
            sphere.setColor(color)
            
            let rigidBody = SphereRigidBody(gameObject: sphere, collisionRadius: sphereRadius)
            rigidBody.isStatic = false
            rigidBody.mass = 1.0
            rigidBody.restitution = 0.8
            
            // Add some initial velocity for more dynamic scene
            rigidBody.velocity = float3(
                x: .random(in: -2...2),
                y: 0,
                z: .random(in: -2...2)
            )
            
            sphrs.append(sphere)
        }
        
        return sphrs
    }
    
    private func addSun() {
        let sun = Sun()
        sun.setPosition(0, 100, 4)
        sun.setLightBrightness(1.0)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.04)
        sun.setLightDiffuseIntensity(0.15)
        addLight(sun)
    }
    
    override func buildScene() {
        (ground, groundRigidBody) = addGround(restitution: 0.9)
        addSun()
        
        debugCamera.setPosition([0, 15, 40])
        debugCamera.setRotationX(Float(-15).toRadians)
        addCamera(debugCamera)
        
        // Start with first test configuration
        setupTest(sphereCount: currentSphereCount, useBroadPhase: true)
        
        print("═══════════════════════════════════════════════════════")
        print("PHYSICS STRESS TEST SCENE - Phase 3 Performance Testing")
        print("═══════════════════════════════════════════════════════")
        print("Starting test with \(currentSphereCount) spheres, broad-phase: \(useBroadPhase)")
    }
    
    private func setupTest(sphereCount: Int, useBroadPhase: Bool) {
        // Remove old spheres
        self.removeAllChildren()
        spheres.removeAll()
        
        // Create new spheres
        spheres = createSpheres(count: sphereCount)
        for sphere in spheres {
            addChild(sphere)
        }
        
        // Setup physics world
        let entities: [RigidBody] = spheres.map { $0.rigidBody! } + [groundRigidBody]
        physicsWorld = PhysicsWorld(entities: entities, updateType: .HeckerVerlet)
        physicsWorld.useBroadPhase = useBroadPhase
        // This scene prints broad-phase stats; collection is off by default now.
        physicsWorld.collectBroadPhaseStatistics = true
        
        // Reset performance tracking
        frameCounter = 0
        timeAccumulator = 0
        minTime = Double.greatestFiniteMagnitude
        maxTime = 0
        
        self.useBroadPhase = useBroadPhase
    }
    
    override func doUpdate() {
        if GameTime.DeltaTime <= 1.0 {
            let time = timeit {
                physicsWorld.update(deltaTime: Float(GameTime.DeltaTime))
            }
            
            let timeInSeconds = Double(time) * 1e-9
            timeAccumulator += time
            minTime = min(minTime, timeInSeconds)
            maxTime = max(maxTime, timeInSeconds)
            
            // Print statistics every 120 frames (2 seconds at 60fps)
            if frameCounter % 120 == 0 && frameCounter > 0 {
                let avgTime = Double(timeAccumulator) / Double(120) * 1e-9
                
                // Get broad-phase statistics if available
                let stats = physicsWorld.getBroadPhaseStats()
                
                print("───────────────────────────────────────────────────")
                print("Spheres: \(currentSphereCount) | Broad-phase: \(useBroadPhase)")
                print("Avg: \(String(format: "%.6f", avgTime))s | Min: \(String(format: "%.6f", minTime))s | Max: \(String(format: "%.6f", maxTime))s")
                
                if useBroadPhase && stats.totalChecks > 0 {
                    let reduction = Double(stats.checksSaved) / Double(stats.totalChecks + stats.checksSaved) * 100
                    print("Broad-phase stats: \(stats.totalChecks) checks, \(stats.checksSaved) saved (\(String(format: "%.1f", reduction))% reduction)")
                }
                
                // Store result and move to next test
                testResults.append((
                    count: currentSphereCount,
                    broadPhase: useBroadPhase,
                    avgTime: avgTime,
                    minTime: minTime,
                    maxTime: maxTime
                ))
                
                // Reset for next measurement period
                timeAccumulator = 0
                minTime = Double.greatestFiniteMagnitude
                maxTime = 0
                
                // After collecting enough samples, move to next test
                if frameCounter >= 600 { // 10 seconds of data
                    moveToNextTest()
                }
            }
            
            frameCounter += 1
        }
    }
    
    private func moveToNextTest() {
        if useBroadPhase {
            // Switch to testing without broad-phase
            setupTest(sphereCount: currentSphereCount, useBroadPhase: false)
            print("\n🔄 Switching to O(n²) algorithm for comparison...")
        } else {
            // Move to next sphere count
            currentTestIndex += 1
            if currentTestIndex < Self.sphereCounts.count {
                setupTest(sphereCount: currentSphereCount, useBroadPhase: true)
                print("\n📈 Increasing sphere count to \(currentSphereCount)...")
            } else {
                // All tests complete, print summary
                printTestSummary()
            }
        }
        
        frameCounter = 0
    }
    
    private func printTestSummary() {
        print("\n═══════════════════════════════════════════════════════")
        print("                  TEST SUMMARY REPORT                   ")
        print("═══════════════════════════════════════════════════════")
        
        // Group results by sphere count
        for count in Self.sphereCounts {
            let broadPhaseResult = testResults.first { $0.count == count && $0.broadPhase }
            let naiveResult = testResults.first { $0.count == count && !$0.broadPhase }
            
            if let bp = broadPhaseResult, let naive = naiveResult {
                let speedup = naive.avgTime / bp.avgTime
                let percentImprovement = (1.0 - bp.avgTime / naive.avgTime) * 100
                
                print("\n\(count) Spheres:")
                print("  O(n²):        \(String(format: "%.6f", naive.avgTime))s avg")
                print("  Broad-phase:  \(String(format: "%.6f", bp.avgTime))s avg")
                print("  Speedup:      \(String(format: "%.2f", speedup))x")
                print("  Improvement:  \(String(format: "%.1f", percentImprovement))%")
            }
        }
        
        print("\n═══════════════════════════════════════════════════════")
        print("Phase 3 Testing Complete! 🎉")
    }
}
