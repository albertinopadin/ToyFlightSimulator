//
//  F16.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/29/22.
//

class F16: GameObject {
    private var _camera: DebugCamera?
    private let _camPositionOffset = float3(0, 2, 4)
    
    private var _moveSpeed: Float = 4.0
    private var _turnSpeed: Float = 1.0
    
    init() {
        super.init(name: "F-16", meshType: .F16)
    }
    
    init(camera: DebugCamera) {
        _camera = camera
        _camera?.setPosition(_camPositionOffset)
        _camera?.setRotationX(Float(25).toRadians)
        super.init(name: "F-16", meshType: .F16)
        
        // Results in gimbal lock and can't rotate on Z axis
//        self.setRotationY(Float(90).toRadians)
//        self.rotateY(Float(90).toRadians)
    }
    
    // TODO: Need to get 'z' axis from existing modelMatrix
    func getFwdVector() -> float3 {
        let fwd = normalize(self.modelMatrix.upperLeft3x3 * float3(0, 0, 1))
        print("fwd vector: \(fwd)")
        return fwd
    }
    
    func moveAlongVector(_ vector: float3, distance: Float) {
        let to = vector * distance
        self.move(to)
    }
    
    override func doUpdate() {
        if let _camera {
            if Keyboard.IsKeyPressed(.leftArrow) {
                self.rotateZ(GameTime.DeltaTime * _moveSpeed)
            }
            
            if Keyboard.IsKeyPressed(.rightArrow) {
                self.rotateZ(-GameTime.DeltaTime * _moveSpeed)
            }
            
            if Keyboard.IsKeyPressed(.upArrow) {
                self.rotateX(GameTime.DeltaTime * _moveSpeed)
            }
            
            if Keyboard.IsKeyPressed(.downArrow) {
                self.rotateX(-GameTime.DeltaTime * _moveSpeed)
            }
            
            if Keyboard.IsKeyPressed(.a) {
                self.moveX(-GameTime.DeltaTime * _moveSpeed)
            }
            
            if Keyboard.IsKeyPressed(.d) {
                self.moveX(GameTime.DeltaTime * _moveSpeed)
            }
            
            if Keyboard.IsKeyPressed(.w) {
                let pointing = getFwdVector()
                moveAlongVector(pointing, distance: -GameTime.DeltaTime * _moveSpeed)
            }
            
            if Keyboard.IsKeyPressed(.s) {
                let pointing = getFwdVector()
                moveAlongVector(pointing, distance: GameTime.DeltaTime * _moveSpeed)
            }
            
            if (Mouse.IsMouseButtonPressed(button: .LEFT)) {
                self.rotateX(-Mouse.GetDY() * GameTime.DeltaTime)
                self.rotateY(-Mouse.GetDX() * GameTime.DeltaTime)
            }
            
            if Mouse.IsMouseButtonPressed(button: .RIGHT) {
                self.rotate(Mouse.GetDY() * GameTime.DeltaTime * _turnSpeed,
                            Mouse.GetDX() * GameTime.DeltaTime * _turnSpeed,
                            0)
            }
            
            if Mouse.IsMouseButtonPressed(button: .CENTER) {
                self.moveX(-Mouse.GetDX() * GameTime.DeltaTime * _moveSpeed)
                self.moveY(Mouse.GetDY() * GameTime.DeltaTime * _moveSpeed)
            }
            
            self.moveZ(-Mouse.GetDWheel() * 0.1)
            
            _camera.setPosition(self.getPosition() + _camPositionOffset)
//            _camera.setRotation(-self.getRotation()) // <- not rotating correctly
        }
    }
}
