import XCTest
@testable import Peridot

final class SSEParserTests: XCTestCase {
    private func parse(_ text: String) -> [SSEEvent] {
        var parser = SSEParser()
        var events = text.components(separatedBy: "\n").compactMap { parser.feed($0) }
        if let last = parser.finish() { events.append(last) }
        return events
    }

    func testReadsHonoEvents() {
        XCTAssertEqual(
            parse("event: message\ndata: {\"chunk\":\"Hi\"}\n\nevent: done\ndata: {\"done\":true}\n\n"),
            [SSEEvent(event: "message", data: "{\"chunk\":\"Hi\"}"), SSEEvent(event: "done", data: "{\"done\":true}")]
        )
    }

    func testDefaultsToMessageAndJoinsDataLines() {
        XCTAssertEqual(parse("data: a\ndata:b\n\n"), [SSEEvent(event: "message", data: "a\nb")])
    }

    func testIgnoresCommentsAndUnknownFields() {
        XCTAssertEqual(parse(": ping\nid: 7\nretry: 100\ndata: x\n\n"), [SSEEvent(event: "message", data: "x")])
    }

    func testEventWithoutDataIsDropped() {
        XCTAssertEqual(parse("event: message\n\n"), [])
    }

    func testFinishReturnsUnterminatedEvent() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed("data: tail"))
        XCTAssertEqual(parser.finish(), SSEEvent(event: "message", data: "tail"))
        XCTAssertNil(parser.finish())
    }

    func testCleanErrorKeepsTheProviderMessage() {
        XCTAssertEqual(cleanError("400 {\"error\":{\"message\":\"Too long\"}}"), "Too long")
        XCTAssertEqual(cleanError("Plain"), "Plain")
        XCTAssertNil(cleanError(" "))
    }
}
