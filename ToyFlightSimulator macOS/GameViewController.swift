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
class GameViewController: NSHostingController<MacGameUIView> {
    required init?(coder: NSCoder) {
        print("GameViewController init with coder")
        super.init(coder: coder, rootView: MacGameUIView())
    }
    
    override func viewDidLoad() {
        print("GameViewController viewDidLoad")
        super.viewDidLoad()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: Keyboard.KeyDown(with:))
        NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: Keyboard.KeyUp(with:))
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: Keyboard.SetCommandKeyPressed(event:))
    }
}
