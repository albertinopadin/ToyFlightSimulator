//
//  F22_CGTrader.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/23/26.
//

class F22_CGTrader: Aircraft {
    static let NAME: String = "F-22_CGTrader"
    
    override var cameraOffset: float3 {
        [0, 4, 8]
    }
    
    init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: Self.NAME,
                   modelType: .CGTrader_F22,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
        
        setupAnimator()
    }
    
    private func setupAnimator() {
        guard let usdModel = model as? UsdModel else {
            print("[F22_CGTrader] Warning: Model is not a UsdModel, animations will not be controlled")
            return
        }

        // Create the animator (AnimationLayerSystem sets hasExternalAnimator flag)
        animator = F22Animator(model: usdModel)

        print("[F22_CGTrader] F22Animator initialized with duration: \(animator?.gearAnimationDuration ?? 0)")
    }
    
    override func doUpdate() {
        super.doUpdate()

        // Handle landing gear toggle input
        if shouldUpdateOnPlayerInput && hasFocus {
            InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
                print("[F22_CGTrader doUpdate] toggling gear")
                self.animator?.toggleGear()
            }
            
            let rollValue = InputManager.ContinuousCommand(.Roll)
            if abs(rollValue) > 0 {
                print("[F22_CGTrader doUpdate] roll value \(rollValue)")
            }
            self.animator?.rollFlaperons(value: rollValue)
        }

        // Update the animator each frame
        animator?.update(deltaTime: Float(GameTime.DeltaTime))
    }
}
