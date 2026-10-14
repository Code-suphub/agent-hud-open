import AgentHUDSupport
import Foundation

/// One tool call on its way from the MCP process to the running application: the tool's name and the arguments the
/// client sent, as they came. The process checks only that the tool exists and that the arguments are an object; what
/// they mean, and whether they are valid, is for the application to say.
public struct MCPToolRequest: Equatable, Sendable {
    public let tool: String
    public let arguments: [String: JSONValue]

    public init(tool: String, arguments: [String: JSONValue] = [:]) {
        self.tool = tool
        self.arguments = arguments
    }

    /// The largest request the channel carries, in bytes.
    static let sizeLimit = 1024 * 1024

    /// Why a message on the channel is no request, as a sentence for the agent that sent it.
    struct Unreadable: Error, Equatable {
        let reason: String
    }

    /// The request as the channel carries it: `{"tool": …, "arguments": {…}}`.
    var message: Data {
        let value = JSONValue.object(["tool": .string(tool), "arguments": .object(arguments)])
        return (try? RecordCoding.encoder().encode(value)) ?? Data()
    }

    /// Reads a request off the channel. Arguments left out are none.
    static func read(_ message: Data) throws -> MCPToolRequest {
        guard let object = (try? JSONValue.parse(message))?.objectValue else {
            throw Unreadable(reason: "The request is not a JSON object.")
        }
        guard let tool = object["tool"]?.stringValue, !tool.isEmpty else {
            throw Unreadable(reason: "The request names no tool.")
        }
        switch object["arguments"] {
        case nil, .null?: return MCPToolRequest(tool: tool)
        case .object(let arguments)?: return MCPToolRequest(tool: tool, arguments: arguments)
        default: throw Unreadable(reason: "The request's arguments are not a JSON object.")
        }
    }
}

/// The application's answer to a tool call: what the tool returned, or an English sentence that tells the agent why
/// it was refused and what to change.
public enum MCPToolReply: Equatable, Sendable {
    case result([String: JSONValue])
    case failure(String)

    /// The reply as the channel carries it: `{"ok": true, "result": {…}}` or `{"ok": false, "error": "…"}`. A result
    /// JSON cannot hold, such as a number that is not finite, travels as the failure it is.
    var message: Data {
        let encoder = RecordCoding.encoder()
        if case .result(let result) = self,
           let data = try? encoder.encode(JSONValue.object(["ok": .bool(true), "result": .object(result)])) {
            return data
        }
        var sentence = "The result could not be written as JSON."
        if case .failure(let given) = self { sentence = given }
        let refusal = JSONValue.object(["ok": .bool(false), "error": .string(sentence)])
        return (try? encoder.encode(refusal)) ?? Data(#"{"ok":false,"error":"The reply could not be written."}"#.utf8)
    }

    /// Reads a reply off the channel; nil for anything else, an empty answer included.
    static func read(_ message: Data) -> MCPToolReply? {
        guard let object = (try? JSONValue.parse(message))?.objectValue else { return nil }
        switch object["ok"] {
        case .bool(true)?:
            guard let result = object["result"]?.objectValue else { return nil }
            return .result(result)
        case .bool(false)?:
            guard let sentence = object["error"]?.stringValue else { return nil }
            return .failure(sentence)
        default:
            return nil
        }
    }
}
