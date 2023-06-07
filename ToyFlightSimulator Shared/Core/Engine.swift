//
//  Engine.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/25/22.
//

import MetalKit

class Engine {
    public static var Device: MTLDevice!
    public static var CommandQueue: MTLCommandQueue!
    public static var DefaultLibrary: MTLLibrary!
    
    public static func Start(device: MTLDevice) {
        self.Device = device
        self.CommandQueue = device.makeCommandQueue()
        self.DefaultLibrary = device.makeDefaultLibrary()
        
        Graphics.Initialize()
        Assets.Initialize()
        InputManager.Initialize()
    }
}
