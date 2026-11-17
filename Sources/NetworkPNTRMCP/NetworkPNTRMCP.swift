import NetworkPNTRCore
import Darwin
import Foundation

@main struct NetworkPNTRMCP {
    static func main() async {
        signal(SIGPIPE, SIG_IGN)
        do {
            let arguments = CommandLine.arguments
            guard arguments.count == 3, arguments[1] == "--connection-file" else {
                FileHandle.standardError.write(Data("Usage: NetworkPNTRMCP --connection-file PRIVATE_CONNECTION_FILE\n".utf8))
                exit(2)
            }
            let connection = try MCPIPCConnection.load(from: URL(fileURLWithPath: arguments[2]))
            try await FiniteMCPServer(client: MCPIPCClient(connection: connection), transport: BoundedStdioTransport()).run()
        } catch {
            FileHandle.standardError.write(Data("NetworkPNTR MCP connection failed. Check the private connection file and running app.\n".utf8))
            exit(1)
        }
    }
}
