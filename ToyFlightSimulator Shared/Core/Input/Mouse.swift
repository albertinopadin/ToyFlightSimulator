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

final class Mouse {
    private static let MOUSE_BUTTON_COUNT = 12
    
    private static let mouseButtonListLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var mouseButtonList = [Bool](repeating: false, count: MOUSE_BUTTON_COUNT)
    
    private static let overallMousePositionLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var overallMousePosition = float2(0, 0)
    
    private static let mousePositionDeltaLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var mousePositionDelta = float2(0, 0)
    
    private static let scrollWheelPositionLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var scrollWheelPosition: Float = 0
    
    private static let scrollWheelChangeLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var scrollWheelChange: Float = 0.0
    
    public static func SetMouseButtonPressed(button: Int) {
        withLock(mouseButtonListLock) {
            mouseButtonList[button] = true
        }
    }
    
    public static func SetMouseButtonReleased(button: Int) {
        withLock(mouseButtonListLock) {
            mouseButtonList[button] = false
        }
    }
    
    public static func IsMouseButtonPressed(button: MOUSE_BUTTON_CODES) -> Bool {
        return withLock(mouseButtonListLock) {
            return mouseButtonList[Int(button.rawValue)]
        }
    }
    
    public static func SetOverallMousePosition(position: float2) {
        withLock(overallMousePositionLock) {
            overallMousePosition = position
        }
    }
    
    public static func SetMousePositionChange(overallPosition: float2, deltaPosition: float2) {
        withLock(overallMousePositionLock) {
            overallMousePosition = overallPosition
        }
        
        withLock(mousePositionDeltaLock) {
            mousePositionDelta = deltaPosition
        }
    }
    
    public static func ScrollMouse(deltaY: Float) {
        withLock(scrollWheelPositionLock) {
            scrollWheelPosition += deltaY
        }
        
        withLock(scrollWheelChangeLock) {
            scrollWheelChange += deltaY
        }
    }
    
    public static func GetMouseWindowPosition() -> float2 {
        return withLock(overallMousePositionLock) {
            return overallMousePosition
        }
    }
    
    public static func GetDWheel() -> Float {
        return withLock(scrollWheelChangeLock) {
            let position = scrollWheelChange
            scrollWheelChange = 0
            return -position
        }
    }
    
    public static func GetDY() -> Float {
        return withLock(mousePositionDeltaLock) {
            let result = mousePositionDelta.y
            mousePositionDelta.y = 0
            return result
        }
    }
    
    public static func GetDX() -> Float {
        return withLock(mousePositionDeltaLock) {
            let result = mousePositionDelta.x
            mousePositionDelta.x = 0
            return result
        }
    }
    
    public static func GetMouseViewportPosition() -> float2 {
        return withLock(overallMousePositionLock) {
            let x = (overallMousePosition.x - Renderer.ScreenSize.x * 0.5) / (Renderer.ScreenSize.x * 0.5)
            let y = (overallMousePosition.y - Renderer.ScreenSize.y * 0.5) / (Renderer.ScreenSize.y * 0.5)
            return float2(x, y)
        }
    }
}
