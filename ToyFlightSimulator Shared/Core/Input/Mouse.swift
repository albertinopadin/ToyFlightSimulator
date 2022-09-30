//
//  Mouse.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

enum MOUSE_BUTTON_CODES: Int {
    case LEFT   = 0
    case RIGHT  = 1
    case CENTER = 2
}

class Mouse {
    private static var MOUSE_BUTTON_COUNT = 12
    private static var mouseButtonList = [Bool](repeating: false, count: MOUSE_BUTTON_COUNT)
    
    private static var overallMousePosition = float2(0, 0)
    private static var mousePositionDelta = float2(0, 0)
    
    private static var scrollWheelPosition: Float = 0
    private static var lastWheelPosition: Float = 0.0
    private static var scrollWheelChange: Float = 0.0
    
    public static func SetMouseButtonPressed(button: Int, isOn: Bool) {
        mouseButtonList[button] = isOn
    }
    
    public static func IsMouseButtonPressed(button: MOUSE_BUTTON_CODES) -> Bool {
        return mouseButtonList[Int(button.rawValue)]
    }
    
    public static func SetOverallMousePosition(position: float2) {
        overallMousePosition = position
    }
    
    public static func SetMousePositionChange(overallPosition: float2, deltaPosition: float2) {
        overallMousePosition = overallPosition
        mousePositionDelta = deltaPosition
    }
    
    public static func ScrollMouse(deltaY: Float) {
        scrollWheelPosition += deltaY
        scrollWheelChange += deltaY
    }
    
    public static func GetMouseWindowPosition() -> float2 {
        return overallMousePosition
    }
    
    public static func GetDWheel() -> Float {
        let position = scrollWheelChange
        scrollWheelChange = 0
        return -position
    }
    
    public static func GetDY() -> Float {
        let result = mousePositionDelta.y
        mousePositionDelta.y = 0
        return result
    }
    
    public static func GetDX() -> Float {
        let result = mousePositionDelta.x
        mousePositionDelta.x = 0
        return result
    }
    
    public static func GetMouseViewportPosition() -> float2 {
        let x = (overallMousePosition.x - Renderer.ScreenSize.x * 0.5) / (Renderer.ScreenSize.x * 0.5)
        let y = (overallMousePosition.y - Renderer.ScreenSize.y * 0.5) / (Renderer.ScreenSize.y * 0.5)
        return float2(x, y)
    }
}
