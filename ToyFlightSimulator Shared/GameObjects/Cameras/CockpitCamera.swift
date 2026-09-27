//
//  CockpitCamera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/26.
//

import simd

/// First-person camera at the pilot's design eye point (DEP).
///
/// It is a child of the aircraft's cockpit node at zero offset, and the cockpit model's
/// origin IS the DEP, so the eye sits exactly where the HUD symbology was calibrated from.
/// It only rotates (head look). Any translation would move the eye off the DEP and slide the
/// painted HUD against the world, which is why this is not a second `AttachedCamera` (that
/// one translates on the wheel, middle-drag and i/j/k/l).
///
/// Head angles are relative to the aircraft's nose, in radians:
/// - `headYaw`: + looks right, a turn about the cockpit's up axis (+Y).
/// - `headPitch`: + looks up, a turn about the turned head's own right axis.
final class CockpitCamera: Camera {
    private static let NAME: String = "CockpitCamera"
    /// Head-turn limits that keep the view human: over the shoulder, and up/down.
    static let maxHeadYaw: Float = Float(150).toRadians
    static let maxHeadPitchUp: Float = Float(70).toRadians
    static let maxHeadPitchDown: Float = Float(80).toRadians
    /// Scales mouse pixels × frame time into radians of head turn, as `_turnSpeed` does in
    /// AttachedCamera, so both cameras turn at the same rate.
    private let turnSpeed: Float = 1.0

    private(set) var headYaw: Float = 0
    private(set) var headPitch: Float = 0

    init() {
        super.init(name: Self.NAME, cameraType: .Cockpit, aspectRatio: Renderer.AspectRatio)
    }

    init(fieldOfView: Float = 45.0, near: Float = 0.1, far: Float = 1000) {
        super.init(name: Self.NAME,
                   cameraType: .Cockpit,
                   aspectRatio: Renderer.AspectRatio,
                   fieldOfView: fieldOfView,
                   near: near,
                   far: far)
    }

    /// Parents the camera to `aircraft`'s cockpit node at zero offset (the eye point) and
    /// recentres the head. Always leaves the previous aircraft first; returns false, with
    /// the camera left unparented, when `aircraft` has no cockpit.
    @discardableResult
    func attach(to aircraft: Aircraft) -> Bool {
        parent?.removeChild(self)  // removeChild also clears `parent`
        guard let cockpit = aircraft.cockpit else { return false }
        setPosition(.zero)
        recenterHead()
        cockpit.addChild(self)
        aircraft.cockpitCamera = self
        return true
    }

    /// Adds a head turn, clamps it to the limits, and applies it as the local rotation.
    func turnHead(yawDelta: Float, pitchDelta: Float) {
        (headYaw, headPitch) = Self.turnedHead(yaw: headYaw,
                                               pitch: headPitch,
                                               yawDelta: yawDelta,
                                               pitchDelta: pitchDelta)
        setRotation(Self.headRotation(yaw: headYaw, pitch: headPitch))
    }

    /// Looks straight ahead along the nose again (through the HUD).
    func recenterHead() {
        headYaw = 0
        headPitch = 0
        setRotation(Self.headRotation(yaw: 0, pitch: 0))
    }

    /// The head angles after a turn, clamped to the limits. Pure (no camera, no Metal), so
    /// tests can drive it directly.
    static func turnedHead(yaw: Float,
                           pitch: Float,
                           yawDelta: Float,
                           pitchDelta: Float) -> (yaw: Float, pitch: Float) {
        ((yaw + yawDelta).clamp(min: -maxHeadYaw, max: maxHeadYaw),
         (pitch + pitchDelta).clamp(min: -maxHeadPitchDown, max: maxHeadPitchUp))
    }

    /// The camera's local rotation for the head angles: yaw about the cockpit's up axis, then
    /// pitch about the turned head's right axis. With column vectors that is Ry(yaw) · Rx(−pitch);
    /// the quaternion product applies its right factor first. Turning in this order never rolls
    /// the head: its right axis stays level. A positive angle about +X tips +Z (forward) toward
    /// −Y (down), so pitch is negated to make + look up.
    static func headRotation(yaw: Float, pitch: Float) -> simd_quatf {
        simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
    }

    override func doUpdate() {
        // Parented cameras update through the scene graph even when not current; without
        // this guard an inactive cockpit camera would consume the chase camera's mouse deltas.
        guard self.isActiveCamera else { return }

        if Mouse.IsMouseButtonPressed(button: .RIGHT) {
            // Mouse deltas are pixels. NSEvent reports deltaY as + for a downward move, so
            // dragging down looks down, as it does in AttachedCamera.
            let turnPerPixel = Float(GameTime.DeltaTime) * turnSpeed
            turnHead(yawDelta: Mouse.GetDX() * turnPerPixel,
                     pitchDelta: -Mouse.GetDY() * turnPerPixel)
        }

        if Mouse.IsMouseButtonPressed(button: .CENTER) || Keyboard.IsKeyPressed(.zero) {
            recenterHead()
        }

        // TODO: Find alternate keys as the arrows control the plane:
//        let keyTurn = Float(GameTime.DeltaTime) * turnSpeed
//        if Keyboard.IsKeyPressed(.upArrow)    { turnHead(yawDelta: 0, pitchDelta: keyTurn) }
//        if Keyboard.IsKeyPressed(.downArrow)  { turnHead(yawDelta: 0, pitchDelta: -keyTurn) }
//        if Keyboard.IsKeyPressed(.rightArrow) { turnHead(yawDelta: keyTurn, pitchDelta: 0) }
//        if Keyboard.IsKeyPressed(.leftArrow)  { turnHead(yawDelta: -keyTurn, pitchDelta: 0) }
//
//        // Moving the eye (i/k) takes it off the design eye point, so the HUD no longer lines up:
//        if Keyboard.IsKeyPressed(.i) {
//            self.moveY(Float(GameTime.DeltaTime) * 5.0)
//        }
//
//        if Keyboard.IsKeyPressed(.k) {
//            self.moveY(-Float(GameTime.DeltaTime) * 5.0)
//        }
    }
}
