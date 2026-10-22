import Foundation

/// Where the app finds Peridot. Set `PERIDOT_API_URL` / `PERIDOT_WEB_URL` in the scheme's
/// environment to use another server (e.g. `http://localhost:3001/api` in the simulator).
enum Config {
    static let apiURL = url("PERIDOT_API_URL", default: "https://peridot.ai/api")
    static let webURL = url("PERIDOT_WEB_URL", default: "https://peridot.ai")

    private static func url(_ key: String, default fallback: String) -> URL {
        var value = ProcessInfo.processInfo.environment[key] ?? fallback
        while value.hasSuffix("/") { value.removeLast() }
        return URL(string: value) ?? URL(string: fallback)!
    }
}
