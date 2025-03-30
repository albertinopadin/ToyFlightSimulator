//
//  TFSThread.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/29/25.
//

import Foundation

class TFSThread: Thread {
    init(name: String, qos: QualityOfService) {
        super.init()
        self.name = name
        self.qualityOfService = qos
    }
}
