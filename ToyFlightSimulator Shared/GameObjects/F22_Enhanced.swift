//
//  F22_Enhanced.swift
//  ToyFlightSimulator
//
//  Enhanced F22 with proper landing gear rotation animation
//

import MetalKit

// Simple wrapper to display a specific mesh from a model
class MeshDisplay: GameObject {
    private let meshIndex: Int
    private let parentModel: Model
    
    init(name: String, model: Model, meshIndex: Int) {
        self.meshIndex = meshIndex
        self.parentModel = model
        super.init(name: name, modelType: .None)
        
        // Create a model with just the specific mesh
        let singleMesh = [model.meshes[meshIndex]]
        self.model = Model(name: name, meshes: singleMesh)
    }
}

class F22_Enhanced: Aircraft {
    static let NAME: String = "F-22 Enhanced"
    
    let afterburnerLeft = Afterburner(name: "F-22 Left Afterburner")
    let afterburnerRight = Afterburner(name: "F-22 Right Afterburner")
    
    // Landing gear animation state
    private var landingGearExtended: Bool = true
    private var landingGearAnimating: Bool = false
    private var animationElapsedTime: Float = 0.0
    private let animationDuration: Float = 3.0  // 3 seconds
    
    // Landing gear display objects
    private var extendedGearDisplay: MeshDisplay?
    private var retractedGearDisplay: MeshDisplay?
    
    // Mesh indices
    private var landingGearMeshIndices: (extended: Int?, retracted: Int?) = (nil, nil)
    
    // Animation parameters
    private let mainGearRotationAxis = X_AXIS  // Main gear rotates sideways
    private let maxRotationAngle: Float = 90.0  // degrees
    private let gearPivotOffset = float3(0, 0, -8)  // Pivot point relative to aircraft center
    
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
        
        // Setup afterburners
        afterburnerLeft.off()
        afterburnerLeft.rotate(deltaAngle: Float(-90).toRadians, axis: Y_AXIS)
        afterburnerLeft.setPosition(-23, -7, 1)
        addChild(afterburnerLeft)
        
        afterburnerRight.off()
        afterburnerRight.rotate(deltaAngle: Float(-90).toRadians, axis: Y_AXIS)
        afterburnerRight.setPosition(-23, 7, 1)
        addChild(afterburnerRight)
        
        // Find and setup landing gear
        findLandingGearMeshes()
        setupLandingGearDisplays()
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
            if mesh.name == "Object_6" {
                landingGearMeshIndices.extended = index
                print("[F22_Enhanced] Found extended landing gear at index \(index)")
            } else if mesh.name == "Object_5" {
                landingGearMeshIndices.retracted = index
                print("[F22_Enhanced] Found retracted landing gear at index \(index)")
            }
        }
        
        // Hide landing gear meshes from main model
        updateMainModelVisibility()
    }
    
    private func setupLandingGearDisplays() {
        guard let extendedIndex = landingGearMeshIndices.extended,
              let retractedIndex = landingGearMeshIndices.retracted else {
            print("[F22_Enhanced] Warning: Could not find landing gear meshes")
            return
        }
        
        // Create display objects for landing gear
        extendedGearDisplay = MeshDisplay(
            name: "F22_ExtendedGear",
            model: self.model,
            meshIndex: extendedIndex
        )
        
        retractedGearDisplay = MeshDisplay(
            name: "F22_RetractedGear",
            model: self.model,
            meshIndex: retractedIndex
        )
        
        // Add as children
        if let extended = extendedGearDisplay {
            addChild(extended)
            extended.setColor(float4(1, 1, 1, 1))  // Fully visible initially
        }
        
        if let retracted = retractedGearDisplay {
            addChild(retracted)
            retracted.setColor(float4(1, 1, 1, 0))  // Hidden initially
        }
    }
    
    private func updateMainModelVisibility() {
        // Hide landing gear meshes from the main model
        if let extendedIndex = landingGearMeshIndices.extended {
            meshVisibility[model.meshes[extendedIndex].name] = false
        }
        if let retractedIndex = landingGearMeshIndices.retracted {
            meshVisibility[model.meshes[retractedIndex].name] = false
        }
    }
    
    private func toggleLandingGear() {
        if !landingGearAnimating {
            landingGearAnimating = true
            landingGearExtended.toggle()
            animationElapsedTime = 0.0
            print("[F22_Enhanced] Toggling landing gear to: \(landingGearExtended ? \"Extended\" : \"Retracted\")")
        }
    }
    
    private func updateLandingGearAnimation() {
        if landingGearAnimating {
            // Update animation time
            animationElapsedTime += ToyFlightSimulator.DeltaTime
            
            // Calculate normalized progress (0 to 1)
            let rawProgress = min(animationElapsedTime / animationDuration, 1.0)
            
            // Apply easing curve
            let easedProgress = easeInOutCubic(rawProgress)
            
            // Calculate rotation angle
            let rotationAngle: Float
            if landingGearExtended {
                // Extending: rotate from retracted (90°) to extended (0°)
                rotationAngle = mix(maxRotationAngle, 0.0, easedProgress)
            } else {
                // Retracting: rotate from extended (0°) to retracted (90°)
                rotationAngle = mix(0.0, maxRotationAngle, easedProgress)
            }
            
            // Apply rotation to extended gear display
            if let extended = extendedGearDisplay {
                // Reset transform
                extended.resetTransform()
                
                // Apply pivot offset
                extended.translate(direction: gearPivotOffset)
                
                // Apply rotation
                extended.rotate(angle: rotationAngle.toRadians, axis: mainGearRotationAxis)
                
                // Visibility based on rotation
                let extendedAlpha = landingGearExtended ? easedProgress : (1.0 - easedProgress)
                extended.setColor(float4(1, 1, 1, extendedAlpha))
            }
            
            // Manage retracted gear visibility
            if let retracted = retractedGearDisplay {
                // Retracted gear fades in/out opposite to extended
                let retractedAlpha = landingGearExtended ? 0.0 : easedProgress
                retracted.setColor(float4(1, 1, 1, retractedAlpha))
            }
            
            // Check if animation is complete
            if rawProgress >= 1.0 {
                landingGearAnimating = false
                animationElapsedTime = 0.0
                print("[F22_Enhanced] Landing gear animation complete")
                
                // Set final states
                if landingGearExtended {
                    extendedGearDisplay?.setColor(float4(1, 1, 1, 1))
                    retractedGearDisplay?.setColor(float4(1, 1, 1, 0))
                    extendedGearDisplay?.resetTransform()
                    extendedGearDisplay?.translate(direction: gearPivotOffset)
                } else {
                    extendedGearDisplay?.setColor(float4(1, 1, 1, 0))
                    retractedGearDisplay?.setColor(float4(1, 1, 1, 1))
                }
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
    
    // Linear interpolation
    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }
}