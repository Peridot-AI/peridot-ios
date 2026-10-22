import Foundation

/// A small Markdown reader for model answers: the block structure plus inline styles, as plain
/// data (rendering lives in the views). It is forgiving on purpose, because answers are parsed
/// again after every streamed chunk: an unclosed code fence runs to the end, an unclosed `**`
/// stays text. Same rules as the Android app's parser.
enum MDBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case listItem(marker: String, text: String, depth: Int)
    case quote(String)
    case code(language: String, code: String)
    case table(header: [String], rows: [[String]])
    case rule
}

struct MDSpan: Equatable {
    var text: String
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var url: String?
}

enum Markdown {
    private static let heading = try! Regex(#"^ {0,3}(#{1,6})\s+(.*?)(?:\s+#+)?\s*$"#)
    private static let bullet = try! Regex(#"^(\s*)([-*+])\s+(.*)$"#)
    private static let numbered = try! Regex(#"^(\s*)(\d{1,9})([.)])\s+(.*)$"#)
    private static let quote = try! Regex(#"^\s*>\s?(.*)$"#)
    private static let rule = try! Regex(#"^ {0,3}([-*_])(\s*\1){2,}\s*$"#)
    private static let fence = try! Regex(#"^\s*(`{3,}|~{3,})\s*([^`\s]*).*$"#)
    private static let tableSeparator = try! Regex(#"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#)

    /// The capture groups of a whole-line match (index 0 is the whole line), or nil.
    private static func groups(_ regex: Regex<AnyRegexOutput>, _ line: String) -> [String]? {
        guard let match = line.wholeMatch(of: regex) else { return nil }
        return (0..<match.output.count).map { i in match.output[i].substring.map(String.init) ?? "" }
    }

    static func blocks(_ source: String) -> [MDBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out: [MDBlock] = []
        var paragraph: [String] = []
        var quoteLines: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph.removeAll()
        }
        func flushQuote() {
            if !quoteLines.isEmpty { out.append(.quote(quoteLines.joined(separator: "\n"))) }
            quoteLines.removeAll()
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]

            if let f = groups(fence, line) {
                flushParagraph(); flushQuote()
                let marker = f[1]
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].drop(while: { $0.isWhitespace }).hasPrefix(marker) {
                    code.append(lines[i]); i += 1
                }
                out.append(.code(language: f[2], code: code.joined(separator: "\n")))
                i += 1 // the closing fence (or past the end)
                continue
            }

            if line.allSatisfy({ $0.isWhitespace }) { flushParagraph(); flushQuote(); i += 1; continue }

            if let q = groups(quote, line) {
                flushParagraph()
                quoteLines.append(q[1])
                i += 1
                continue
            }
            flushQuote()

            if line.wholeMatch(of: rule) != nil { flushParagraph(); out.append(.rule); i += 1; continue }

            if let h = groups(heading, line) {
                flushParagraph()
                out.append(.heading(level: h[1].count, text: h[2]))
                i += 1
                continue
            }

            if line.contains("|"), i + 1 < lines.count, lines[i + 1].contains("-"), lines[i + 1].wholeMatch(of: tableSeparator) != nil {
                flushParagraph()
                let header = cells(line)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].allSatisfy({ $0.isWhitespace }) {
                    rows.append(cells(lines[i])); i += 1
                }
                out.append(.table(header: header, rows: rows))
                continue
            }

            if let b = groups(bullet, line) {
                flushParagraph()
                out.append(.listItem(marker: "•", text: b[3], depth: depth(b[1])))
                i += 1
                continue
            }
            if let n = groups(numbered, line) {
                flushParagraph()
                out.append(.listItem(marker: n[2] + ".", text: n[4], depth: depth(n[1])))
                i += 1
                continue
            }

            // An indented line right after a list item continues that item
            if paragraph.isEmpty, case let .listItem(marker, text, d)? = out.last, line.first?.isWhitespace == true {
                out[out.count - 1] = .listItem(marker: marker, text: text + " " + line.trimmingCharacters(in: .whitespaces), depth: d)
                i += 1
                continue
            }

            paragraph.append(line.trimmingCharacters(in: .whitespaces))
            i += 1
        }
        flushParagraph(); flushQuote()
        return out
    }

    private static func depth(_ indent: String) -> Int {
        let width = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return min(width / 2, 4)
    }

    private static func cells(_ row: String) -> [String] {
        var s = Array(row.trimmingCharacters(in: .whitespaces))
        if s.first == "|" { s.removeFirst() }
        if s.last == "|", !(s.count >= 2 && s[s.count - 2] == "\\") { s.removeLast() }
        var cells: [String] = []
        var cell = ""
        var j = 0
        while j < s.count {
            let c = s[j]
            if c == "\\", j + 1 < s.count, s[j + 1] == "|" { cell.append("|"); j += 2; continue }
            if c == "|" { cells.append(cell.trimmingCharacters(in: .whitespaces)); cell = "" } else { cell.append(c) }
            j += 1
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    // MARK: Inline

    private struct Style: Equatable {
        var bold = false
        var italic = false
        var strike = false
        var url: String?
    }

    private static let escapable = Set("\\`*_{}[]()#+-.!|~<>")

    static func spans(_ source: String) -> [MDSpan] {
        var out: [MDSpan] = []
        parse(Array(source), Style(), &out)
        // Neighbours with the same style become one span
        var merged: [MDSpan] = []
        for span in out {
            if var prev = merged.last, sameStyle(prev, span) {
                prev.text += span.text
                merged[merged.count - 1] = prev
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func sameStyle(_ a: MDSpan, _ b: MDSpan) -> Bool {
        a.bold == b.bold && a.italic == b.italic && a.strike == b.strike && a.code == b.code && a.url == b.url
    }

    private static func span(_ text: String, _ style: Style, code: Bool = false, url: String? = nil) -> MDSpan {
        MDSpan(text: text, bold: style.bold, italic: style.italic, strike: style.strike, code: code, url: url ?? style.url)
    }

    private static func parse(_ s: [Character], _ style: Style, _ out: inout [MDSpan]) {
        var buf = ""
        func flush() {
            if !buf.isEmpty { out.append(span(buf, style)) }
            buf = ""
        }
        var i = 0
        while i < s.count {
            let c = s[i]
            // Backslash escapes
            if c == "\\", i + 1 < s.count, escapable.contains(s[i + 1]) { buf.append(s[i + 1]); i += 2; continue }

            // `code`
            if c == "`" {
                var n = 0
                while i + n < s.count, s[i + n] == "`" { n += 1 }
                guard let close = find(s, Array(repeating: "`", count: n), from: i + n) else {
                    buf += String(repeating: "`", count: n); i += n; continue
                }
                flush()
                var code = String(s[(i + n)..<close])
                if code.count > 2, code.hasPrefix(" "), code.hasSuffix(" ") { code = String(code.dropFirst().dropLast()) }
                out.append(span(code, style, code: true))
                i = close + n
                continue
            }

            // **bold**, __bold__, ~~strike~~
            if i + 1 < s.count, s[i + 1] == c, c == "*" || c == "_" || c == "~" {
                if let close = closeDouble(s, c, from: i + 2), opens(s, i, 2, c), closes(s, close, 2, c) {
                    flush()
                    var inner = style
                    if c == "~" { inner.strike = true } else { inner.bold = true }
                    parse(Array(s[(i + 2)..<close]), inner, &out)
                    i = close + 2
                    continue
                }
                buf.append(c); buf.append(c)
                i += 2
                continue
            }

            // *italic*, _italic_
            if c == "*" || c == "_" {
                if let close = closeSingle(s, c, from: i + 1), opens(s, i, 1, c), closes(s, close, 1, c) {
                    flush()
                    var inner = style
                    inner.italic = true
                    parse(Array(s[(i + 1)..<close]), inner, &out)
                    i = close + 1
                    continue
                }
                buf.append(c)
                i += 1
                continue
            }

            // [text](url)
            if c == "[", style.url == nil, let textEnd = matching(s, i, "[", "]"), textEnd + 1 < s.count, s[textEnd + 1] == "(",
               let urlEnd = matching(s, textEnd + 1, "(", ")") {
                let raw = String(s[(textEnd + 2)..<urlEnd]).trimmingCharacters(in: .whitespaces)
                let url = String(raw.prefix { $0 != " " })
                if isWebURL(url) {
                    flush()
                    var inner = style
                    inner.url = url
                    parse(Array(s[(i + 1)..<textEnd]), inner, &out)
                    i = urlEnd + 1
                    continue
                }
            }

            // Bare links
            if style.url == nil, starts(s, i, "https://") || starts(s, i, "http://"), i == 0 || !(s[i - 1].isLetter || s[i - 1].isNumber) {
                var end = i
                while end < s.count, !s[end].isWhitespace, s[end] != "<", s[end] != ">" { end += 1 }
                while end > i, ".,;:!?'\")]*_".contains(s[end - 1]) { end -= 1 }
                let url = String(s[i..<end])
                if url.count > 8 {
                    flush()
                    out.append(span(url, style, url: url))
                    i = end
                    continue
                }
            }

            buf.append(c)
            i += 1
        }
        flush()
    }

    private static func starts(_ s: [Character], _ at: Int, _ prefix: String) -> Bool {
        let p = Array(prefix)
        guard at + p.count <= s.count else { return false }
        return Array(s[at..<(at + p.count)]) == p
    }

    private static func find(_ s: [Character], _ needle: [Character], from: Int) -> Int? {
        guard !needle.isEmpty, from <= s.count - needle.count else { return nil }
        for j in from...(s.count - needle.count) where Array(s[j..<(j + needle.count)]) == needle {
            return j
        }
        return nil
    }

    private static func isWordChar(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c.isLetter || c.isNumber
    }

    /// Can a delimiter run at `at` open emphasis? Not before a space, and `_` not inside a word.
    private static func opens(_ s: [Character], _ at: Int, _ len: Int, _ ch: Character) -> Bool {
        guard at + len < s.count, !s[at + len].isWhitespace else { return false }
        if ch == "_", at > 0, isWordChar(s[at - 1]) { return false }
        return true
    }

    private static func closes(_ s: [Character], _ at: Int, _ len: Int, _ ch: Character) -> Bool {
        guard at > 0, !s[at - 1].isWhitespace else { return false }
        if ch == "_", at + len < s.count, isWordChar(s[at + len]) { return false }
        return true
    }

    /// In a longer run like `***`, the closer is its last two characters (the rest closes inner italics).
    private static func closeDouble(_ s: [Character], _ ch: Character, from: Int) -> Int? {
        var j = from
        var found: Int?
        while j + 1 < s.count {
            if s[j] == ch, s[j + 1] == ch, j != from, !s[j - 1].isWhitespace { found = j; break }
            j += 1
        }
        guard var k = found else { return nil }
        while k + 2 < s.count, s[k + 2] == ch { k += 1 }
        return k
    }

    /// The next single `ch` that isn't half of a double one (those belong to nested bold).
    private static func closeSingle(_ s: [Character], _ ch: Character, from: Int) -> Int? {
        var j = from
        while j < s.count {
            if s[j] == "`" {
                guard let end = s[(j + 1)...].firstIndex(of: "`") else { return nil }
                j = end + 1
                continue
            }
            if s[j] == ch {
                if j + 1 < s.count, s[j + 1] == ch { j += 2; continue }
                if j > from, !s[j - 1].isWhitespace { return j }
            }
            j += 1
        }
        return nil
    }

    private static func matching(_ s: [Character], _ open: Int, _ a: Character, _ b: Character) -> Int? {
        var depth = 0
        for j in open..<s.count {
            if s[j] == a { depth += 1 } else if s[j] == b { depth -= 1; if depth == 0 { return j } }
        }
        return nil
    }

    private static func isWebURL(_ url: String) -> Bool {
        url.hasPrefix("https://") || url.hasPrefix("http://") || url.hasPrefix("mailto:")
    }
}
