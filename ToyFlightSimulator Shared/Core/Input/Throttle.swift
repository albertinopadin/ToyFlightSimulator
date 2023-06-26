//
//  Throttle.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 6/24/23.
//
//  Heavily inspired by https://github.com/Arti3DPlayer/USBDeviceSwift

import IOKit.hid
import Foundation


enum ThrottleContinuousState {
    case ThrottleLeft
    case ThrottleRight
}

enum ThrottleDiscreteState: CaseIterable {
    case RadarAltimeter
}

class Throttle: HIDDevice {
    static let VALUE_RANGE_MIN: Float = 0.0
    static let VALUE_RAGE_MAX: Float = 5.0
    
    var throttleContinuousStateMapping: [ThrottleContinuousState: Float] = [
        .ThrottleLeft: 0.0,
        .ThrottleRight: 0.0
    ]
    
    var joystickDiscreteStateMapping: [ThrottleDiscreteState: Bool] = [
        .RadarAltimeter: false,
    ]

    init() {
        super.init(vendorId: ThrustmasterWarthog.vendorId, productId: ThrustmasterWarthog.throttleProductId)
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
        }
        
        if let elements = IOHIDDeviceCopyMatchingElements(hidDevice!, nil, UInt32(kIOHIDOptionsTypeNone)) {
            let hidElements: [IOHIDElement] = elements as! [IOHIDElement]
            var reportErrors = 0
            
            for elem in hidElements {
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
                            let isDesktopPage = elemUsagePage == kHIDPage_GenericDesktop
                            let isButtonPage = elemUsagePage == kHIDPage_Button
                            let isUnknownPage = elemUsagePage == 255
                            if !isUnknownPage && hidElemVal != intValue {
                                print("[Throttle] HID Element changed, elem: \(elem), page: \(elemUsagePage), usage: \(elemUsage), value: \(intValue)")
                                
                                print("[Throttle] Is Desktop Page? \(isDesktopPage)")
                                print("[Throttle] Is Button Page? \(isButtonPage)")
                                
                                if isDesktopPage {
                                    print("[Throttle] Desktop Page; Usage:")
                                    switch Int(elemUsage) {
                                        case kHIDUsage_GD_X:
                                            print("GD_X")
                                        case kHIDUsage_GD_Y:
                                            print("GD_Y")
                                        case kHIDUsage_GD_Z:
                                            print("GD_Z")
                                            let rawThrottleVal = hidElemPhysicalMax - intValue
                                            let throttleVal = getRescaledAxisValue(rawValue: rawThrottleVal,
                                                                                   minPhysicalValue: hidElemPhysicalMin,
                                                                                   maxPhysicalValue: hidElemPhysicalMax,
                                                                                   minAxisValue: Throttle.VALUE_RANGE_MIN,
                                                                                   maxAxisValue: Throttle.VALUE_RAGE_MAX)
                                            throttleContinuousStateMapping[.ThrottleRight] = throttleVal
                                        case kHIDUsage_GD_Rx:
                                            print("GD_Rx")
                                        case kHIDUsage_GD_Ry:
                                            print("GD_Ry")
                                        case kHIDUsage_GD_Rz:
                                            print("GD_Rz")
                                        case kHIDUsage_GD_Slider:
                                            print("GD_Slider")
                                        case kHIDUsage_GD_Dial:
                                            print("GD_Dial")
                                        case kHIDUsage_GD_Wheel:
                                            print("GD_Wheel")
                                        case kHIDUsage_GD_Hatswitch:
                                            print("GD_Hatswitch")
                                        default:
                                            print("UKNOWN")
                                    }
                                }
                                
                                print("[Throttle] Usage Page:")
                                switch Int(elemUsagePage) {
                                    case kHIDPage_Undefined:
                                        print("UNDEFINED")
                                    case kHIDPage_GenericDesktop:
                                        print("GenericDesktop")
                                    case kHIDPage_Simulation:
                                        print("Simulation")
                                    case kHIDPage_VR:
                                        print("VR")
                                    case kHIDPage_Sport:
                                        print("Sport")
                                    case kHIDPage_Game:
                                        print("Game")
                                    case kHIDPage_GenericDeviceControls:
                                        print("GenericDeviceControls")
                                    case kHIDPage_KeyboardOrKeypad:
                                        print("KeyboardOrKeypad")
                                    case kHIDPage_LEDs:
                                        print("LEDs")
                                    case kHIDPage_Button:
                                        print("Button")
                                    case kHIDPage_Ordinal:
                                        print("Ordinal")
                                    case kHIDPage_Telephony:
                                        print("Telephony")
                                    case kHIDPage_Consumer:
                                        print("Consumer")
                                    case kHIDPage_Digitizer:
                                        print("Digitizer")
                                    case kHIDPage_Haptics:
                                        print("Haptics")
                                    case kHIDPage_PID:
                                        print("PID")
                                    case kHIDPage_Unicode:
                                        print("Unicode")
                                    case kHIDPage_AlphanumericDisplay:
                                        print("AlphanumericDisplay")
                                    case kHIDPage_Sensor:
                                        print("Sensor")
                                    case kHIDPage_Monitor:
                                        print("Monitor")
                                    case kHIDPage_MonitorEnumerated:
                                        print("MonitorEnumerated")
                                    case kHIDPage_MonitorVirtual:
                                        print("MonitorVirtual")
                                    case kHIDPage_MonitorReserved:
                                        print("MonitorReserved")
                                    case kHIDPage_PowerDevice:
                                        print("PowerDevice")
                                    case kHIDPage_BatterySystem:
                                        print("BatterySystem")
                                    case kHIDPage_PowerReserved:
                                        print("PowerReserved")
                                    case kHIDPage_PowerReserved2:
                                        print("PowerReserved2")
                                    case kHIDPage_BarCodeScanner:
                                        print("BarCodeScanner")
                                    case kHIDPage_WeighingDevice:
                                        print("WeighingDevice")
                                    case kHIDPage_Scale:
                                        print("Scale")
                                    case kHIDPage_MagneticStripeReader:
                                        print("MagneticStripeReader")
                                    case kHIDPage_CameraControl:
                                        print("CameraControl")
                                    case kHIDPage_Arcade:
                                        print("Arcade")
                                    case kHIDPage_FIDO:
                                        print("FIDO")
                                    case kHIDPage_VendorDefinedStart:
                                        print("VendorDefinedStart")
                                    default:
                                        print("[Throttle] UKNOWN usage page")
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

