import Foundation

/// A ~50-line test harness.
///
/// Not a preference — a constraint. This machine has Command Line Tools without
/// Xcode, where `XCTest` has no module and `_Testing_Foundation` ships an empty
/// one, so neither test framework can be imported. Rather than skip tests, the
/// runner is hand-rolled: same shape (suite / test / expect), same exit-code
/// contract, no dependencies. If Xcode is ever installed, moving these to
/// swift-testing is a mechanical rewrite of `expect` into `#expect`.
@MainActor
enum TestReport {
    static var passed = 0
    static var failures: [String] = []
    fileprivate static var currentSuite = ""
    fileprivate static var currentTest = ""
    fileprivate static var failedInCurrentTest = false
}

@MainActor
func suite(_ name: String, _ body: () -> Void) {
    TestReport.currentSuite = name
    print("\n\(name)")
    body()
}

@MainActor
func test(_ name: String, _ body: () -> Void) {
    TestReport.currentTest = name
    TestReport.failedInCurrentTest = false
    body()
    if TestReport.failedInCurrentTest {
        print("  ✘ \(name)")
    } else {
        TestReport.passed += 1
        print("  ✔ \(name)")
    }
}

@MainActor
func expect(_ condition: Bool, _ description: @autoclosure () -> String,
            file: StaticString = #fileID, line: UInt = #line) {
    guard !condition else { return }
    record("\(description())", file: file, line: line)
}

/// Preferred over `expect(a == b, …)` because it reports both values, which is the
/// difference between a useful failure and a rerun under a debugger.
@MainActor
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ description: @autoclosure () -> String = "",
                               file: StaticString = #fileID, line: UInt = #line) {
    guard actual != expected else { return }
    let note = description().isEmpty ? "" : " — \(description())"
    record("expected \(expected), got \(actual)\(note)", file: file, line: line)
}

@MainActor
func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 0.001,
                 _ description: @autoclosure () -> String = "",
                 file: StaticString = #fileID, line: UInt = #line) {
    guard abs(actual - expected) > tolerance else { return }
    let note = description().isEmpty ? "" : " — \(description())"
    record("expected \(expected) ± \(tolerance), got \(actual)\(note)", file: file, line: line)
}

@MainActor
private func record(_ message: String, file: StaticString, line: UInt) {
    TestReport.failedInCurrentTest = true
    TestReport.failures.append("\(TestReport.currentSuite) › \(TestReport.currentTest)\n      \(message)\n      at \(file):\(line)")
}

@MainActor
func reportAndExit() -> Never {
    print("\n" + String(repeating: "─", count: 56))
    if TestReport.failures.isEmpty {
        print("\(TestReport.passed) tests passed")
        exit(0)
    }
    print("\(TestReport.failures.count) failed, \(TestReport.passed) passed\n")
    for failure in TestReport.failures { print("  ✘ \(failure)") }
    exit(1)
}
