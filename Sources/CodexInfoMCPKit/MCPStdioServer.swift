import Foundation

/// Reads one line of text at a time.
///
/// The reader returns `nil` when the input ends, so the server can stop
/// cleanly at the end of the stream.
public protocol LineReading: Sendable {
    /// The next line, or `nil` at the end of the input.
    func readLine() async -> String?
}

/// Writes one line of bytes at a time.
public protocol LineWriting: Sendable {
    /// Writes the bytes as one line.
    func writeLine(_ data: Data) async
}

/// The stdio loop of the MCP server.
///
/// The loop reads one JSON-RPC request per line, routes it through the router
/// and writes every answer as one line. A request without an answer — a
/// notification — stays silent, so the stream only carries protocol messages.
public struct MCPStdioServer: Sendable {
    private let router: MCPRouter

    /// Creates the server.
    ///
    /// - Parameter router: the router that answers the requests.
    public init(router: MCPRouter) {
        self.router = router
    }

    /// Answers the requests until the input ends.
    ///
    /// The loop returns when the reader reports the end of the input, so the
    /// executable can exit with a clean status.
    ///
    /// - Parameters:
    ///   - input: the source of the requests.
    ///   - output: the sink of the answers.
    public func run(input: any LineReading, output: any LineWriting) async {
        while let line = await input.readLine() {
            let responses = await router.handle(line: Data(line.utf8))
            for response in responses {
                await output.writeLine(response)
            }
        }
    }
}

/// Reads the lines of a file handle.
///
/// The read blocks until the handle has data, so the reader is used by the
/// server alone: no other work runs on that thread while it waits.
public actor FileHandleLineReader: LineReading {
    private let handle: FileHandle
    private var buffer = Data()

    /// Creates the reader.
    ///
    /// - Parameter handle: the handle the lines are read from.
    public init(handle: FileHandle = .standardInput) {
        self.handle = handle
    }

    public func readLine() async -> String? {
        while true {
            if let index = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<index])
                buffer = Data(buffer[buffer.index(after: index)...])
                return String(data: line, encoding: .utf8)
            }
            let chunk = handle.availableData
            // An empty chunk means the end of the file.
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}

/// Writes the lines to a file handle.
///
/// The bytes and the line break are written in one call, so two answers can
/// never be mixed.
public struct FileHandleLineWriter: LineWriting {
    private let handle: FileHandle

    /// Creates the writer.
    ///
    /// - Parameter handle: the handle the lines are written to.
    public init(handle: FileHandle = .standardOutput) {
        self.handle = handle
    }

    public func writeLine(_ data: Data) async {
        var payload = data
        payload.append(0x0A)
        handle.write(payload)
    }
}
