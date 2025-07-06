//
//  F22.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/20/24.
//

import MetalKit

class F22: Aircraft {
    static let NAME: String = "F-22"
    
    let afterburnerLeft = Afterburner(name: "F-22 Left Afterburner")
    let afterburnerRight = Afterburner(name: "F-22 Right Afterburner")
    
    // Landing gear animation
    private var landingGearExtended: Bool = true
    private var landingGearAnimating: Bool = false
    private var landingGearAnimationProgress: Float = 1.0
    private let landingGearAnimationSpeed: Float = 0.025
    
    // Rotation-based animation properties
    private var gearRotationAngle: Float = 0.0  // Current rotation angle in radians
    private let maxRotationAngle: Float = 90.0   // Maximum rotation in degrees
    private var animationElapsedTime: Float = 0.0
    private let animationDuration: Float = 3.0   // 3 seconds as requested
    
    // Pivot points for landing gear rotation (in model space)
    private let mainGearPivot = float3(0, 0, -10)  // Approximate main gear pivot
    private let noseGearPivot = float3(15, 0, 0)   // Approximate nose gear pivot
    
    // Mesh indices for landing gear (found during setup)
    private var landingGearMeshIndices: (extended: Int?, retracted: Int?) = (nil, nil)
    
    // Store original mesh colors to preserve them when changing alpha
    private var originalMeshColors: [Int: [float4]] = [:]
    
    override var cameraOffset: float3 {
        [0, 14, 28]
    }
    
    init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: Self.NAME,
                   modelType: .Sketchfab_F22,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
        rotateX(Float(90).toRadians)
        rotateZ(Float(90).toRadians)
        
        afterburnerLeft.off()
        afterburnerLeft.rotate(deltaAngle: Float(-90).toRadians, axis: Y_AXIS)
        afterburnerLeft.setPosition(-23, -7, 1)
        addChild(afterburnerLeft)
        
        afterburnerRight.off()
        afterburnerRight.rotate(deltaAngle: Float(-90).toRadians, axis: Y_AXIS)
        afterburnerRight.setPosition(-23, 7, 1)
        addChild(afterburnerRight)
        
        // Find and setup landing gear meshes
        findLandingGearMeshes()
        
