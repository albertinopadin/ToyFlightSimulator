//
//  inspect_mdl_materials.swift
//  ToyFlightSimulator
//
//  Prints what Model I/O actually produces for a model's materials: every MDLMaterialProperty
//  (semantic, name, type, value), whether each one is the scattering function's own default
//  object or was added by the importer, and two diagnostics that mirror the engine's import
//  rules in ToyFlightSimulator Shared/AssetPipeline/Material.swift:
//    - the base color `Material.populateMaterial` ends up with today (the LAST .baseColor
//      value in `properties(with:)` order wins) against the FIRST .baseColor property
//      (`MDLMaterial.property(with:)`), flagged MISMATCH when they differ: this is the
//      untextured-USD-material-turns-gray defect;
//    - per-channel mean and maximum of every emission texture, to see whether an emission
//      term would light anything up.
//
//  What this script established (2026-09-21, macOS 27 SDK), written up in
//  research/claude/modelio_material_semantics_blinn_phong_2026-09-21.md:
//    - the OBJ importer stores the MTL `Ka` line (ambient reflectivity) under .emission and
//      drops `Ke`, `Tr` and `illum`; `Ks` -> .specular (float3), `Ns` -> .specularExponent,
//      `d` -> .opacity, `Kd` + `map_Kd` merge into ONE .baseColor property;
//    - every OBJ material also gets PBR defaults that are not in the file (roughness 0.9,
//      ao 0.0, sheen 0.05, a scalar specular 0 when Ks is absent);
//    - the USD importer lists the authored UsdPreviewSurface inputs (diffuseColor,
//      emissiveColor, occlusion) BEFORE Model I/O's defaults with the same semantic in
//      `properties(with:)`, while by-index enumeration lists the defaults first.
//
//  Usage (run from anywhere; --repo-models resolves relative to this file):
//      swift scripts/inspect_mdl_materials.swift [--all] [--synthetic] [--repo-models] [<model path> ...]
//        --all          print every property, including Model I/O's untouched PBR defaults
//        --synthetic    write a throwaway OBJ + MTL carrying every standard MTL key into the
//                       temporary directory and inspect it (how the mapping table was measured)
//        --repo-models  inspect every .obj / .usdz / .usdc under Core/Resources/Models
//

import Foundation
import ModelIO
import simd

// MARK: - Options

var showAllProperties = false
var inspectSynthetic = false
var inspectRepoModels = false
var modelPaths: [String] = []

for argument in CommandLine.arguments.dropFirst() {
    switch argument {
    case "--all":         showAllProperties = true
    case "--synthetic":   inspectSynthetic = true
    case "--repo-models": inspectRepoModels = true
    default:              modelPaths.append(argument)
    }
}

if !inspectSynthetic && !inspectRepoModels && modelPaths.isEmpty {
    fputs("Usage: swift scripts/inspect_mdl_materials.swift [--all] [--synthetic] [--repo-models] [<model path> ...]\n",
          stderr)
    exit(1)
}

// MARK: - Names for the Model I/O enums

let semanticNames: [MDLMaterialSemantic: String] = [
    .baseColor: "baseColor", .subsurface: "subsurface", .metallic: "metallic", .specular: "specular",
    .specularExponent: "specularExponent", .specularTint: "specularTint", .roughness: "roughness",
    .anisotropic: "anisotropic", .anisotropicRotation: "anisotropicRotation", .sheen: "sheen",
    .sheenTint: "sheenTint", .clearcoat: "clearcoat", .clearcoatGloss: "clearcoatGloss",
    .emission: "emission", .bump: "bump", .opacity: "opacity",
    .interfaceIndexOfRefraction: "interfaceIndexOfRefraction",
    .materialIndexOfRefraction: "materialIndexOfRefraction",
    .objectSpaceNormal: "objectSpaceNormal", .tangentSpaceNormal: "tangentSpaceNormal",
    .displacement: "displacement", .displacementScale: "displacementScale",
    .ambientOcclusion: "ambientOcclusion", .ambientOcclusionScale: "ambientOcclusionScale",
    .none: "none", .userDefined: "userDefined",
]

let typeNames: [MDLMaterialPropertyType: String] = [
    .none: "none", .string: "string", .URL: "URL", .texture: "texture", .color: "color",
    .float: "float", .float2: "float2", .float3: "float3", .float4: "float4",
    .matrix44: "matrix44", .buffer: "buffer",
]

