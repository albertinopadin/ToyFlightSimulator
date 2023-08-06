//
//  Keyboard.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

#if os(macOS)
import AppKit
typealias Event = NSEvent
#endif

#if os(iOS)
import UIKit
typealias Event = UIEvent
#endif

class Keyboard {
    private static var KEY_COUNT: Int = 256
    private static var keys = [Bool](repeating: false, count: KEY_COUNT)
    
    public static func SetKeyPressed(_ keyCode: UInt16, pressed: Bool) {
        keys[Int(keyCode)] = pressed
    }
    
    public static func SetCommandKeyPressed(event: Event) -> Event {
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
