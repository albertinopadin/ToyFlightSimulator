//
//  DebugLog.swift
//  ToyFlightSimulator
//
//  Conditional print() wrapper. The `enabled` flag (typically a static let in
//  Preferences) gates the call; the @autoclosure on `message` means the string
//  is only built when enabled is true — passing a complex interpolation when
//  the flag is off costs only one branch.
//
//      DebugLog("force: \(f)", DEBUG_FORCES)
//

@inlinable
func DebugLog(_ message: @autoclosure () -> String, _ enabled: Bool) {
    if enabled {
        print(message())
    }
}
