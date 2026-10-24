import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class TestContext {
    private(set) var failures: [String] = []

    func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if actual != expected {
            failures.append("\(label) at \(file):\(line): expected \(expected), got \(actual)")
        }
    }

    func expectTrue(_ condition: Bool, _ label: String = "", file: StaticString = #filePath, line: UInt = #line) {
        if !condition { failures.append("\(label) at \(file):\(line)") }
    }

    func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ label: String = "", file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try expression()
            failures.append("\(label) at \(file):\(line): expected an error")
        } catch { }
    }

    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        failures.append("\(message) at \(file):\(line)")
    }
}

struct TestCase {
    let name: String
    let body: (TestContext) async throws -> Void
}

final class TestRegistry {
    static let shared = TestRegistry()
    private var cases: [TestCase] = []
    private init() {}

    func add(_ name: String, body: @escaping (TestContext) async throws -> Void) {
        cases.append(TestCase(name: name, body: body))
    }

    func run(filter: String?) async -> Int {
        var failed = 0
        var ran = 0
        for testCase in cases {
            if let filter, !testCase.name.localizedCaseInsensitiveContains(filter) { continue }
            ran += 1
            let context = TestContext()
            do {
                try await testCase.body(context)
            } catch {
                context.fail("threw: \(error)")
            }
            if context.failures.isEmpty {
                print("PASS \(testCase.name)")
            } else {
                failed += 1
                print("FAIL \(testCase.name)")
                for failure in context.failures { print("  \(failure)") }
            }
        }
        print("SUMMARY ran=\(ran) failed=\(failed)")
        return failed
    }
}

func test(_ name: String, _ body: @escaping (TestContext) async throws -> Void) {
    TestRegistry.shared.add(name, body: body)
}
