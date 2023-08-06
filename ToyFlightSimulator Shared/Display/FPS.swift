//
//  FPS.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/5/23.
//

enum FPS: Int, CaseIterable, Identifiable {
    case FPS_30 = 30
    case FPS_60 = 60
    case FPS_120 = 120
    
    var id: Int { rawValue }
}
