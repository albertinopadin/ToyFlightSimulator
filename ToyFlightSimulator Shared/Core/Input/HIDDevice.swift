//
//  HIDManager.swift
//  ToyFlightSimulator macOS
//
//  Created by Albertino Padin on 6/24/23.
//
//  Heavily inspired by https://github.com/Arti3DPlayer/USBDeviceSwift

#if os(macOS)
import IOKit.hid

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

class HIDDevice {
    static let reportSize: Int = 64
    
    let name: String
    let vendorId: Int
    let productId: Int
    
    var hidDevice: IOHIDDevice?
    var present: Bool = false
    
    let dQueue: DispatchQueue
    
    var hidElementPagesUsages: [UInt32: [UInt32: Int]] = [:]
    
    var lastData = Data()
    var lastReportErrors = 0

    init(name: String, vendorId: Int, productId: Int) {
        self.name = name
        self.vendorId = vendorId
        self.productId = productId
        let dQueueName = "\(name.lowercased().replacingOccurrences(of: " ", with: "_"))_dispatch_queue"
        self.dQueue = DispatchQueue(label: dQueueName)
        let thread = Thread(target: self, selector: #selector(self.run), object: nil)
        thread.start()
    }
    
    @objc func run() {
        let managerRef = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchingDict: NSMutableDictionary = [kIOHIDVendorIDKey: NSNumber(value: self.vendorId),
                                                kIOHIDProductIDKey: NSNumber(value: self.productId)]


        IOHIDManagerSetDeviceMatching(managerRef, matchingDict)
        IOHIDManagerScheduleWithRunLoop(managerRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(managerRef, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let deviceMatchingCallback: IOHIDDeviceCallback = { inContext, inResult, inSender, inDeviceRef in
            print("[deviceMatchingCallback]")
            print("inContext: \(inContext), inResult: \(inResult), inSender: \(inSender), device ref: \(inDeviceRef)")
            let this: HIDDevice = unsafeBitCast(inContext, to: HIDDevice.self)
            this.deviceAdded(inResult, inSender: inSender!, inIOHIDDeviceRef: inDeviceRef)
        }

        let deviceRemovalCallback: IOHIDDeviceCallback = { inContext, inResult, inSender, inDeviceRef in
            let this: HIDDevice = unsafeBitCast(inContext, to: HIDDevice.self)
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
        hidDevice = inIOHIDDeviceRef
        present = true
        
        let report = UnsafeMutablePointer<UInt8>.allocate(capacity: HIDDevice.reportSize)
        
        let inputReportCallback: IOHIDReportCallback = { inContext, inResult, inSender, inType, reportId, report, reportLength in
            let this: HIDDevice = unsafeBitCast(inContext, to: HIDDevice.self)
            this.read(inResult,
                      inSender: inSender!,
                      reportType: inType,
                      reportId: reportId,
                      report: report,
                      reportLength: reportLength)
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
        print("[HIDDevice deviceAdded] Report Descriptor: \(reportDescriptor)")
        
        IOHIDDeviceRegisterInputReportCallback(inIOHIDDeviceRef,
                                               report,
                                               HIDDevice.reportSize,
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
        print("[HIDDevice deviceRemoved]")
        hidDevice = nil
        present = false
        
//        NotificationCenter.default.addObserver(forName: .HIDDeviceDisconnected,
//                                               object: nil,
//                                               queue: nil) { [weak self] notification in
//            print("Got notification for HID Device Disconnected")
//        }
    }
    
    func getNormalizedAxisValue(rawValue: Int, minPhysicalValue: Int, maxPhysicalValue: Int, axis: String = "") -> Float {
        let zeroVal: Float = (Float(maxPhysicalValue - 1) / 2.0) + (Float(minPhysicalValue) / 2.0)
        var correction: Int = 0
        if axis == "x" {
            correction = 600
        }
        let normalizedValue = Float(Float(rawValue + correction) - zeroVal) / zeroVal
        if abs(normalizedValue) < 1e-2 {
            return 0.0
        } else {
            return normalizedValue
        }
    }
    
    func getRescaledAxisValue(rawValue: Int,
                              minPhysicalValue: Int,
                              maxPhysicalValue: Int,
                              minAxisValue: Float = 0.0,
                              maxAxisValue: Float = 1.0) -> Float {
        let range: Float = Float(maxPhysicalValue - minPhysicalValue)
        let scaledValue = (Float(rawValue - minPhysicalValue) / range) * maxAxisValue
        if abs(scaledValue) < 1e-2 {
            return 0.0
        } else {
            return scaledValue
        }
    }
    
    func read(_ inResult: IOReturn,
              inSender: UnsafeMutableRawPointer,
              reportType: IOHIDReportType,
              reportId: UInt32,
              report: UnsafeMutablePointer<UInt8>,
              reportLength: CFIndex) {
        // Override this function
        if let elements = IOHIDDeviceCopyMatchingElements(hidDevice!, nil, UInt32(kIOHIDOptionsTypeNone)) {
            let hidElements: [IOHIDElement] = elements as! [IOHIDElement]
            
            for elem in hidElements {
                let elemUsagePage: UInt32 = IOHIDElementGetUsagePage(elem)
                
                print("[\(name)] Usage Page:")
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
            }
        }
    }
}
#endif
