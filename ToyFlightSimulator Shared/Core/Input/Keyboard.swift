//
//  Keyboard.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import AppKit

class Keyboard {
    private static var KEY_COUNT: Int = 256
    private static var keys = [Bool](repeating: false, count: KEY_COUNT)
    
    public static func SetKeyPressed(_ keyCode: UInt16, pressed: Bool) {
        keys[Int(keyCode)] = pressed
    }
    
    public static func SetCommandKeyPressed(event: NSEvent) -> NSEvent {
        print("[SetCommandKeyPressed] event modifier flags: \(event.modifierFlags)")
        if event.modifierFlags.contains(.command) {
            print("Command pressed")
            keys[Int(Keycodes.command.rawValue)] = true
        } else {
            print("Command released")
            keys[Int(Keycodes.command.rawValue)] = false
        }
        return event
    }
    
    public static func IsKeyPressed(_ keyCode: Keycodes) -> Bool {
        return keys[Int(keyCode.rawValue)]
    }
}
