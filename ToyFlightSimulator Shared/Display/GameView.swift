//
//  GameView.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/29/22.
//

import MetalKit

class GameView: MTKView {
//    override func performKeyEquivalent(with event: NSEvent) -> Bool {
//        return true
//    }
}

// Keyboard input
extension GameView {
    override var acceptsFirstResponder: Bool { return true }
    
    override func keyDown(with event: NSEvent) {
//        print("Key Down: \(event.keyCode)")
//        print("Key Down modifier is command? \(event.modifierFlags.contains(.command))")
        Keyboard.SetKeyPressed(event.keyCode, pressed: true)
    }
    
    override func keyUp(with event: NSEvent) {
//        print("Key Up: \(event.keyCode)")
        Keyboard.SetKeyPressed(event.keyCode, pressed: false)
    }
}

// Mouse input
extension GameView {
    override func mouseDown(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
    }
    
    override func mouseUp(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
    }
    
    override func rightMouseUp(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
    }
    
    override func otherMouseDown(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: true)
    }
    
    override func otherMouseUp(with event: NSEvent) {
        Mouse.SetMouseButtonPressed(button: event.buttonNumber, isOn: false)
    }
}

// Mouse movement
extension GameView {
    override func mouseMoved(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        Mouse.ScrollMouse(deltaY: Float(event.deltaY))
    }
    
    override func mouseDragged(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }
    
    override func rightMouseDragged(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }
    
    override func otherMouseDragged(with event: NSEvent) {
        setMousePositionChanged(event: event)
    }
    
    private func setMousePositionChanged(event: NSEvent) {
        let overallLocation = SIMD2<Float>(Float(event.locationInWindow.x), Float(event.locationInWindow.y))
        let deltaChange = SIMD2<Float>(Float(event.deltaX), Float(event.deltaY))
        Mouse.SetMousePositionChange(overallPosition: overallLocation, deltaPosition: deltaChange)
    }
    
    override func updateTrackingAreas() {
        let area = NSTrackingArea(rect: self.bounds,
                                  options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag],
                                  owner: self,
                                  userInfo: nil)
        self.addTrackingArea(area)
    }
}
