//
//  ModelAssetLoadFailureTests.swift
//  ToyFlightSimulatorTests
//

import Testing
@testable import ToyFlightSimulator

/// `Model.NoMeshesFailureMessage`: the message `Model.init` stops with when a model file
/// yields no meshes. Pure string building, so no Metal and no Model construction.
///
/// The tests pin what the message must let the reader do (find the file, see its size,
/// tell an empty bundled copy from unreadable content), not its exact wording.
@Suite("Model asset load failure message", .tags(.assetPipeline))
struct ModelAssetLoadFailureTests {

    static let bundledModelFilePath = "/Applications/ToyFlightSimulator.app/Contents/Resources/cgtrader_F22.usdz"

    @Test("an empty file is reported as empty, with the evicted-placeholder remedy")
    func emptyFileNamesEvictedPlaceholder() {
        let message = Model.NoMeshesFailureMessage(modelName: "cgtrader_F22",
                                                   assetFilePath: Self.bundledModelFilePath,
                                                   assetFileByteCount: 0)
        #expect(message.contains("cgtrader_F22: no meshes loaded"))
        #expect(message.contains(Self.bundledModelFilePath))
        #expect(message.contains("(0 bytes)"))
        #expect(message.contains("iCloud"))
        #expect(message.contains("Clean Build Folder"))
    }

    @Test("a file with content is blamed on its content, not on iCloud")
    func fileWithContentBlamesContent() {
        // 6,498,118 bytes is the intact cgtrader_F22.usdz.
        let message = Model.NoMeshesFailureMessage(modelName: "cgtrader_F22",
                                                   assetFilePath: Self.bundledModelFilePath,
                                                   assetFileByteCount: 6_498_118)
        #expect(message.contains(Self.bundledModelFilePath))
        #expect(message.contains("(6498118 bytes)"))
        #expect(message.contains("valid model file"))
        #expect(!message.contains("iCloud"))
    }

    @Test("an unknown path and size still name the model and guess no cause")
    func unknownFileStillNamesModel() {
        let message = Model.NoMeshesFailureMessage(modelName: "Temple",
                                                   assetFilePath: nil,
                                                   assetFileByteCount: nil)
        #expect(message.contains("Temple: no meshes loaded"))
        #expect(message.contains("unknown file path"))
        #expect(message.contains("file size unavailable"))
        #expect(!message.contains("iCloud"))
        #expect(!message.contains("valid model file"))
    }
}
