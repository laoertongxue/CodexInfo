import Foundation
import CodexInfoCore
import CodexInfoLive
import CodexInfoMCPKit

// The MCP server of the plugin.
//
// The server answers the JSON-RPC requests of the host over stdio: it reads
// one request per line from the standard input and writes one answer per line
// to the standard output. Nothing but the protocol messages reaches the
// standard output, so the host can parse every line it reads.
let environment = LiveEnvironment.live(snapshotFileName: SnapshotStore.mcpFileName)
let router = MCPRouter(
    toolService: LiveMCPToolService(environment: environment),
    panelHTML: WebAssets.panelHTML
)
let server = MCPStdioServer(router: router)
await server.run(input: FileHandleLineReader(), output: FileHandleLineWriter())
