//
//  SingleSMMeshLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit

enum SingleSMMeshType {
    case F18_Sidewinder
    case F18_AIM120
    case F18_GBU16
    case F18_FuelTank
}

class SingleSMMeshLibrary: Library<SingleSMMeshType, SingleSMMesh> {
    private var _library: [SingleSMMeshType: SingleSMMesh] = [:]
    
    override func makeLibrary() {
        _library.updateValue(SingleSMMesh(modelName: "FA-18F", submeshName: "AIM-9XR_Paint"), forKey: .F18_Sidewinder)
        _library.updateValue(SingleSMMesh(modelName: "FA-18F", submeshName: "AIM-120DR_Paint"), forKey: .F18_AIM120)
        _library.updateValue(SingleSMMesh(modelName: "FA-18F", submeshName: "GBU-16R_Paint"), forKey: .F18_GBU16)
        _library.updateValue(SingleSMMesh(modelName: "FA-18F", submeshName: "TankCenter_Paint"), forKey: .F18_FuelTank)
    }
    
    override subscript(type: SingleSMMeshType) -> SingleSMMesh {
        return _library[type]!
    }
}