/// Semantics Material.swift reads today or is expected to read. The rest are Model I/O's
/// untouched PBR defaults and are hidden unless --all is given.
let semanticsShownByDefault: Set<MDLMaterialSemantic> = [
    .baseColor, .emission, .specular, .specularExponent, .opacity, .roughness, .metallic,
    .ambientOcclusion, .tangentSpaceNormal, .objectSpaceNormal, .materialIndexOfRefraction,
    .displacement, .none, .userDefined,
]

// MARK: - Formatting

func formatScalar(_ value: Float) -> String {
    return String(format: "%.4g", value)
}

func formatVector(_ values: [Float]) -> String {
    return "(" + values.map(formatScalar).joined(separator: ", ") + ")"
}

func describeValue(of property: MDLMaterialProperty) -> String {
    switch property.type {
    case .string:
        return "\"\(property.stringValue ?? "")\""
    case .URL:
        return "URL \(property.urlValue?.lastPathComponent ?? "nil")"
    case .texture:
        guard let texture = property.textureSamplerValue?.texture else { return "texture <nil>" }
        return "texture \(texture.dimensions.x)x\(texture.dimensions.y) \(texture.channelCount)ch"
    case .color:
        guard let color = property.color, let components = color.components else { return "color <nil>" }
        let colorSpace = color.colorSpace?.name.map { String($0) } ?? "no colorspace"
        return "color \(formatVector(components.map { Float($0) })) \(colorSpace)"
    case .float:
        return formatScalar(property.floatValue)
    case .float2:
        let value = property.float2Value
        return formatVector([value.x, value.y])
    case .float3:
        let value = property.float3Value
        return formatVector([value.x, value.y, value.z])
    case .float4:
        let value = property.float4Value
        return formatVector([value.x, value.y, value.z, value.w])
    case .matrix44:
        return "matrix4x4"
    case .buffer:
        return "buffer"
    case .none:
        return "<none>"
    @unknown default:
        return "<unknown type \(property.type.rawValue)>"
    }
}

// MARK: - Scattering-function default objects

/// Model I/O creates these property objects for every material. The OBJ importer fills them in
/// place (so they are the only property per semantic and carry the file's Kd / Ka / Ks); the USD
/// importer leaves them at their defaults and adds the authored UsdPreviewSurface inputs as
/// separate properties.
func scatteringFunctionProperties(of material: MDLMaterial) -> [MDLMaterialProperty] {
    let scattering = material.scatteringFunction
    var properties: [MDLMaterialProperty] = [
        scattering.baseColor, scattering.emission, scattering.specular,
        scattering.materialIndexOfRefraction, scattering.interfaceIndexOfRefraction,
        scattering.normal, scattering.ambientOcclusion, scattering.ambientOcclusionScale,
    ]
    if let physicallyPlausible = scattering as? MDLPhysicallyPlausibleScatteringFunction {
        properties += [
            physicallyPlausible.subsurface, physicallyPlausible.metallic,
            physicallyPlausible.specularAmount, physicallyPlausible.specularTint,
            physicallyPlausible.roughness, physicallyPlausible.anisotropic,
            physicallyPlausible.anisotropicRotation, physicallyPlausible.sheen,
            physicallyPlausible.sheenTint, physicallyPlausible.clearcoat,
            physicallyPlausible.clearcoatGloss,
        ]
    }
    return properties
}

// MARK: - Engine-rule diagnostics (mirror Material.swift; keep in sync when it changes)

/// A .color / .float3 / .float4 property as the float4 `Material.setBaseColor` stores it.
func baseColorValue(of property: MDLMaterialProperty) -> SIMD4<Float>? {
    switch property.type {
    case .float3:
        let value = property.float3Value
        return SIMD4(value.x, value.y, value.z, 1)
    case .float4:
        return property.float4Value
    case .color:
        guard let components = property.color?.components, components.count >= 3 else { return nil }
        let alpha: Float = components.count > 3 ? Float(components[3]) : 1
        return SIMD4(Float(components[0]), Float(components[1]), Float(components[2]), alpha)
    default:
        return nil
    }
}

