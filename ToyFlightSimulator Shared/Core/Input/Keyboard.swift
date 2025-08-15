//
//  Keyboard.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import os

#if os(macOS)
import AppKit
typealias Event = NSEvent
#endif

#if os(iOS)
import UIKit
typealias Event = UIEvent
#endif

final class Keyboard {
    private static let KEY_COUNT: Int = 256
    
    private static let keysLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var keys = [Bool](repeating: false, count: KEY_COUNT)
    
    public static func SetKeyPressed(_ keyCode: UInt16, pressed: Bool) {
        withLock(keysLock) {
            keys[Int(keyCode)] = pressed
        }
    }

#if os(macOS)
    public static func KeyDown(with event: Event) -> Event? {
        SetKeyPressed(event.keyCode, pressed: true)
        // Return nil to prevent beep sound
        return nil
    }
    
    public static func KeyUp(with event: Event) -> Event? {
        SetKeyPressed(event.keyCode, pressed: false)
        // Return nil to prevent beep sound
        return nil
    }
#endif
    
    @MainActor public static func SetCommandKeyPressed(event: Event) -> Event {
//        print("[SetCommandKeyPressed] event modifier flags: \(event.modifierFlags)")
        if event.modifierFlags.contains(.command) {
            keys[Int(Keycodes.command.rawValue)] = true
        } else {
            keys[Int(Keycodes.command.rawValue)] = false
        }
        return event
    }
    
    public static func IsKeyPressed(_ keyCode: Keycodes) -> Bool {
        return keys[Int(keyCode.rawValue)]
    }
}
