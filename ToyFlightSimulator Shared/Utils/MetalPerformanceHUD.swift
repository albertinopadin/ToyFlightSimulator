//
//  MetalPerformanceHUD.swift
//  ToyFlightSimulator
//
//  Toggles Apple's built-in Metal Performance HUD on the active drawable layer.
//

import MetalKit
import QuartzCore

enum MetalPerformanceHUD {
    nonisolated(unsafe) private(set) static var isEnabled = false

    /// Show/hide Apple's Metal Performance HUD on the active drawable layer.
    /// No-op if there is no Metal view yet, or in non-development builds where
    /// the runtime ignores `developerHUDProperties`.
    @MainActor
    static func setEnabled(_ enabled: Bool) {
        guard let layer = Engine.MetalView?.layer as? CAMetalLayer else {
            print("[MetalPerformanceHUD] No CAMetalLayer available.")
            return
        }
        layer.developerHUDProperties = enabled
            ? ["mode": "default", "logging": "default"]
            : ["mode": "none"]
        isEnabled = enabled
        print("[MetalPerformanceHUD] \(enabled ? "enabled" : "disabled")")
    }

    @MainActor
    static func toggle() {
        setEnabled(!isEnabled)
    }
}
