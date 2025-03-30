//
//  Mouse.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import os

enum MOUSE_BUTTON_CODES: Int {
    case LEFT   = 0
    case RIGHT  = 1
    case CENTER = 2
}

enum MouseState: Int, CaseIterable {
    case leftClick = 0
    case rightClick = 1
}

class Mouse {
    private static let lock = OSAllocatedUnfairLock()
    
    private static let MOUSE_BUTTON_COUNT = 12
    nonisolated(unsafe) private static var mouseButtonList = [Bool](repeating: false, count: MOUSE_BUTTON_COUNT)
    
    nonisolated(unsafe) private static var overallMousePosition = float2(0, 0)
    nonisolated(unsafe) private static var mousePositionDelta = float2(0, 0)
    
    nonisolated(unsafe) private static var scrollWheelPosition: Float = 0
    nonisolated(unsafe) private static var scrollWheelChange: Float = 0.0
    
    public static func SetMouseButtonPressed(button: Int) {
        lock.withLock {
            mouseButtonList[button] = true
        }
    }
    
    public static func SetMouseButtonReleased(button: Int) {
        lock.withLock {
            mouseButtonList[button] = false
        }
    }
    
    public static func IsMouseButtonPressed(button: MOUSE_BUTTON_CODES) -> Bool {
        lock.withLock {
            return mouseButtonList[Int(button.rawValue)]
        }
    }
    
    public static func SetOverallMousePosition(position: float2) {
        lock.withLock {
            overallMousePosition = position
        }
    }
    
    public static func SetMousePositionChange(overallPosition: float2, deltaPosition: float2) {
        lock.withLock {
            overallMousePosition = overallPosition
            mousePositionDelta = deltaPosition
        }
    }
    
    public static func ScrollMouse(deltaY: Float) {
        lock.withLock {
            scrollWheelPosition += deltaY
            scrollWheelChange += deltaY
        }
    }
    
    public static func GetMouseWindowPosition() -> float2 {
        lock.withLock {
            return overallMousePosition
        }
    }
    
    public static func GetDWheel() -> Float {
        lock.withLock {
            let position = scrollWheelChange
            scrollWheelChange = 0
            return -position
        }
    }
    
    public static func GetDY() -> Float {
        lock.withLock {
            let result = mousePositionDelta.y
            mousePositionDelta.y = 0
            return result
        }
    }
    
    public static func GetDX() -> Float {
        lock.withLock {
            let result = mousePositionDelta.x
            mousePositionDelta.x = 0
            return result
        }
    }
    
    public static func GetMouseViewportPosition() -> float2 {
        lock.withLock {
            let x = (overallMousePosition.x - Renderer.ScreenSize.x * 0.5) / (Renderer.ScreenSize.x * 0.5)
            let y = (overallMousePosition.y - Renderer.ScreenSize.y * 0.5) / (Renderer.ScreenSize.y * 0.5)
            return float2(x, y)
        }
    }
}
