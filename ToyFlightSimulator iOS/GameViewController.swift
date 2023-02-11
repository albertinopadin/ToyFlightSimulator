//
//  GameViewController.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 8/25/22.
//

import UIKit
import MetalKit

// Our iOS specific view controller
class GameViewController: UIViewController {
    var gameView: GameView!
    var renderer: Renderer!

    override func viewDidLoad() {
        super.viewDidLoad()

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
        gameView.depthStencilPixelFormat = .depth32Float_stencil8
        gameView.framebufferOnly = false
        gameView.preferredFramesPerSecond = 120
        
        Engine.Start(device: defaultDevice)
//        renderer = OITRenderer(gameView)  // Does not work if gameView.depthStencilPixelFormat = .depth32Float_stencil8
        renderer = SinglePassDeferredRenderer(gameView)
        SceneManager.SetScene(Preferences.StartingSceneType)
    }
}
