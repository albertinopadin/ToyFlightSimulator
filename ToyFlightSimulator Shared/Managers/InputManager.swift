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
    case ClickSelect
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

final class InputManager {
    private static var controller: Controller!
    private static var pitchAxisFlipped: Bool = true
    
    #if os(macOS)
    private static var joystick: Joystick!
    private static var throttle: Throttle!
    #endif
    
    #if os(iOS)
    private static var motion: MotionDevice!
    public static var useMotion: Bool = true
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
    private static var keysPressed: [Keycodes: Bool] = {
        var kp = [Keycodes: Bool]()
        for kc in Keycodes.allCases {
            kp[kc] = false
        }
        return kp
    }()
    
    private static var controllerDiscreteState: [ControllerState: Bool] = {
        var cds = [ControllerState: Bool]()
        for cs in ControllerState.allCases {
            cds[cs] = false
        }
        return cds
    }()
    
    // Perhaps instead of 'Discrete States' should name this 'Key Pressed' ???
    private static var mouseDiscreteState: [MouseState: Bool] = {
        var mds = [MouseState: Bool]()
        for mouseState in MouseState.allCases {
            mds[mouseState] = false
        }
        return mds
    }()
    
    #if os(macOS)
    private static var joystickDiscreteState: [JoystickDiscreteState: Bool] = {
        var jbp = [JoystickDiscreteState: Bool]()
        for jb in JoystickDiscreteState.allCases {
            jbp[jb] = false
        }
        return jbp
    }()
    #endif
    
    private static var mouseMappingsDiscrete: [DiscreteCommand: MouseState] = [
        .ClickSelect: .leftClick
    ]
    
    private static var keyboardMappingsContinuous: [ContinuousCommand: [KeycodeValue]] = [
        .MoveFwd: [KeycodeValue(keyCode: .w, value: 1.0), KeycodeValue(keyCode: .s, value: -1.0)],
        .MoveSide: [KeycodeValue(keyCode: .d, value: 1.0), KeycodeValue(keyCode: .a, value: -1.0)],
        .Pitch: [KeycodeValue(keyCode: .upArrow, value: pitchAxisFlipped ? -1.0 : 1.0),
                 KeycodeValue(keyCode: .downArrow, value: pitchAxisFlipped ? 1.0 : -1.0)],
        .Roll: [KeycodeValue(keyCode: .rightArrow, value: 1.0), KeycodeValue(keyCode: .leftArrow, value: -1.0)],
        .Yaw: [KeycodeValue(keyCode: .e, value: -1.0), KeycodeValue(keyCode: .q, value: 1.0)]
    ]
    
    private static var keyboardMappingsDiscrete: [DiscreteCommand: Keycodes] = [
        .Pause: .p,
        .ResetLoadout: .l,
        .FireMissileAIM9: .space,
        .FireMissileAIM120: .n,
        .DropBomb: .m,
        .JettisonFuelTank: .j,
        .ToggleFlaps: .f,
        .ToggleGear: .g
    ]
    
    private static var multiKeyInputMappings: [SpecialUserCommand: [Keycodes]] = [
        .ResetScene: [.command, .r]
    ]
    
    private static var specialCommandsActive: [SpecialUserCommand: Bool] = {
        var sca: [SpecialUserCommand: Bool] = [SpecialUserCommand: Bool]()
        for suc in SpecialUserCommand.allCases {
            sca[suc] = false
        }
        return sca
    }()
    
    private static var controllerMappingsContinuous: [ContinuousCommand: ControllerState] = [
        .Roll: .RightStickX,
        .Pitch: .RightStickY,
        .MoveFwd: .LeftStickY,
        .MoveSide: .LeftStickX
    ]
    
    private static var controllerMappingsDiscrete: [DiscreteCommand: ControllerState] = [
        .FireMissileAIM9: .RightTrigger,
        .DropBomb: .LeftTrigger
    ]
    
    #if os(macOS)
    private static var joystickMappingsContinuous: [ContinuousCommand: JoystickContinuousState] = [
        .Pitch: .JoystickY,
        .Roll: .JoystickX
    ]
    
    private static var joystickMappingsDiscrete: [DiscreteCommand: JoystickDiscreteState] = [
        .FireMissileAIM9: .TriggerFull,
        .FireMissileAIM120: .RedButton
    ]
    
    private static var throttleMappingContinuous: [ContinuousCommand: ThrottleContinuousState] = [
        .MoveFwd: .ThrottleRight
    ]
    #endif
    
    #if os(iOS)
    private static var motionMappingContinuous: [ContinuousCommand: MotionContinuousState] = [
        .Pitch: .MotionPitch,
        .Roll: .MotionRoll,
        .Yaw: .MotionYaw
    ]
    
    private static var touchContinuousState: [ContinuousCommand: Float] = [
        .MoveFwd: 0.0,
        .MoveSide: 0.0,
        .Pitch: 0.0,
        .Roll: 0.0,
        .Yaw: 0.0
    ]
    #endif
    
    static func HandleMouseClickDebounced(command: DiscreteCommand, _ handleBlock: () -> Void) {
        guard let mouseState = mouseMappingsDiscrete[command] else { return }
        guard let mouseCommandState = mouseDiscreteState[mouseState] else { return }
        let mouseButtonClicked = Mouse.IsMouseButtonPressed(button: MOUSE_BUTTON_CODES(rawValue: mouseState.rawValue)!)
        if mouseButtonClicked {
            if !mouseCommandState {
                mouseDiscreteState[mouseState] = true
                handleBlock()
            }
        } else {
            if mouseCommandState {
                mouseDiscreteState[mouseState] = false
            }
        }
    }
    
    static func HandleKeyPressedDebounced(keyCode: Keycodes, _ handleBlock: () -> Void) {
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
    
    static func HandleControllerDiscreteCommandDebounced(command: DiscreteCommand, _ handleBlock: () -> Void) {
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
    static func HandleJoystickDiscreteCommandDebounced(command: DiscreteCommand, _ handleBlock: () -> Void) {
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
        HandleKeyPressedDebounced(keyCode: key, handleBlock)
        
        if controller.present {
            HandleControllerDiscreteCommandDebounced(command: command, handleBlock)
        }
        
        #if os(macOS)
        if joystick.present {
            HandleJoystickDiscreteCommandDebounced(command: command, handleBlock)
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
        
//        print("[HasMultiInputCommand] All keys (\(keyboardCommandws)) pressed: \(allKeysPressed)")
        
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
