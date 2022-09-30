//
//  Library.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

class Library<T, K> {
    init() {
        makeLibrary()
    }
    
    func makeLibrary() {
        // Override this function when filling the library with default values
    }
    
    subscript(_ type: T) -> K? {
        return nil
    }
}