/// What `Material.populateMaterial` computes today: it visits every .baseColor property in
/// `properties(with:)` order and each value overwrites the previous one, so the LAST one wins.
func lastWinsBaseColor(of material: MDLMaterial) -> SIMD4<Float>? {
    var color: SIMD4<Float>? = nil
    for property in material.properties(with: .baseColor) {
        if let value = baseColorValue(of: property) {
            color = value
        }
    }
    return color
}

/// Per-channel mean and maximum of an 8-bit texture, on a 0...255 scale.
func textureStatistics(_ texture: MDLTexture) -> String {
    let width = Int(texture.dimensions.x)
    let height = Int(texture.dimensions.y)
    let channels = Int(texture.channelCount)
    guard texture.channelEncoding == .uInt8 else {
        return "channel encoding \(texture.channelEncoding.rawValue) not sampled"
    }
    guard let data = texture.texelDataWithTopLeftOrigin(), channels > 0,
          data.count >= width * height * channels else {
        return "texel data unavailable"
    }
    var sums = [Double](repeating: 0, count: channels)
    var maxima = [UInt8](repeating: 0, count: channels)
    data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
        for texelStart in stride(from: 0, to: width * height * channels, by: channels) {
            for channel in 0..<channels {
                let value = buffer[texelStart + channel]
                sums[channel] += Double(value)
                maxima[channel] = max(maxima[channel], value)
            }
        }
    }
    let texelCount = Double(width * height)
    let means = sums.map { String(format: "%.1f", $0 / texelCount) }.joined(separator: ", ")
    let maximaText = maxima.map(String.init).joined(separator: ", ")
    return "mean (\(means)) max (\(maximaText)) on a 0...255 scale"
}

// MARK: - Inspection

func describe(_ material: MDLMaterial) {
    let defaultObjects = scatteringFunctionProperties(of: material)
    let scatteringName = String(describing: type(of: material.scatteringFunction))
    print("  material \"\(material.name)\": \(scatteringName), \(material.count) properties")

    for index in 0..<material.count {
        guard let property = material[index] else { continue }
        if !showAllProperties && !semanticsShownByDefault.contains(property.semantic) { continue }
        let semantic = semanticNames[property.semantic] ?? "semantic \(property.semantic.rawValue)"
        let type = typeNames[property.type] ?? "type \(property.type.rawValue)"
        let origin = defaultObjects.contains { $0 === property } ? "scattering-function object" : "importer-added"
        let paddedSemantic = ("." + semantic).padding(toLength: 28, withPad: " ", startingAt: 0)
        print("    \(paddedSemantic) \"\(property.name)\" \(type) = \(describeValue(of: property))  [\(origin)]")
    }

    // Diagnostic 1: the base color the engine ends up with vs the first .baseColor property.
    let firstBaseColor = material.property(with: .baseColor)
    let firstValue = firstBaseColor.flatMap(baseColorValue)
    if let lastWins = lastWinsBaseColor(of: material) {
        let firstText: String
        if let firstValue {
            firstText = formatVector([firstValue.x, firstValue.y, firstValue.z, firstValue.w])
        } else if let firstBaseColor {
            firstText = "\(typeNames[firstBaseColor.type] ?? "?") \"\(firstBaseColor.name)\""
        } else {
            firstText = "none"
        }
        let lastText = formatVector([lastWins.x, lastWins.y, lastWins.z, lastWins.w])
        var line = "    engine base color today (last .baseColor value wins): \(lastText); first .baseColor: \(firstText)"
        if let firstValue, firstValue != lastWins {
            line += "   <-- MISMATCH: Material.populateMaterial overwrites the authored value"
        }
        print(line)
    }

    // Diagnostic 2: would an emission term light anything up?
    for property in material.properties(with: .emission) {
        if property.type == .texture, let texture = property.textureSamplerValue?.texture {
            print("    emission texture \"\(property.name)\": \(textureStatistics(texture))")
        }
    }
}

