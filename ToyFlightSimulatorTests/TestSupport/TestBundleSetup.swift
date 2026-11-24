//
//  TestBundleSetup.swift
//  ToyFlightSimulatorTests
//

import Foundation

/// The test bundle's principal class. XCTest creates one instance of it when it loads the test
/// bundle, before any test runs. The bundle's Info.plist names it under `NSPrincipalClass`; the
/// test target's `INFOPLIST_KEY_NSPrincipalClass` build setting writes that entry.
///
/// Its one job is to limit Swift Testing to one test at a time. When Swift Testing runs tests in
/// parallel inside the host app, the suite deadlocks (see "Testing" in CLAUDE.md). The limit is
/// set here, inside the process, because Xcode does not pass a test plan's environment variables
/// to the host app when it launches a test run from the IDE (measured 2026-11-24).
///
/// `@objc(TFSTestBundleSetup)` fixes the Objective-C class name, so the Info.plist entry does not
/// depend on the Swift module name.
@objc(TFSTestBundleSetup)
final class TestBundleSetup: NSObject {
    /// The environment variable Swift Testing reads for the largest number of tests it may run at
    /// the same time. It is experimental by name, so a later toolchain may rename or drop it.
    static let maximumParallelizationWidthVariableName = "SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH"

    /// The value written to that variable: one test at a time.
    static let maximumParallelizationWidthVariableValue = "1"

    override init() {
        super.init()
        let variableName = Self.maximumParallelizationWidthVariableName
        let valueFromLauncher = Self.currentValue(ofEnvironmentVariable: variableName)

        // The last argument 0 means "do not replace an existing value", so a run can still choose
        // another width on purpose, for example
        // `TEST_RUNNER_SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=4 xcodebuild test ...`.
        setenv(variableName, Self.maximumParallelizationWidthVariableValue, 0)

        let valueNow = Self.currentValue(ofEnvironmentVariable: variableName)
        print("[TestBundleSetup] \(variableName): from launcher = \(valueFromLauncher ?? "unset"), now = \(valueNow ?? "unset")")
    }

    private static func currentValue(ofEnvironmentVariable variableName: String) -> String? {
        guard let valuePointer = getenv(variableName) else { return nil }
        return String(cString: valuePointer)
    }
}
