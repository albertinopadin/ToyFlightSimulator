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

enum SpecialUserCommand: CaseIterable {
    case ResetScene
}

class InputManager {
    static var controller: Controller = Controller()
    
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
    
    static var multiKeyInputMappings: [SpecialUserCommand: [Keycodes]] = [
        .ResetScene: [.command, .r]
    ]
    
    static var specialCommandsActive: [SpecialUserCommand: Bool] = {
        var sca: [SpecialUserCommand: Bool] = [SpecialUserCommand: Bool]()
        for suc in SpecialUserCommand.allCases {
            sca[suc] = false
        }
        return sca
    }()
    
    // TODO: This is pretty bad...
    static var controllerMappings: [UserCommand: ControllerState] = [
        .RollLeft: .RightStickX,
        .RollRight: .RightStickX,
        .PitchUp: .RightStickY,
        .PitchDown: .RightStickY
    ]
    
    static func handleKeyPressedDebounced(keyCode: Keycodes, _ handleBlock: () -> Void) {
        guard let _ = keysPressed[keyCode] else {
            print("[InputManager handleKeyPressedDebounced] WARNING: Unknown Key Code: \(keyCode)")
            return
        }
        
        if Keyboard.IsKeyPressed(keyCode) {
            if !keysPressed[keyCode]! {
                keysPressed[keyCode] = true
                handleBlock()
            }
        } else {
            if keysPressed[keyCode]! {
                keysPressed[keyCode] = false
            }
        }
    }
    
    static func HasCommand(_ command: UserCommand) -> Bool {
        if controller.present {
            guard let controllerState = controllerMappings[command] else { return false }
            let controllerValue = controller.getState(controllerState)
            
            switch command {
                case .RollLeft:
                    return controllerValue < 0.0
                case .RollRight:
                    return controllerValue > 0.0
                case .PitchUp:
                    return controllerValue > 0.0
                case .PitchDown:
                    return controllerValue < 0.0
                default:
                    return false
            }
        } else {
            guard let key = keyboardMappings[command] else { return false }
            return Keyboard.IsKeyPressed(key)
        }
    }
    
    static func HasCommandDebounced(command: UserCommand, _ handleBlock: () -> Void) {
        guard let key = keyboardMappings[command] else { return }
        handleKeyPressedDebounced(keyCode: key, handleBlock)
    }
    
    static func HasMultiInputCommand(command: SpecialUserCommand, _ handleBlock: () -> Void) {
        guard let keyboardCommands: [Keycodes] = multiKeyInputMappings[command] else {
            print("[HasMultiInputCommand] WARNING: no mapping for command: \(command)")
            return
        }
        
        let allKeysPressed: Bool = keyboardCommands.reduce(into: true) { resultBool, keyCode in
            resultBool = resultBool && Keyboard.IsKeyPressed(keyCode)
        }
        
        if allKeysPressed {
            if !specialCommandsActive[command]! {
                specialCommandsActive[command] = true
                handleBlock()
            }
        } else {
            if specialCommandsActive[command]! {
                specialCommandsActive[command] = false
            }
        }
    }
}
