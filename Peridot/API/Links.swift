import Foundation

/// The public page of a shared chat.
func shareLink(_ id: String, web: URL = Config.webURL) -> String {
    web.absoluteString.trimmingTrailingSlashes + "/share/" + id
}

/// The invite link: a friend who signs up through it is credited to you.
func inviteLink(_ code: String, web: URL = Config.webURL) -> String {
    web.absoluteString.trimmingTrailingSlashes + "/?ref=" + code
}

/// A price in euro cents as shown in the apps: "€ 10", "€ 7.50".
func euros(_ cents: Int) -> String {
    cents % 100 == 0 ? "€ \(cents / 100)" : "€ \(cents / 100)." + String(format: "%02d", locale: Locale(identifier: "en_US_POSIX"), cents % 100)
}

private extension String {
    var trimmingTrailingSlashes: String {
        var s = self
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
