//
//  IOSMetalViewWrapper.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 8/5/23.
//

import SwiftUI

struct IOSMetalViewWrapper: UIViewRepresentable {
    typealias UIViewType = GameView
    
    var viewSize: CGSize
    var refreshRate: FPS
    
    func makeCoordinator() -> Void {
        let rendererType: RendererType = .OrderIndependentTransparency
        // TODO: Single Pass renderer doesn't work due to a memory issue:
//        let rendererType: RendererType = .SinglePassDeferredLighting
        Engine.Start(rendererType: rendererType)
    }
    
    func makeUIView(context: Context) -> GameView {
        let gameView = GameView()
        gameView.device = Engine.Device
        gameView.clearColor = Preferences.ClearColor
        gameView.colorPixelFormat = Preferences.MainPixelFormat
        gameView.framebufferOnly = false
        gameView.preferredFramesPerSecond = refreshRate.rawValue
        gameView.drawableSize = viewSize
        
        Engine.renderer!.metalView = gameView
        SceneManager.SetScene(Preferences.StartingSceneType,
                              mtkView: gameView,
                              rendererType: Engine.renderer!.rendererType)
        
        return gameView
    }
    
    func updateUIView(_ nsView: UIViewType, context: Context) {
        Engine.renderer!.metalView.preferredFramesPerSecond = refreshRate.rawValue
        
        // Query renderer to see if screen size has already been set: (is there a better way to do this...?)
        if !((Engine.renderer as? OITRenderer)?.alreadySetScreenSize ?? false) {
            let newSize = nsView.bounds.size
            print("[updateUIView] newSize: \(newSize)")
            if newSize.width > 0 && newSize.width.isNormal && newSize.height > 0 && newSize.height.isNormal {
                Engine.renderer!.metalView.drawableSize = nsView.bounds.size
            }
        }
    }
}

struct IOSMetalViewWrapper_Previews: PreviewProvider {
    static var previewSize = CGSize(width: 1920, height: 1080)
    static var previews: some View {
        IOSMetalViewWrapper(viewSize: previewSize, refreshRate: .FPS_120)
    }
}

