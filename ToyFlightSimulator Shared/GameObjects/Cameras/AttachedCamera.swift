//
//  AttachedCamera.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/2/22.
//

import simd

class AttachedCamera: Camera {
    private var _moveSpeed: Float = 4.0
    private var _turnSpeed: Float = 1.0
    private static let NAME: String = "AttachedCamera"
    
    init() {
        super.init(name: AttachedCamera.NAME, cameraType: .Attached, aspectRatio: Renderer.AspectRatio)
    }
    
    init(fieldOfView: Float = 45.0, near: Float = 0.1, far: Float = 1000) {
        super.init(name: AttachedCamera.NAME,
                   cameraType: .Attached,
                   aspectRatio: Renderer.AspectRatio,
                   fieldOfView: fieldOfView,
                   near: near,
                   far: far)
    }
    
    public func attach(to node: Node, offset: float3 = [0, 2, -4], rotation: float3 = [Float(-5).toRadians, 0, 0]) {
        // Detach if currently attached to another node:
        self.parent?.removeChild(self)
        
        // Zero camera rotation first:
        self.setRotationX(0)
        self.setRotationY(0)
        self.setRotationZ(0)
        
        self.rotate3Axis(deltaX: rotation.x, deltaY: rotation.y, deltaZ: rotation.z)
        self.setPosition(offset)
        node.addChild(self)
    }
    
    // To make a camera follow a node, invert the camera's model matrix.
    // A camera has no mesh, so a scaled parent (e.g. a setScale(3) jet) should
    // not warp its view. Strip the inherited scale: keep world position +
    // orientation, drop scale, then invert. Perspective is scale-invariant so
    // the rendered scene is unchanged, but view-space distances now equal world
    // distances — which lets the CSM fitter work in true world units regardless
    // of the parent's scale (no hidden 1/scale factor on near/far).
    override func computeViewMatrix(from world: float4x4) -> float4x4 {
        AttachedCamera.scaleStrippedInverse(of: world)
    }

    /// Inverse of a rigid (scale-free) world transform derived from `world`:
    /// translation kept, basis re-orthonormalized to remove (uniform) scale.
    /// Internal (not private) so it can be unit-tested directly.
    static func scaleStrippedInverse(of world: float4x4) -> float4x4 {
        let x = simd_normalize(world.columns.0.xyz)
        let y = simd_normalize(world.columns.1.xyz)
        let z = simd_normalize(world.columns.2.xyz)
        let t = world.columns.3.xyz
        let rigid = float4x4(SIMD4<Float>(x, 0),
                             SIMD4<Float>(y, 0),
                             SIMD4<Float>(z, 0),
                             SIMD4<Float>(t, 1))
        return rigid.inverse
    }

    // update() override removed: the generation-checked viewMatrix getter in
    // Camera covers both own-transform changes and parent propagation, so no
    // per-frame worldMatrixDirty hook is needed anymore.

    override func doUpdate() {
        // Parented cameras update via scene-graph traversal even when not
        // current — without this guard every chase camera in the scene would
        // keep consuming right-drag/wheel/i-j-k-l while another camera is active.
        guard isActiveCamera else { return }

        if Mouse.IsMouseButtonPressed(button: .RIGHT) {
            self.rotate3Axis(deltaX: Mouse.GetDY() * Float(GameTime.DeltaTime) * _turnSpeed,
                             deltaY: Mouse.GetDX() * Float(GameTime.DeltaTime) * _turnSpeed,
                             deltaZ: 0)
        }
        
        if Mouse.IsMouseButtonPressed(button: .CENTER) {
            self.moveX(-Mouse.GetDX() * Float(GameTime.DeltaTime) * _moveSpeed)
            self.moveY(Mouse.GetDY() * Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.i) {
            self.moveY(Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.k) {
            self.moveY(-Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.l) {
            self.moveX(Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        if Keyboard.IsKeyPressed(.j) {
            self.moveX(-Float(GameTime.DeltaTime) * _moveSpeed)
        }
        
        self.moveZ(Mouse.GetDWheel() * 0.1)
    }
}
