//
//  Hotas.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 6/6/23.
//

import IOKit.hid
import Foundation


public extension Notification.Name {
    static let HIDDeviceDataReceived = Notification.Name("HIDDeviceDataReceived")
    static let HIDDeviceConnected = Notification.Name("HIDDeviceConnected")
    static let HIDDeviceDisconnected = Notification.Name("HIDDeviceDisconnected")
}

class Hotas {
    var gameControllerDevice: IOHIDDevice?

    init() {
        print("Hotas init")
        
//        RunLoop.current.run()
        
        let thread = Thread(target: self, selector: #selector(self.run), object: nil)
        thread.start()
        print("Exiting Hotas init")
        
//        NotificationCenter.default.addObserver(forName: .HIDDeviceConnected,
//                                               object: nil,
//                                               queue: nil) { [weak self] notification in
//            print("Got notification for HID Device Connected")
//        }
//
//        NotificationCenter.default.addObserver(forName: .HIDDeviceDisconnected,
//                                               object: nil,
//                                               queue: nil) { [weak self] notification in
//            print("Got notification for HID Device Disconnected")
//        }
    }
    
    @objc func run() {
        print("[Hotas run]")
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
//        let matchingDict = IOServiceMatching(kIOHIDDeviceKey)
        let matchingDict: NSMutableDictionary = [kIOHIDVendorIDKey: NSNumber(value: 0x044f),
                                                 kIOHIDProductIDKey: NSNumber(value: 0x0402)]


        IOHIDManagerSetDeviceMatching(manager, matchingDict)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Hotas.deviceMatchingCallback, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Hotas.deviceRemovalCallback, nil)
        
        RunLoop.current.run()
    }

    static let deviceMatchingCallback: IOHIDDeviceCallback = { inContext, inResult, inSender, device in
        print("[deviceMatchingCallback]")
        print("inContext: \(inContext), inResult: \(inResult), inSender: \(inSender), device: \(device)")
        guard let inContext else { return }
        let controller = Unmanaged<Hotas>.fromOpaque(inContext).takeUnretainedValue()
        controller.gameControllerDevice = device
        print("[deviceMatchingCallback] USB Joystick detected!")
    }

    static let deviceRemovalCallback: IOHIDDeviceCallback = { inContext, inResult, inSender, device in
        guard let inContext else { return }
        let controller = Unmanaged<Hotas>.fromOpaque(inContext).takeUnretainedValue()
        controller.gameControllerDevice = nil
        print("[deviceRemovalCallback] USB Joystick removed!")
    }
}
