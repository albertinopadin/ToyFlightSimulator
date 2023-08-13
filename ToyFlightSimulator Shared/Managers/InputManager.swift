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
    
    case ToggleFlaps
    case ToggleGear
    
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
    static var controller: Controller!
    static var pitchAxisFlipped: Bool = true
    
    #if os(macOS)
    static var joystick: Joystick!
    static var throttle: Throttle!
    #endif
    
    #if os(iOS)
    static var motion: MotionDevice!
    static var useMotion: Bool = true
    #endif
    
    public static func Initialize() {
        controller = Controller()
        
        #if os(macOS)
        joystick = Joystick()
        throttle = Throttle()
        #endif
        
        #if os(iOS)
        motion = MotionDevice()
        #endif
    }
    
    // TODO: These three computed properties follow the same initialization pattern.
    //       Wonder if there is a generic way to do this...
    static var keysPressed: [Keycodes: Bool] = {
        var kp: [Keycodes: Bool] = [Keycodes: Bool]()
        for kc in Keycodes.allCases {
            kp[kc] = false
        }
        return kp
    }()
    
    static var controllerDiscreteState: [ControllerState: Bool] = {
        var cds: [ControllerState: Bool] = [ControllerState: Bool]()
        for cs in ControllerState.allCases {
            cds[cs] = false
        }
        return cds
    }()
    
    #if os(macOS)
    static var joystickDiscreteState: [JoystickDiscreteState: Bool] = {
        var jbp: [JoystickDiscreteState: Bool] = [JoystickDiscreteState: Bool]()
        for jb in JoystickDiscreteState.allCases {
            jbp[jb] = false
        }
        return jbp
    }()
    #endif
    
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
        .JettisonFuelTank: .j,
        .ToggleFlaps: .f,
        .ToggleGear: .g
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
    
    #if os(macOS)
    static var joystickMappingsContinuous: [ContinuousCommand: JoystickContinuousState] = [
        .Pitch: .JoystickY,
        .Roll: .JoystickX
    ]
    
    static var joystickMappingsDiscrete: [DiscreteCommand: JoystickDiscreteState] = [
        .FireMissileAIM9: .TriggerFull,
        .FireMissileAIM120: .RedButton
    ]
    
    static var throttleMappingContinuous: [ContinuousCommand: ThrottleContinuousState] = [
        .MoveFwd: .ThrottleRight
    ]
    #endif
    
    #if os(iOS)
    static var motionMappingContinuous: [ContinuousCommand: MotionContinuousState] = [
        .Pitch: .MotionPitch,
        .Roll: .MotionRoll,
        .Yaw: .MotionYaw
    ]
    
    static var touchContinuousState: [ContinuousCommand: Float] = [
        .MoveFwd: 0.0,
        .MoveSide: 0.0,
        .Pitch: 0.0,
        .Roll: 0.0,
        .Yaw: 0.0
    ]
    #endif
    
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
    
    static func handleControllerDiscreteCommandDebounced(command: DiscreteCommand, _ handleBlock: () -> Void) {
        guard let controllerState = controllerMappingsDiscrete[command] else { return }
        guard let controllerCommandState = controllerDiscreteState[controllerState] else { return }
        let controllerValue = controller.getState(controllerState)
        if controllerValue > .zero {
            if !controllerCommandState {
                controllerDiscreteState[controllerState] = true
                handleBlock()
            }
        } else {
            if controllerCommandState {
                controllerDiscreteState[controllerState] = false
            }
        }
    }
    
    #if os(macOS)
    static func handleJoystickDiscreteCommandDebounced(command: DiscreteCommand, _ handleBlock: () -> Void) {
        guard let joystickState = joystickMappingsDiscrete[command] else { return }
        
        guard let joystickCommandState = joystickDiscreteState[joystickState] else {
            print("[InputManager handleJoystickDiscreteCommandDebounced] WARNING: Unknown joystick command: \(command)")
            return
        }
        
        guard let joystickValue = joystick.joystickDiscreteStateMapping[joystickState] else { return }
        
        if joystickValue {
            if !joystickCommandState {
                joystickDiscreteState[joystickState] = true
                handleBlock()
            }
        } else {
            if joystickCommandState {
                joystickDiscreteState[joystickState] = false
            }
        }
    }
    #endif
    
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
        
        #if os(macOS)
        if joystick.present {
            guard let joystickState = joystickMappingsDiscrete[command] else { return hasCommand }
            guard let joystickValue = joystick.joystickDiscreteStateMapping[joystickState] else { return hasCommand }
            hasCommand = hasCommand || joystickValue
        }
        #endif
        
        return hasCommand
    }
    
    static func GetControllerContinuousValue(_ command: ContinuousCommand) -> Float {
        guard let controllerState = controllerMappingsContinuous[command] else { return .zero }
        return controller.getState(controllerState)
    }
    
    #if os(macOS)
    static func GetJoystickContinuousValue(_ command: ContinuousCommand) -> Float {
        guard let joystickState = joystickMappingsContinuous[command] else { return .zero }
        guard let joystickValue = joystick.joystickContinuousStateMapping[joystickState] else { return .zero }
        return joystickValue
    }
    
    static func GetThrottleContinuousValue(_ command: ContinuousCommand) -> Float {
        guard let throttleState = throttleMappingContinuous[command] else { return .zero }
        guard let throttleValue = throttle.throttleContinuousStateMapping[throttleState] else { return .zero }
        return throttleValue
    }
    #endif
    
    #if os(iOS)
    static func GetMotionContinuousValue(_ command: ContinuousCommand) -> Float {
        guard let motionState = motionMappingContinuous[command] else { return .zero }
        guard let motionValue = motion.motionContinuousStateMapping[motionState] else { return .zero }
        return motionValue
    }
    #endif
    
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
            let controllerValue = GetControllerContinuousValue(command)
            if command == .Pitch && pitchAxisFlipped {
                continuousValue += -controllerValue
            } else {
                continuousValue += controllerValue
            }
        }
        
        #if os(macOS)
        if joystick.present {
            let joystickValue = GetJoystickContinuousValue(command)
            if command == .Pitch && !pitchAxisFlipped {
                continuousValue += -joystickValue
            } else {
                continuousValue += joystickValue
            }
        }
        
        if throttle.present {
            let throttleValue = GetThrottleContinuousValue(command)
            continuousValue += throttleValue
        }
        #endif
        
        #if os(iOS)
        if useMotion && motion.present {
            let motionValue = GetMotionContinuousValue(command)
            continuousValue += motionValue
        }
        
        continuousValue += touchContinuousState[command] ?? 0.0
        #endif
        
        return continuousValue
    }
    
    #if os(iOS)
    static func ZeroMotionDevice() {
        motion.zeroDevice()
    }
    #endif
    
    static func HasDiscreteCommandDebounced(command: DiscreteCommand, _ handleBlock: () -> Void) {
        guard let key = keyboardMappingsDiscrete[command] else { return }
        handleKeyPressedDebounced(keyCode: key, handleBlock)
        
        if controller.present {
            handleControllerDiscreteCommandDebounced(command: command, handleBlock)
        }
        
        #if os(macOS)
        if joystick.present {
            handleJoystickDiscreteCommandDebounced(command: command, handleBlock)
        }
        #endif
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
    
    #if os(iOS)
    static func SetContinuous(command: ContinuousCommand, value: Float) {
        touchContinuousState[command] = value
    }
    #endif
}
