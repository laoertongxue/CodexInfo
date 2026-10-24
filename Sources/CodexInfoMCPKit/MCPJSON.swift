import Foundation

/// The JSON-RPC 2.0 messages of the MCP server.
///
/// The router never touches the standard streams; it returns the bytes of the
/// answers and lets the host decide where to write them.
public enum MCPJSON {
    /// The JSON-RPC version every message carries.
    public static let jsonRPCVersion = "2.0"

    /// The object form of an encodable value.
    ///
    /// Dates become ISO-8601 strings, so the payload matches the document the
    /// panel reads in the native host.
    public static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// A successful answer.
    public static func response(id: Any?, result: [String: Any]) -> Data {
        let object: [String: Any] = [
            "jsonrpc": jsonRPCVersion,
            "id": id ?? NSNull(),
            "result": result,
        ]
        return data(object)
    }

    /// A failed answer.
    public static func error(id: Any?, code: Int, message: String) -> Data {
        let object: [String: Any] = [
            "jsonrpc": jsonRPCVersion,
            "id": id ?? NSNull(),
            "error": ["code": code, "message": message],
        ]
        return data(object)
    }

    /// The answer of a tool that failed.
    ///
    /// A failing tool is a normal outcome of the protocol, so the error is
    /// reported inside the result instead of as a protocol error.
    public static func toolError(id: Any?, message: String) -> Data {
        toolResult(id: id, text: message, structured: nil, isError: true)
    }

    /// The answer of a tool that succeeded.
    public static func toolResult(id: Any?, text: String, structured: [String: Any]?) -> Data {
        toolResult(id: id, text: text, structured: structured, isError: false)
    }

    /// A tool answer with its readable line and its structured payload.
    public static func toolResult(id: Any?, text: String, structured: [String: Any]?, isError: Bool) -> Data {
        var result: [String: Any] = [
            "content": [["type": "text", "text": text]],
            "isError": isError,
        ]
        if let structured {
            result["structuredContent"] = structured
        }
        return response(id: id, result: result)
    }

    /// The bytes of a JSON object.
    private static func data(_ object: [String: Any]) -> Data {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        return (try? JSONSerialization.data(withJSONObject: object, options: options)) ?? Data()
    }
}
