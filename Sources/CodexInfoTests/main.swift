import Foundation

registerCoreTests()

let arguments = CommandLine.arguments
let filter: String?
if let argument = arguments.first(where: { $0.hasPrefix("--filter=") }) {
    filter = String(argument.dropFirst("--filter=".count))
} else if let index = arguments.firstIndex(of: "--filter"), arguments.indices.contains(index + 1) {
    filter = arguments[index + 1]
} else {
    filter = nil
}
let failures = await TestRegistry.shared.run(filter: filter)
exit(failures == 0 ? 0 : 1)
