//
//  GameViewController.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 8/25/22.
//

import Cocoa
import MetalKit

//enum VirtualKey: Int {
//    case ANSI_A     = 0x00
//    case ANSI_S     = 0x01
//    case ANSI_D     = 0x02
//    case ANSI_W     = 0x0D
//    case space      = 0x31
//    case leftArrow  = 0x7B
//    case rightArrow = 0x7C
//    case downArrow  = 0x7D
//    case upArrow    = 0x7E
//}

// Our macOS specific view controller
class GameViewController: NSViewController {
    var gameView: GameView!
    var renderer: Renderer!
    // TODO:
    // - Create Metal device (& set it on GameView)
    // - Set view prefs (clearColor, colorPixelFormat, depthStencilPixelFormat (?), framebufferOnly)
    // - Start Engine
    // - Instantiate Renderer -> pass GameView as param so it can set itself as MtkViewDelegate
    // - Set initial scene
    
//    var cameraController: FlyCameraController!

//    var gameController: GCController?
//    var virtualController: Any?
//
//    private var observers = [Any]()
//
//    deinit {
//        for observer in observers {
//            NotificationCenter.default.removeObserver(observer)
//        }
//    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: Keyboard.SetCommandKeyPressed(event:))

        guard let _gameView = self.view as? GameView else {
            print("View attached to GameViewController is not a GameView")
            return
        }
        
        gameView = _gameView

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        gameView.device = defaultDevice
        gameView.clearColor = Preferences.ClearColor
        gameView.colorPixelFormat = Preferences.MainPixelFormat
        gameView.framebufferOnly = false
        gameView.preferredFramesPerSecond = 120
        
        Engine.Start(device: defaultDevice)
        let rendererType: RendererType = .SinglePassDeferredLighting
        renderer = initRenderer(type: rendererType)
        SceneManager.SetScene(Preferences.StartingSceneType, rendererType: rendererType)
        
//        cameraController = FlyCameraController(pointOfView: simController.renderer.pointOfView)
//        cameraController.eye = SIMD3<Float>(0, 0, 4)
//
//        let frameDuration = 1.0 / Double(mtkView.preferredFramesPerSecond)
//        Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { [weak self] _ in
//            self?.updateCamera(Float(frameDuration))
//        }
    }
    
    func initRenderer(type: RendererType) -> Renderer {
        switch type {
            case .OrderIndependentTransparency:
                // Does not work if gameView.depthStencilPixelFormat = .depth32Float_stencil8
                return OITRenderer(gameView)
            case .SinglePassDeferredLighting:
                gameView.depthStencilPixelFormat = .depth32Float_stencil8
                return SinglePassDeferredLightingRenderer(gameView)
        }
    }

//    func updateCamera(_ timestep: Float) {
//        if let gamepad = gameController?.extendedGamepad {
//            let lookX = gamepad.rightThumbstick.xAxis.value
//            let lookZ = gamepad.rightThumbstick.yAxis.value
//            let lookDelta = SIMD2<Float>(lookX, lookZ)
//
//            let moveZ = gamepad.leftThumbstick.yAxis.value
//            let moveDelta = SIMD2<Float>(0, moveZ)
//
//            cameraController.update(timestep: timestep,
//                                    lookDelta: lookDelta,
//                                    moveDelta: moveDelta)
//        } else {
//            let cursorDeltaX = Float(currentMousePoint.x - previousMousePoint.x)
//            let cursorDeltaY = Float(currentMousePoint.y - previousMousePoint.y)
//            previousMousePoint = currentMousePoint
//
//            let forwardPressed = keysPressed[VirtualKey.ANSI_W.rawValue]
//            let backwardPressed = keysPressed[VirtualKey.ANSI_S.rawValue]
//            let leftPressed = keysPressed[VirtualKey.ANSI_A.rawValue]
//            let rightPressed = keysPressed[VirtualKey.ANSI_D.rawValue]
//
//            let deltaX: Float = (leftPressed ? -1.0 : 0.0) + (rightPressed ? 1.0 : 0.0)
//            let deltaZ: Float = (backwardPressed ? -1.0 : 0.0) + (forwardPressed ? 1.0 : 0.0)
//
//            let mouseDelta = SIMD2<Float>(cursorDeltaX, cursorDeltaY)
//            let keyDelta = SIMD2<Float>(deltaX, deltaZ)
//            cameraController.update(timestep: timestep,
//                                    lookDelta: mouseDelta,
//                                    moveDelta: keyDelta)
//        }
//    }
}