        // Set initial visibility
        updateLandingGearVisibilitySimple()
    }
    
    override func doUpdate() {
        super.doUpdate()
        
        if hasFocus {
            // Afterburner control
            let fwdValue = InputManager.ContinuousCommand(.MoveFwd)
            
            if fwdValue > 0.8 {
                afterburnerLeft.on()
                afterburnerRight.on()
            } else {
                afterburnerLeft.off()
                afterburnerRight.off()
            }
            
            // Landing gear control
            InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
                toggleLandingGear()
            }
        }
        
        // Update landing gear animation
        updateLandingGearAnimation()
    }
    
    private func findLandingGearMeshes() {
        // Find landing gear meshes by name
        for (index, mesh) in model.meshes.enumerated() {
            // Object_6 = extended gear, Object_5 = retracted gear
            if mesh.name == "Object_6" {
                landingGearMeshIndices.extended = index
                print("[F22] Found extended landing gear at index \(index)")
            } else if mesh.name == "Object_5" {
                landingGearMeshIndices.retracted = index
                print("[F22] Found retracted landing gear at index \(index)")
            }
        }
        
        // Set initial visibility
        updateLandingGearVisibilitySimple()
    }
    
    private func toggleLandingGear() {
        if !landingGearAnimating {
            landingGearAnimating = true
            landingGearExtended.toggle()
            animationElapsedTime = 0.0  // Reset animation timer
            print("[F22] Toggling landing gear to: \(landingGearExtended ? "Extended" : "Retracted")")
        }
    }
    
    private func updateLandingGearAnimation() {
        if landingGearAnimating {
            // Update elapsed time
            animationElapsedTime += Float(GameTime.DeltaTime)
            
            // Calculate normalized progress (0 to 1)
            let progress = min(animationElapsedTime / animationDuration, 1.0)
            
            // Apply easing curve for smooth motion
            let easedProgress = easeInOutCubic(progress)
            
            // Calculate rotation angle based on gear state
            if landingGearExtended {
                // Extending: rotate from max angle to 0
                gearRotationAngle = mix(maxRotationAngle, 0.0, easedProgress).toRadians
                landingGearAnimationProgress = easedProgress
            } else {
                // Retracting: rotate from 0 to max angle
                gearRotationAngle = mix(0.0, maxRotationAngle, easedProgress).toRadians
                landingGearAnimationProgress = 1.0 - easedProgress
            }
            
            // During animation, swap meshes at midpoint for visual effect
            updateLandingGearVisibilitySimple()
            
            // Check if animation is complete
            if progress >= 1.0 {
                landingGearAnimating = false
                animationElapsedTime = 0.0
                print("[F22] Landing gear animation complete")
                
                // Ensure final state
                if landingGearExtended {
                    landingGearAnimationProgress = 1.0
                    gearRotationAngle = 0.0
                } else {
                    landingGearAnimationProgress = 0.0
                    gearRotationAngle = maxRotationAngle.toRadians
                }
            }
        }
    }
    
    private func updateLandingGearVisibilitySimple() {
        // Simple approach: hide one mesh completely, show the other
        // Since we can't use meshVisibility at runtime, we'll use a workaround
        if let extendedIndex = landingGearMeshIndices.extended,
           let retractedIndex = landingGearMeshIndices.retracted {
            
            // During animation, show the appropriate mesh based on progress
            let showExtended = landingGearAnimating ? 
                (landingGearAnimationProgress > 0.5) : landingGearExtended
            
            // Move meshes out of view instead of making them transparent
            if showExtended {
                // Show extended gear at normal position
                resetMeshTransform(at: extendedIndex)
                // Hide retracted gear by moving it far away
                hideMeshByTranslation(at: retractedIndex)
            } else {
                // Hide extended gear by moving it far away
                hideMeshByTranslation(at: extendedIndex)
                // Show retracted gear at normal position
                resetMeshTransform(at: retractedIndex)
            }
        }
    }
    
    private func hideMeshByTranslation(at meshIndex: Int) {
        // This is a workaround: we can't actually transform individual meshes
        // So we'll make them very small or move the entire model temporarily
        // For now, we'll just ensure materials are properly set
        guard meshIndex < model.meshes.count else { return }
        
        let mesh = model.meshes[meshIndex]
        
        print("[hideMeshByTranslation] meshIndex: \(meshIndex), name: \(mesh.name), num submeshes: \(mesh.submeshes.count)")
        
        for submesh in mesh.submeshes {
            // Make completely transparent (which will make it not render)
            if submesh.material != nil {
                submesh.material!.properties.color.w = 0.0
                
                // TEST: Setting the base color texture to nil actually causes a visual change - it just makes the mesh black:
                submesh.material!.baseColorTexture = nil
            }
        }
    }
    
    private func resetMeshTransform(at meshIndex: Int) {
        guard meshIndex < model.meshes.count else { return }
        
        let mesh = model.meshes[meshIndex]
        for submesh in mesh.submeshes {
            // Make fully opaque
            if submesh.material != nil {
                // Restore original color with full alpha
                var color = submesh.material!.properties.color
                color.w = 1.0
                submesh.material!.properties.color = color
            }
        }
    }
    
    // Easing function for smooth animation
    private func easeInOutCubic(_ t: Float) -> Float {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            let p = 2 * t - 2
            return 1 + p * p * p / 2
        }
    }
    
    // Linear interpolation helper
    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }
    
    // Helper function for Transform
    static func translate(direction: float3) -> float4x4 {
        return Transform.translationMatrix(direction)
    }
    
}
