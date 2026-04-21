//
//  MDLMaterialSemanticTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import ModelIO
@testable import ToyFlightSimulator

@Suite("MDLMaterialSemantic+Extensions", .tags(.utils))
struct MDLMaterialSemanticTests {

    @Test("allCases contains every semantic in the mapping")
    func allCasesCount() {
        // The extension enumerates 26 semantics.
        #expect(MDLMaterialSemantic.allCases.count == 26)
    }

    @Test("Every case in allCases maps to a non-UNKNOWN string")
    func everyCaseMapped() {
        for semantic in MDLMaterialSemantic.allCases {
            #expect(semantic.toString() != "UNKNOWN SEMANTIC",
                    "Semantic \(semantic) has no string mapping")
        }
    }

    @Test("toString returns stable, human-readable names for core semantics",
          arguments: [
            (semantic: MDLMaterialSemantic.baseColor, expected: "Base Color"),
            (semantic: MDLMaterialSemantic.metallic,  expected: "Metallic"),
            (semantic: MDLMaterialSemantic.roughness, expected: "Roughness"),
            (semantic: MDLMaterialSemantic.opacity,   expected: "Opacity"),
            (semantic: MDLMaterialSemantic.emission,  expected: "Emission"),
            (semantic: MDLMaterialSemantic.ambientOcclusion, expected: "Ambient Occlusion"),
            (semantic: MDLMaterialSemantic.tangentSpaceNormal, expected: "Tangent Space Normal"),
            (semantic: MDLMaterialSemantic.none,      expected: "None"),
          ])
    func coreSemantics(_ args: (semantic: MDLMaterialSemantic, expected: String)) {
        #expect(args.semantic.toString() == args.expected)
    }

    @Test("All mapped strings are distinct")
    func mappedStringsAreDistinct() {
        let strings = MDLMaterialSemantic.allCases.map { $0.toString() }
        let unique = Set(strings)
        #expect(strings.count == unique.count,
                "Duplicate toString() mappings: \(strings)")
    }
}
