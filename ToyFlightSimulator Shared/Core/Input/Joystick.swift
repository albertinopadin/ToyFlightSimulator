//
//  Hotas.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 6/6/23.
//  Heavily inspired by https://github.com/Arti3DPlayer/USBDeviceSwift

#if os(macOS)
import Foundation
import IOKit.hid

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

class Joystick: HIDDevice {
    let buttonDataRange = 0..<4
    let axisDataRange = 4..<12
    
    var joystickContinuousStateMapping: [JoystickContinuousState: Float] = [
        .JoystickX: 0.0,
        .JoystickY: 0.0
    ]
    
    var joystickDiscreteStateMapping: [JoystickDiscreteState: Bool] = [
        .RedButton: false,
        .TriggerSemi: false,
        .TriggerFull: false
    ]

    init() {
        super.init(name: ThrustmasterWarthog.joystickName,
                   vendorId: ThrustmasterWarthog.vendorId,
                   productId: ThrustmasterWarthog.joystickProductId)
    }
    
    override func read(_ inResult: IOReturn,
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
        
        if let elements = IOHIDDeviceCopyMatchingElements(hidDevice!, nil, UInt32(kIOHIDOptionsTypeNone)) {
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
                let ioReturn: IOReturn = IOHIDDeviceGetValue(hidDevice!, elem, valuePtr)
                
                if ioReturn == kIOReturnSuccess {
                    let elemValue = valuePtr.pointee.takeUnretainedValue()
                    let intValue: Int = IOHIDValueGetIntegerValue(elemValue)
                    let scaledValue: Double = IOHIDValueGetScaledValue(elemValue,
                                                                       UInt32(kIOHIDValueScaleTypeCalibrated))
                    
                    let hidElemLogicalMin: Int = IOHIDElementGetLogicalMin(elem)
                    let hidElemLogicalMax: Int = IOHIDElementGetLogicalMax(elem)
                    
                    // TODO: Get these values only once:
                    let hidElemPhysicalMin: Int = IOHIDElementGetPhysicalMin(elem)
                    let hidElemPhysicalMax: Int = IOHIDElementGetPhysicalMax(elem)
                    
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
                                print("[Joystick] HID Element changed, elem: \(elem), page: \(elemUsagePage), usage: \(elemUsage), value: \(intValue)")
                                
                                if !isXYJoystick {
                                    hidElementPagesUsages[elemUsagePage]![elemUsage] = intValue
                                    if isRedButton {
                                        print("PRESSED RED BUTTON")
                                        dQueue.sync {
                                            joystickDiscreteStateMapping[.RedButton] = intValue == 1
                                        }
                                    }
                                    
                                    if isTriggerFirstDetent {
                                        print("TRIGGER FIRST DETENT")
                                        dQueue.sync {
                                            joystickDiscreteStateMapping[.TriggerSemi] = intValue == 1
                                        }
                                    }
                                    
                                    if isTriggerSecondDetent {
                                        print("TRIGGER FULLY PRESSED")
                                        dQueue.sync {
                                            joystickDiscreteStateMapping[.TriggerFull] = intValue == 1
                                        }
                                    }
                                }
                                
                                if isXYJoystick {
                                    print("XY Joystick scaled value: \(scaledValue)")
                                    
                                    print("XY Joystick Logical MIN: \(hidElemLogicalMin)")
                                    print("XY Joystick Physical MIN: \(hidElemPhysicalMin)")
                                    print("XY Joystick Logical MAX: \(hidElemLogicalMax)")
                                    print("XY Joystick Physical MAX: \(hidElemPhysicalMax)")
                                    
                                    if isJoystickX {
                                        let normalizedValue = getNormalizedAxisValue(rawValue: intValue,
                                                                                     minPhysicalValue: hidElemPhysicalMin,
                                                                                     maxPhysicalValue: hidElemPhysicalMax,
                                                                                     axis: "x")
                                        print("X Joystick normalized value: \(normalizedValue)")
                                        dQueue.sync {
                                            joystickContinuousStateMapping[.JoystickX] = normalizedValue
                                        }
                                    }
                                    
                                    if isJoystickY {
                                        let normalizedValue = getNormalizedAxisValue(rawValue: intValue,
                                                                                     minPhysicalValue: hidElemPhysicalMin,
                                                                                     maxPhysicalValue: hidElemPhysicalMax)
                                        print("Y Joystick normalized value: \(normalizedValue)")
                                        dQueue.sync {
                                            joystickContinuousStateMapping[.JoystickY] = normalizedValue
                                        }
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
                    
//                    valuePtr.pointee.release()
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
#endif
