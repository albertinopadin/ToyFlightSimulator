//
//  InputManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/29/23.
//

enum UserCommand {
    case MoveForward
    case MoveRearward
    case MoveRight
    case MoveLeft
    
    case PitchUp
    case PitchDown
    case RollRight
    case RollLeft
    case YawRight
    case YawLeft
    
    case FireMissileAIM9
    case FireMissileAIM120
    case DropBomb
    case JettisonFuelTank
    
    case ResetLoadout
    
    case Pause
}

class InputManager {
    // Key or Button mappings (depending on if using keyboard, controller or joystick/throttle) ???
    
    static var keysPressed: [Keycodes: Bool] = {
        var kp: [Keycodes: Bool] = [Keycodes: Bool]()
        for kc in Keycodes.allCases {
            kp[kc] = false
        }
        return kp
    }()
    
    static var keyboardMappings: [UserCommand: Keycodes] = [
        .Pause: .p,
        .ResetLoadout: .l,
        .MoveForward: .w,
        .MoveRearward: .s,
        .MoveLeft: .a,
        .MoveRight: .d,
        .PitchUp: .upArrow,
        .PitchDown: .downArrow,
        .RollLeft: .leftArrow,
        .RollRight: .rightArrow,
        .YawLeft: .q,
        .YawRight: .e,
        .FireMissileAIM9: .space,
        .FireMissileAIM120: .n,
        .DropBomb: .m,
        .JettisonFuelTank: .j
    ]
    
    // TODO:
    static var controllerMappings: [UserCommand: ControllerState] = [:]
    
    static func handleKeyPressedDebounced(keyCode: Keycodes, _ handleBlock: () -> Void) {
        guard let _ = keysPressed[keyCode] else {
            print("[InputManager handleKeyPressedDebounced] WARNING: Unknown Key Code: \(keyCode)")
            return
        }
        
        if Keyboard.IsKeyPressed(keyCode) {
            if !keysPressed[keyCode]! {
                keysPressed[keyCode]!.toggle()
                handleBlock()
            }
        } else {
            if keysPressed[keyCode]! {
                keysPressed[keyCode]!.toggle()
            }
        }
    }
    
    static func HasCommand(_ command: UserCommand) -> Bool {
        guard let key = keyboardMappings[command] else { return false }
        return Keyboard.IsKeyPressed(key)
    }
    
    static func HasCommandDebounced(command: UserCommand, _ handleBlock: () -> Void) {
        guard let key = keyboardMappings[command] else { return }
        handleKeyPressedDebounced(keyCode: key, handleBlock)
    }
    
    // TODO: (Reference Scene file)
//    static func HasMultiInputCommand(command: UserCommand, _ handleBlock: () -> Void) {
//        InputManager.handleKeyPressedDebounced(keyCode: .command, keyPressed: &_cmdPressed) {
//            print("CMD pressed")
//                InputManager.handleKeyPressedDebounced(keyCode: .r, keyPressed: &_rPressed) {
//                print("CMD-R pressed")
//                // TODO: Figure out how to reset scene
//            }
//        }
//    }
}
