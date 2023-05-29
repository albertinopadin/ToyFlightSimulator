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
}

class InputManager {
    // Key or Button mappings (depending on if using keyboard, controller or joystick/throttle) ???
    
    static var keyboardMappings: [UserCommand: Keycodes] = [
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
    
    static func handleKeyPressedDebounced(keyCode: Keycodes, keyPressed: inout Bool, _ handleBlock: () -> Void) {
        if Keyboard.IsKeyPressed(keyCode) {
            if !keyPressed {
                keyPressed.toggle()
                handleBlock()
            }
        } else {
            if keyPressed {
                keyPressed.toggle()
            }
        }
    }
    
    static func HasCommand(_ command: UserCommand) -> Bool {
        guard let key = keyboardMappings[command] else { return false }
        return Keyboard.IsKeyPressed(key)
    }
    
//    static func HasCommandDebounced(command: UserCommand) -> Bool {
//
//    }
}
