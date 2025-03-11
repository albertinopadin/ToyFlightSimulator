//
//  GameStatsManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/5/24.
//

import Foundation

final class GameStatsManager: ObservableObject {
    static let sharedInstance = GameStatsManager()
    
    @Published public var rollingAverageFPS: Double = 0.0
    
    private let maxFrames = 60
    private var frame = 0
    private var lastXFrameDeltaTime = [Double]()
    
    private init() {}
    
    // TODO: Optimize this method using a true ring buffer (or better data structure)
    public func recordRenderDeltaTime(_ deltaTime: Double) {
        if lastXFrameDeltaTime.count >= maxFrames {
            lastXFrameDeltaTime.removeFirst()
        }
        
        lastXFrameDeltaTime.append(deltaTime)
        
        frame += 1
        
        if frame >= maxFrames {
            let avgDeltaTime: Double = lastXFrameDeltaTime.reduce(0.0) { $0 + $1 } / Double(maxFrames)
            DispatchQueue.main.async {
                self.rollingAverageFPS = 1 / avgDeltaTime
            }
            frame = 0
        }
    }
    
    // TODO:
//    public func threadInfo() {
//        Thread.isMultiThreaded()
//        ProcessInfo.processInfo.processName
//        ProcessInfo.processInfo.processIdentifier
//        ProcessInfo.processInfo.physicalMemory
//    }
    
    // From: https://developer.apple.com/forums/thread/105088
    private func rawMemoryFootprint() -> mach_vm_size_t? {
        // The `TASK_VM_INFO_COUNT` and `TASK_VM_INFO_REV1_COUNT` macros are too
        // complex for the Swift C importer, so we have to define them ourselves.
        let TASK_VM_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let TASK_VM_INFO_REV1_COUNT = mach_msg_type_number_t(MemoryLayout.offset(of: \task_vm_info_data_t.min_address)! / MemoryLayout<integer_t>.size)
        var info = task_vm_info_data_t()
        var count = TASK_VM_INFO_COUNT
        let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard
            kr == KERN_SUCCESS,
            count >= TASK_VM_INFO_REV1_COUNT
        else { return nil }
        return info.phys_footprint
    }
    
    public func memoryFootprint() -> String {
        guard let memFootprint = rawMemoryFootprint() else { return 0.formatted(.byteCount(style: .memory)) }
        return memFootprint.formatted(.byteCount(style: .memory))
    }
}
