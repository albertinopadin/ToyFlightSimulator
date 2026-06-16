//
//  AircraftType.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 6/15/26.
//

enum AircraftType: String, CaseIterable, Identifiable {
    case f16            = "F-16 Fighting Falcon"
    case f18            = "F/A-18 Hornet"
    case f22            = "F/A-22 Raptor"
    case f22_cgtrader   = "CGTrader F/A-22 Raptor"
    case f35            = "F/A-35 Lightning II"
    
    var id: String { rawValue }
}
