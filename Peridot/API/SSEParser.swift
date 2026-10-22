import Foundation

/// One server-sent event.
struct SSEEvent: Equatable, Sendable {
    let event: String
    let data: String
}

/// Incremental parser for a text/event-stream, fed one line at a time (without the line break).
/// A blank line ends an event; `data:` lines are joined with "\n"; comments and unknown fields
/// are ignored, as the spec says.
struct SSEParser {
    private var event = ""
    private var data = ""
    private var hasData = false

    /// Returns the finished event when `line` ends one, otherwise nil.
    mutating func feed(_ line: String) -> SSEEvent? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = line[...]
            value = ""
        }
        switch field {
        case "event":
            event = String(value)
        case "data":
            if hasData { data += "\n" }
            data += value
            hasData = true
        default:
            break
        }
        return nil
    }

    /// Call when the stream ends: returns an event that was not followed by a blank line.
    mutating func finish() -> SSEEvent? { dispatch() }

    private mutating func dispatch() -> SSEEvent? {
        defer { event = ""; data = ""; hasData = false }
        guard hasData else { return nil }
        return SSEEvent(event: event.isEmpty ? "message" : event, data: data)
    }
}
