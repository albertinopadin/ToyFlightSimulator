//
//  InputManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/29/23.
//

enum DiscreteCommand {
    case FireMissileAIM9
    case FireMissileAIM120
    case DropBomb
    case JettisonFuelTank
    
    case ResetLoadout
    
    case Pause
}

enum ContinuousCommand {
    case MoveFwd
    case MoveSide
    
    case Pitch
    case Roll
    case Yaw
}

enum SpecialUserCommand: CaseIterable {
    case ResetScene
}

struct KeycodeValue {
    let keyCode: Keycodes
    let value: Float
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
    
    static var pitchAxisFlipped: Bool = true
    
    static var keyboardMappingsContinuous: [ContinuousCommand: [KeycodeValue]] = [
        .MoveFwd: [KeycodeValue(keyCode: .w, value: 1.0), KeycodeValue(keyCode: .s, value: -1.0)],
        .MoveSide: [KeycodeValue(keyCode: .d, value: 1.0), KeycodeValue(keyCode: .a, value: -1.0)],
        .Pitch: [KeycodeValue(keyCode: .upArrow, value: pitchAxisFlipped ? -1.0 : 1.0),
                 KeycodeValue(keyCode: .downArrow, value: pitchAxisFlipped ? 1.0 : -1.0)],
        .Roll: [KeycodeValue(keyCode: .rightArrow, value: 1.0), KeycodeValue(keyCode: .leftArrow, value: -1.0)],
        .Yaw: [KeycodeValue(keyCode: .e, value: -1.0), KeycodeValue(keyCode: .q, value: 1.0)]
    ]
    
    static var keyboardMappingsDiscrete: [DiscreteCommand: Keycodes] = [
        .Pause: .p,
        .ResetLoadout: .l,
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
    
    static var controllerMappingsContinuous: [ContinuousCommand: ControllerState] = [
        .Roll: .RightStickX,
        .Pitch: .RightStickY,
        .MoveFwd: .LeftStickY,
        .MoveSide: .LeftStickX
    ]
    
    static var controllerMappingsDiscrete: [DiscreteCommand: ControllerState] = [
        .FireMissileAIM9: .RightTrigger,
        .DropBomb: .LeftTrigger
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
    
    static func DiscreteCommand(_ command: DiscreteCommand) -> Bool {
        var hasCommand: Bool = false
        
        guard let key = keyboardMappingsDiscrete[command] else { return false }
        hasCommand = hasCommand || Keyboard.IsKeyPressed(key)
        
        if controller.present {
//            guard let controllerState = controllerMappingsDiscrete[command] else { return false }
            guard let controllerState = controllerMappingsDiscrete[command] else { return hasCommand }
            let controllerValue = controller.getState(controllerState)
            hasCommand = hasCommand || controllerValue > .zero
        }
        
        return hasCommand
    }
    
    static func ContinuousCommand(_ command: ContinuousCommand) -> Float {
        var continuousValue: Float = .zero
        
        guard let keysValues = keyboardMappingsContinuous[command] else { return .zero }
        for kv in keysValues {
            if Keyboard.IsKeyPressed(kv.keyCode) {
                continuousValue = kv.value
                break
            }
        }
        
        if controller.present {
//            guard let controllerState = controllerMappingsContinuous[command] else { return .zero }
            guard let controllerState = controllerMappingsContinuous[command] else { return continuousValue }
            let controllerValue = controller.getState(controllerState)
            if command == .Pitch && pitchAxisFlipped {
                continuousValue += -controllerValue
            } else {
                continuousValue += controllerValue
            }
        }
        
        return continuousValue
    }
    
    static func HasDiscreteCommandDebounced(command: DiscreteCommand, _ handleBlock: () -> Void) {
        guard let key = keyboardMappingsDiscrete[command] else { return }
        handleKeyPressedDebounced(keyCode: key, handleBlock)
        
        // TODO: Debounce this:
        if controller.present {
            guard let controllerState = controllerMappingsDiscrete[command] else { return }
            let controllerValue = controller.getState(controllerState)
            if controllerValue > .zero {
                handleBlock()
            }
        }
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
