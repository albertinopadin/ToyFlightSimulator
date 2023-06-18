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

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

enum JoystickContinuousState {
    case JoystickX
    case JoystickY
}

enum JoystickDiscreteState: CaseIterable {
    case RedButton
    case TriggerSemi
    case TriggerFull
    case TrimUp
    case TrimDown
    case TrimLeft
    case TrimRight
}

class Joystick {
    static let reportSize: Int = 64
    
    var joystickDevice: IOHIDDevice?
    var present: Bool = false
    
    var lastData = Data()
    let buttonDataRange = 0..<4
    let axisDataRange = 4..<12
    
    var hidElementPagesUsages: [UInt32: [UInt32: Int]] = [:]
    
    var lastReportErrors = 0
    
    var joystickContinuousStateMapping: [JoystickContinuousState: Float] = [
        .JoystickX: 0.0,
        .JoystickY: 0.0
    ]
    
    var joystickDiscreteStateMapping: [JoystickDiscreteState: Bool] = [
        .RedButton: false,
        .TriggerSemi: false,
        .TriggerFull: false
    ]
    
    // TODO: Get this dynamically from HID input reports:
    let xyMin: Int = 0
    let xyMax: Int = 65_535
    let xyZero: Int = 32_768

    init() {
        let thread = Thread(target: self, selector: #selector(self.run), object: nil)
        thread.start()
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
            let this: Joystick = unsafeBitCast(inContext, to: Joystick.self)
            this.deviceAdded(inResult, inSender: inSender!, inIOHIDDeviceRef: inDeviceRef)
        }

        let deviceRemovalCallback: IOHIDDeviceCallback = { inContext, inResult, inSender, inDeviceRef in
            let this: Joystick = unsafeBitCast(inContext, to: Joystick.self)
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
        present = true
        joystickDevice = inIOHIDDeviceRef
        
        let report = UnsafeMutablePointer<UInt8>.allocate(capacity: Joystick.reportSize)
        
        let inputReportCallback: IOHIDReportCallback = { inContext, inResult, inSender, inType, reportId, report, reportLength in
            let this: Joystick = unsafeBitCast(inContext, to: Joystick.self)
            this.read(inResult, inSender: inSender!, reportType: inType, reportId: reportId, report: report, reportLength: reportLength)
        }
        
        let inputValueCallback: IOHIDValueCallback = { inContext, inResult, inSender, inValue in
            let element = IOHIDValueGetElement(inValue)
            let usage = IOHIDElementGetUsage(element)
            let intValue = IOHIDValueGetIntegerValue(inValue)
            
//            print("[Input Value] value: \(inValue)")
//            print("Element: \(element)")
//            print("Usage: \(usage)")
//            print("Int Value: \(intValue)")
            
            switch Int(usage) {
                case kHIDUsage_GD_X:
                    break
//                    print("[InputValueCallback] X axis value: \(intValue)")
                case kHIDUsage_GD_Y:
                    break
//                    print("[InputValueCallback] Y axis value: \(intValue)")
                case kHIDUsage_GD_Z:
                    print("[InputValueCallback] Z axis value: \(intValue)")
                case kHIDUsage_GD_Joystick:
                    print("[InputValueCallback] Joystick value: \(intValue)")
                case kHIDUsage_Game_Gun:
                    print("[InputValueCallback] GameGun value: \(intValue)")
                case kHIDUsage_GD_Qx:
                    print("[InputValueCallback] Qx value: \(intValue)")
                case kHIDUsage_GD_Qy:
                    print("[InputValueCallback] Qy value: \(intValue)")
                case kHIDUsage_GD_Qz:
                    print("[InputValueCallback] Qz value: \(intValue)")
                case kHIDUsage_GD_Qw:
                    print("[InputValueCallback] Qw value: \(intValue)")
                case kHIDUsage_GD_Rx:
                    print("[InputValueCallback] Rx value: \(intValue)")
                case kHIDUsage_GD_Ry:
                    print("[InputValueCallback] Ry value: \(intValue)")
                case kHIDUsage_GD_Rz:
                    print("[InputValueCallback] Rz value: \(intValue)")
                case kHIDUsage_GD_Vx:
                    print("[InputValueCallback] Vx value: \(intValue)")
                case kHIDUsage_GD_Vy:
                    print("[InputValueCallback] Vy value: \(intValue)")
                case kHIDUsage_GD_Vz:
                    print("[InputValueCallback] Vz value: \(intValue)")
                case kHIDUsage_GD_Vbrx:
                    print("[InputValueCallback] Vbrx value: \(intValue)")
                case kHIDUsage_GD_Vbry:
                    print("[InputValueCallback] Vbry value: \(intValue)")
                case kHIDUsage_GD_Vbrz:
                    print("[InputValueCallback] Vbrz value: \(intValue)")
                case kHIDUsage_Keypad0:
                    print("[InputValueCallback] Keypad0 value: \(intValue)")
                case kHIDUsage_Keyboard0:
                    print("[InputValueCallback] Keyboard0 value: \(intValue)")
                case kHIDUsage_GD_Mouse:
                    break
    //                print("[InputValueCallback] Mouse value: \(intValue)")
                case kHIDUsage_GD_Pointer:
                    break
    //                print("[InputValueCallback] Pointer value: \(intValue)")
                case kHIDUsage_GD_GamePad:
                    print("[InputValueCallback] GamePad value: \(intValue)")
                case kHIDUsage_GD_Keyboard:
                    print("[InputValueCallback] Keyboard value: \(intValue)")
                case kHIDUsage_GD_Keypad:
                    print("[InputValueCallback] Keypad value: \(intValue)")
                case kHIDUsage_GD_MultiAxisController:
                    print("[InputValueCallback] MultiAxisController value: \(intValue)")
                case kHIDUsage_GD_TabletPCSystemControls:
                    print("[InputValueCallback] TabletPCSystemControls value: \(intValue)")
                case kHIDUsage_GD_AssistiveControl:
                    print("[InputValueCallback] AssistiveControl value: \(intValue)")
                case kHIDUsage_GD_SystemMultiAxisController:
                    print("[InputValueCallback] SystemMultiAxisController value: \(intValue)")
                case kHIDUsage_GD_SpatialController:
                    print("[InputValueCallback] SpatialController value: \(intValue)")
                case kHIDUsage_GD_AssistiveControlCompatible:
                    print("[InputValueCallback] AssistiveControlCompatible value: \(intValue)")
                case kHIDUsage_GD_Slider:
                    print("[InputValueCallback] Slider value: \(intValue)")
                case kHIDUsage_GD_Dial:
                    print("[InputValueCallback] Dial value: \(intValue)")
                case kHIDUsage_GD_Wheel:
                    print("[InputValueCallback] Wheel value: \(intValue)")
                case kHIDUsage_GD_Hatswitch:
                    print("[InputValueCallback] Hat Switch value: \(intValue)")
                case kHIDUsage_GD_Select:
                    print("[InputValueCallback] Select value: \(intValue)")
                case kHIDUsage_GD_DPadUp:
                    print("[InputValueCallback] DPad UP value: \(intValue)")
                case kHIDUsage_GD_DPadDown:
                    print("[InputValueCallback] DPad DOWN value: \(intValue)")
                case kHIDUsage_GD_DPadLeft:
                    print("[InputValueCallback] DPad LEFT value: \(intValue)")
                case kHIDUsage_GD_DPadRight:
                    print("[InputValueCallback] DPad RIGHT value: \(intValue)")
                case kHIDUsage_Undefined:
                    print("[InputValueCallback] Usage Undefined value: \(intValue)")
                default:
//                    let _ = 0
                    print("[InputValueCallback] Unknown usage: \(usage), value: \(intValue)")
            }
        }
        
        let reportDescriptor: CFTypeRef = IOHIDDeviceGetProperty(inIOHIDDeviceRef, kIOHIDReportDescriptorKey as CFString)!
        print("[Hotas deviceAdded] Report Descriptor: \(reportDescriptor)")
        
        IOHIDDeviceRegisterInputReportCallback(inIOHIDDeviceRef,
                                               report,
                                               Joystick.reportSize,
                                               inputReportCallback,
                                               unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        
//        IOHIDDeviceRegisterInputValueCallback(inIOHIDDeviceRef,
//                                              inputValueCallback,
//                                              unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        
        
//        NotificationCenter.default.addObserver(forName: .HIDDeviceConnected,
//                                               object: nil,
//                                               queue: nil) { [weak self] notification in
//            print("Got notification for HID Device Connected")
//        }
    }
    
    func deviceRemoved(inIOHIDDeviceRef: IOHIDDevice!) {
        print("[Hotas deviceRemoved]")
        present = false
        joystickDevice = nil
        
//        NotificationCenter.default.addObserver(forName: .HIDDeviceDisconnected,
//                                               object: nil,
//                                               queue: nil) { [weak self] notification in
//            print("Got notification for HID Device Disconnected")
//        }
    }
    
    func getNormalizedAxisValue(rawIntValue: Int) -> Float {
        return Float(Float(rawIntValue) - Float(xyZero)) / Float(xyZero)
    }
    
    func read(_ inResult: IOReturn,
              inSender: UnsafeMutableRawPointer,
              reportType: IOHIDReportType,
              reportId: UInt32,
              report: UnsafeMutablePointer<UInt8>,
              reportLength: CFIndex) {
        let data = Data(bytes: UnsafePointer<UInt8>(report), count: reportLength)
        
        // TODO: Make sense of this data:
        // Looks like the first 4 bytes are button/hat data, bytes 5-12 are axis data
        if lastData != data {
            if data.count != lastData.count {
                print("Data count changed; length (in bytes): \(data.count)")
            }
            
            lastData = data
//            print("[Hotas read] data changed:")
//            print("Report length: \(reportLength)")
//            print("Report type: \(reportType)")
//            print("Report ID: \(reportId)")
            
//            print("Data string: \(lastData.hexEncodedString())")
//            print("Button Data: \(lastData.subdata(in: buttonDataRange).hexEncodedString())")
//            print("Axis Data: \(lastData.subdata(in: axisDataRange).hexEncodedString())")
        }
        
        if let elements = IOHIDDeviceCopyMatchingElements(joystickDevice!, nil, UInt32(kIOHIDOptionsTypeNone)) {
            let hidElements: [IOHIDElement] = elements as! [IOHIDElement]
//            if hidElements.count != hidElementUsages.count {
//                print("[Hotas read] Number of recorded HID element usages: \(hidElementUsages.count)")
//                print("[Hotas read] Number of elements: \(hidElements.count)")
//                print("HID Elements: \(hidElements)")
//            }
            
            var reportErrors = 0
            
            for elem in hidElements {
//                let elemType: IOHIDElementType = IOHIDElementGetType(elem)
//                print("[Hotas read] element type: \(elemType)")
                var valuePtr: UnsafeMutablePointer<Unmanaged<IOHIDValue>> = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
                let elemUsagePage: UInt32 = IOHIDElementGetUsagePage(elem)
                let elemUsage: UInt32 = IOHIDElementGetUsage(elem)
                let ioReturn: IOReturn = IOHIDDeviceGetValue(joystickDevice!, elem, valuePtr)
                
                if ioReturn == kIOReturnSuccess {
                    let intValue: Int = IOHIDValueGetIntegerValue(valuePtr.pointee.takeUnretainedValue())
                    
                    if let hidElemPage = hidElementPagesUsages[elemUsagePage] {
                        if let hidElemVal = hidElemPage[elemUsage] {
                            let isNoise = elemUsagePage == 255 && (elemUsage == 1 || elemUsage == 2)
//                            let isXYJoystick = elemUsagePage == 1 && (elemUsage == 48 || elemUsage == 49)
                            let isDesktopPage = elemUsagePage == kHIDPage_GenericDesktop
                            let isXYJoystick = isDesktopPage && (elemUsage == kHIDUsage_GD_X || elemUsage == kHIDUsage_GD_Y)
                            let isJoystickX = isDesktopPage && elemUsage == kHIDUsage_GD_X
                            let isJoystickY = isDesktopPage && elemUsage == kHIDUsage_GD_Y
                            let isButtonPage = elemUsagePage == kHIDPage_Button
                            let isRedButton = isButtonPage && elemUsage == kHIDUsage_Button_2
                            let isTriggerFirstDetent = isButtonPage && elemUsage == kHIDUsage_Button_1
                            let isTriggerSecondDetent = isButtonPage && elemUsage == kHIDUsage_Button_6
                            if hidElemVal != intValue && !isNoise {
                                print("HID Element changed, elem: \(elem), page: \(elemUsagePage), usage: \(elemUsage), value: \(intValue)")
                                
                                if !isXYJoystick {
                                    hidElementPagesUsages[elemUsagePage]![elemUsage] = intValue
                                    if isRedButton {
                                        print("PRESSED RED BUTTON")
                                        joystickDiscreteStateMapping[.RedButton] = intValue == 1
                                    }
                                    
                                    if isTriggerFirstDetent {
                                        print("TRIGGER FIRST DETENT")
                                        joystickDiscreteStateMapping[.TriggerSemi] = intValue == 1
                                    }
                                    
                                    if isTriggerSecondDetent {
                                        print("TRIGGER FULLY PRESSED")
                                        joystickDiscreteStateMapping[.TriggerFull] = intValue == 1
                                    }
                                }
                                
                                if isXYJoystick {
                                    let normalizedValue = getNormalizedAxisValue(rawIntValue: intValue)
                                    print("XY Joystick normalized value: \(normalizedValue)")
                                    if isJoystickX {
                                        joystickContinuousStateMapping[.JoystickX] = normalizedValue
                                    }
                                    
                                    if isJoystickY {
                                        joystickContinuousStateMapping[.JoystickY] = normalizedValue
                                    }
                                }
                                
                                hidElementPagesUsages[elemUsagePage]![elemUsage] = intValue
                            }
                        } else {
                            hidElementPagesUsages[elemUsagePage]![elemUsage] = intValue
                        }
                        
                    } else {
                        hidElementPagesUsages[elemUsagePage] = [:]
                        hidElementPagesUsages[elemUsagePage]![elemUsage] = intValue
                    }
                } else {
//                    print("ERROR :: Call to IOHIDDeviceGetValue failed!")
//                    print("ioReturn: \(ioReturn); Page: \(elemUsagePage); Usage: \(elemUsage)")
//                    print("Usage is kHIDUsage_GD_Joystick ? \(elemUsage == kHIDUsage_GD_Joystick)")
                    reportErrors += 1
                }
                
                if lastReportErrors != reportErrors {
                    print("ERRORS in call to IOHIDDeviceGetValue; number: \(reportErrors)")
                    lastReportErrors = reportErrors
                }
            }
        }
    }
}
