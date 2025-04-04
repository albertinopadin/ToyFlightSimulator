//
//  Throttle.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 6/24/23.
//
//  Heavily inspired by https://github.com/Arti3DPlayer/USBDeviceSwift

#if os(macOS)
import Foundation
import IOKit.hid

enum ThrottleContinuousState {
    case ThrottleLeft
    case ThrottleRight
}

enum ThrottleDiscreteState: CaseIterable {
    case RadarAltimeter
}

final class Throttle: HIDDevice, @unchecked Sendable {
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
        super.init(name: ThrustmasterWarthog.throttleName,
                   vendorId: ThrustmasterWarthog.vendorId,
                   productId: ThrustmasterWarthog.throttleProductId)
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
                let valuePtr: UnsafeMutablePointer<Unmanaged<IOHIDValue>> = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
                let elemUsagePage: UInt32 = IOHIDElementGetUsagePage(elem)
                let elemUsage: UInt32 = IOHIDElementGetUsage(elem)
                let ioReturn: IOReturn = IOHIDDeviceGetValue(hidDevice!, elem, valuePtr)
                
                if ioReturn == kIOReturnSuccess {
                    let elemValue = valuePtr.pointee.takeUnretainedValue()
                    let intValue: Int = IOHIDValueGetIntegerValue(elemValue)
//                    let scaledValue: Double = IOHIDValueGetScaledValue(elemValue,
//                                                                       UInt32(kIOHIDValueScaleTypeCalibrated))
                    
//                    let hidElemLogicalMin: Int = IOHIDElementGetLogicalMin(elem)
//                    let hidElemLogicalMax: Int = IOHIDElementGetLogicalMax(elem)
                    
                    // TODO: Get these values only once:
                    let hidElemPhysicalMin: Int = IOHIDElementGetPhysicalMin(elem)
                    let hidElemPhysicalMax: Int = IOHIDElementGetPhysicalMax(elem)
                    
                    dQueue.sync {
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
//                                                dQueue.sync {
//                                                    throttleContinuousStateMapping[.ThrottleRight] = throttleVal
//                                                }
                                            
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
                                    
                                    hidElementPagesUsages[elemUsagePage]![elemUsage] = intValue
                                }
                            } else {
                                hidElementPagesUsages[elemUsagePage]![elemUsage] = intValue
                            }
                            
                        } else {
                            hidElementPagesUsages[elemUsagePage] = [:]
                            hidElementPagesUsages[elemUsagePage]![elemUsage] = intValue
                        }
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
#endif
