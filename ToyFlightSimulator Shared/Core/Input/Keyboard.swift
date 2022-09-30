//
//  Keyboard.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

class Keyboard {
    private static var KEY_COUNT: Int = 256
    private static var keys = [Bool](repeating: false, count: KEY_COUNT)
    
    public static func SetKeyPressed(_ keyCode: UInt16, inOn: Bool) {
        keys[Int(keyCode)] = inOn
    }
    
    public static func IsKeyPressed(_ keyCode: Keycodes) -> Bool {
        return keys[Int(keyCode.rawValue)]
    }
}
