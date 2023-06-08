//
//  Hotas.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 6/6/23.
//  Heavily inspired by https://github.com/Arti3DPlayer/USBDeviceSwift

import IOKit.hid
import Foundation


public extension Notification.Name {
    static let HIDDeviceDataReceived = Notification.Name("HIDDeviceDataReceived")
    static let HIDDeviceConnected = Notification.Name("HIDDeviceConnected")
    static let HIDDeviceDisconnected = Notification.Name("HIDDeviceDisconnected")
}

class Hotas {
    static let reportSize: Int = 64
    
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
        let managerRef = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchingDict: NSMutableDictionary = [kIOHIDVendorIDKey: NSNumber(value: 0x044f),
                                                 kIOHIDProductIDKey: NSNumber(value: 0x0402)]


        IOHIDManagerSetDeviceMatching(managerRef, matchingDict)
        IOHIDManagerScheduleWithRunLoop(managerRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(managerRef, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let deviceMatchingCallback: IOHIDDeviceCallback = { inContext, inResult, inSender, inDeviceRef in
            print("[deviceMatchingCallback]")
            print("inContext: \(inContext), inResult: \(inResult), inSender: \(inSender), device ref: \(inDeviceRef)")
            let this:Hotas = unsafeBitCast(inContext, to: Hotas.self)
            this.deviceAdded(inResult, inSender: inSender!, inIOHIDDeviceRef: inDeviceRef)
        }

        let deviceRemovalCallback: IOHIDDeviceCallback = { inContext, inResult, inSender, inDeviceRef in
            let this:Hotas = unsafeBitCast(inContext, to: Hotas.self)
            this.deviceRemoved(inIOHIDDeviceRef: inDeviceRef)
        }
        
        IOHIDManagerRegisterDeviceMatchingCallback(managerRef,
                                                   deviceMatchingCallback,
                                                   unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        IOHIDManagerRegisterDeviceRemovalCallback(managerRef,
                                                  deviceRemovalCallback,
                                                  unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        
        RunLoop.current.run()
    }
    
    func deviceAdded(_ inResult: IOReturn, inSender: UnsafeMutableRawPointer, inIOHIDDeviceRef: IOHIDDevice!) {
        let report = UnsafeMutablePointer<UInt8>.allocate(capacity: Hotas.reportSize)
        let inputCallback: IOHIDReportCallback = { inContext, inResult, inSender, inType, reportId, report, reportLength in
            let this:Hotas = unsafeBitCast(inContext, to: Hotas.self)
            this.read(inResult, inSender: inSender!, type: inType, reportId: reportId, report: report, reportLength: reportLength)
        }
        
        IOHIDDeviceRegisterInputReportCallback(inIOHIDDeviceRef,
                                               report,
                                               Hotas.reportSize,
                                               inputCallback,
                                               unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
    }
    
    func deviceRemoved(inIOHIDDeviceRef: IOHIDDevice!) {
        print("[Hotas deviceRemoved]")
    }
    
    func read(_ inResult: IOReturn,
                     inSender: UnsafeMutableRawPointer,
                     type: IOHIDReportType,
                     reportId: UInt32,
                     report: UnsafeMutablePointer<UInt8>,
                     reportLength: CFIndex) {
        let data = Data(bytes: UnsafePointer<UInt8>(report), count: reportLength)
        // TODO: Make sense of this data:
//        print("[Hotas read] data: \(data.base64EncodedString())")
    }
}