func inspect(modelAt path: String) {
    let url = URL(fileURLWithPath: path)
    print("\n===== \(url.lastPathComponent)  [\(url.deletingLastPathComponent().path)]")
    guard FileManager.default.fileExists(atPath: url.path) else {
        print("  file not found")
        return
    }
    let asset = MDLAsset(url: url)
    asset.loadTextures()   // string / URL properties become .texture, as Model.init does before Material reads them

    var seenMaterialNames = Set<String>()
    let meshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
    for mesh in meshes {
        for submesh in (mesh.submeshes as? [MDLSubmesh]) ?? [] {
            guard let material = submesh.material else {
                print("  submesh \"\(submesh.name)\": no material")
                continue
            }
            guard seenMaterialNames.insert(material.name).inserted else { continue }
            describe(material)
        }
    }
    print("  \(seenMaterialNames.count) distinct material(s) over \(meshes.count) mesh(es)")
}

// MARK: - Synthetic MTL carrying every standard key

/// Values are distinct so the output shows which MTL key landed in which Model I/O semantic.
/// The map files do not exist, so those properties stay `string` typed ("would be a texture").
let syntheticMTL = """
newmtl all_keys_with_maps
Ka 0.11 0.12 0.13
Kd 0.21 0.22 0.23
Ks 0.31 0.32 0.33
Ke 0.41 0.42 0.43
Ns 96.5
Ni 1.45
d 0.75
illum 2
map_Ka ka.png
map_Kd kd.png
map_Ks ks.png
map_Ns ns.png
map_d d.png
map_bump bump.png
bump bump2.png
disp disp.png

newmtl ka_and_ke_scalars
Ka 0.11 0.12 0.13
Kd 0.21 0.22 0.23
Ks 0.31 0.32 0.33
Ke 0.41 0.42 0.43
Ns 96.5
d 0.75

newmtl ke_only
Kd 0.21 0.22 0.23
Ke 0.41 0.42 0.43
Ns 0

newmtl tr_only
Kd 0.21 0.22 0.23
Tr 0.25

newmtl d_and_tr
Kd 0.21 0.22 0.23
d 0.75
Tr 0.25

newmtl kd_and_map_kd
Kd 0.21 0.22 0.23
Ks 0.31 0.32 0.33
map_Kd kd.png
map_Ke ke.png

newmtl illum_1
Ka 0.11 0.12 0.13
Kd 0.21 0.22 0.23
Ks 0.31 0.32 0.33
Ns 96.5
illum 1

"""

let syntheticMaterialNames = [
    "all_keys_with_maps", "ka_and_ke_scalars", "ke_only", "tr_only", "d_and_tr", "kd_and_map_kd", "illum_1",
]

func writeSyntheticModel() -> String {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tfs_mdl_material_probe", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    // One triangle per material (rotated vertex order per face) so each becomes its own submesh.
    var obj = "mtllib probe.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nvn 0 0 1\nvt 0 0\nvt 1 0\nvt 0 1\n"
    let corners = ["1/1/1", "2/2/1", "3/3/1"]
    for (index, name) in syntheticMaterialNames.enumerated() {
        let rotated = (0..<3).map { corners[($0 + index) % 3] }
        obj += "usemtl \(name)\nf \(rotated.joined(separator: " "))\n"
    }
    let objURL = directory.appendingPathComponent("probe.obj")
    let mtlURL = directory.appendingPathComponent("probe.mtl")
    try! obj.write(to: objURL, atomically: true, encoding: .utf8)
    try! syntheticMTL.write(to: mtlURL, atomically: true, encoding: .utf8)
    return objURL.path
}

// MARK: - Repo models

func repoModelPaths() -> [String] {
    let scriptsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let modelsDirectory = scriptsDirectory
        .deletingLastPathComponent()
        .appendingPathComponent("ToyFlightSimulator Shared/Core/Resources/Models", isDirectory: true)
    guard let enumerator = FileManager.default.enumerator(at: modelsDirectory, includingPropertiesForKeys: nil) else {
        return []
    }
    let modelExtensions: Set<String> = ["obj", "usdz", "usdc", "usda", "usd"]
    var paths: [String] = []
    for case let fileURL as URL in enumerator where modelExtensions.contains(fileURL.pathExtension.lowercased()) {
        paths.append(fileURL.path)
    }
    return paths.sorted()
}

// MARK: - Main

if inspectSynthetic {
    let path = writeSyntheticModel()
    print("Synthetic OBJ + MTL written to \(path)")
    inspect(modelAt: path)
}
if inspectRepoModels {
    modelPaths += repoModelPaths()
}
for path in modelPaths {
    inspect(modelAt: path)
}
