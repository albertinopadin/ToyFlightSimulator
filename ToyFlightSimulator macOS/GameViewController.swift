//
//  GameViewController.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 8/25/22.
//

import Cocoa
import MetalKit
import SwiftUI

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
class GameViewController: NSHostingController<GameUIView> {
    var gameView: GameView!
    var renderer: Renderer!
    // TODO:
    // - Create Metal device (& set it on GameView)
    // - Set view prefs (clearColor, colorPixelFormat, depthStencilPixelFormat (?), framebufferOnly)
    // - Start Engine
    // - Instantiate Renderer -> pass GameView as param so it can set itself as MtkViewDelegate
    // - Set initial scene
    
    required init?(coder: NSCoder) {
        print("GameViewController init with coder")
        super.init(coder: coder, rootView: GameUIView())
    }
    
    override func viewDidLoad() {
        print("GameViewController viewDidLoad")
        super.viewDidLoad()

        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: Keyboard.SetCommandKeyPressed(event:))
    }
    
    override func viewDidLayout() {
//        print("[GameViewController viewDidLayout] view.bounds.size: \(view.bounds.size)")
//        print("[GameViewController viewDidLayout] view.frame.size: \(view.frame.size)")
//
//        print("[GameViewController viewDidLayout] view.window?.frame.size: \(view.window?.frame.size)")
//        print("[GameViewController viewDidLayout] view.window?.contentView?.frame.size: \(view.window?.contentView?.frame.size)")
//        print("[GameViewController viewDidLayout] view.window?.contentView?.bounds: \(view.window?.contentView?.bounds)")
        
//        rootView = GameUIView(viewSize: view.bounds.size)
    }
}
