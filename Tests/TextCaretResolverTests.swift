@testable import ClipStack
import XCTest

/// Scripted geometry source. Markers are UTF-16 offsets into `text`; elements are string identifiers.
final class FakeCaretGeometry: TextCaretGeometrySource {
    typealias Marker = Int
    typealias Element = String

    var text = ""
    var fieldFrame: CGRect?
    var selectedRange: CFRange?
    var count: Int?
    var rangeBounds: [String: CGRect] = [:]
    var markerSelection: TextMarkerRange<Int>?
    var markerBounds: [String: CGRect] = [:]
    var markerStrings: [String: String] = [:]
    var nextMarkerOverrides: [Int: Int] = [:]
    var containers: [Int: String] = [:]
    var frames: [String: CGRect] = [:]
    var elementRanges: [String: TextMarkerRange<Int>] = [:]
    var parents: [String: String] = [:]
    var fieldElement = "field"

    func selectedTextRange() -> CFRange? { selectedRange }
    func characterCount() -> Int? { count ?? text.utf16.count }
    func bounds(for range: CFRange) -> CGRect? { rangeBounds["\(range.location),\(range.length)"] }
    func string(for range: CFRange) -> String? { substring(range.location, range.location + range.length) }
    func selectedMarkerRange() -> TextMarkerRange<Int>? { markerSelection }
    func marker(before marker: Int) -> Int? { marker > 0 ? marker - 1 : nil }

    func marker(after marker: Int) -> Int? {
        if let override = nextMarkerOverrides[marker] {
            return override
        }
        return marker < text.utf16.count ? marker + 1 : nil
    }

    func bounds(for range: TextMarkerRange<Int>) -> CGRect? { markerBounds["\(range.start)-\(range.end)"] }

    func string(for range: TextMarkerRange<Int>) -> String? {
        markerStrings["\(range.start)-\(range.end)"] ?? substring(range.start, range.end)
    }

    func element(containing marker: Int) -> String? { containers[marker] }
    func frame(of element: String) -> CGRect? { frames[element] }
    func markerRange(of element: String) -> TextMarkerRange<Int>? { elementRanges[element] }
    func parent(of element: String) -> String? { parents[element] }
    func isField(_ element: String) -> Bool { element == fieldElement }

    private func substring(_ start: Int, _ end: Int) -> String? {
        let utf16 = text.utf16
        guard start >= 0, start <= end, end <= utf16.count else {
            return nil
        }
        return (text as NSString).substring(with: NSRange(location: start, length: end - start))
    }
}

/// Deterministic stand-in for TextKit: every glyph is `glyphWidth` wide and lines wrap greedily.
struct FixedGlyphMeasurer: TextRunMeasuring {
    final class Recorder {
        var calls: [(prefix: Int, text: String, runFrame: CGRect, wrapWidth: CGFloat)] = []
    }

    var glyphWidth: CGFloat = 7
    let recorder = Recorder()

    func caretRect(prefixLength: Int, in text: String, runFrame: CGRect, wrapWidth: CGFloat) -> CGRect? {
        recorder.calls.append((prefixLength, text, runFrame, wrapWidth))
        let length = text.utf16.count
        let perLine = max(1, Int(wrapWidth / glyphWidth))
        let lineCount = max(1, Int((Double(length) / Double(perLine)).rounded(.up)))
        let lineHeight = runFrame.height / CGFloat(lineCount)
        let line = min(prefixLength / perLine, lineCount - 1)
        let column = prefixLength - line * perLine
        return CGRect(
            x: runFrame.minX + CGFloat(column) * glyphWidth,
            y: runFrame.minY + CGFloat(line) * lineHeight,
            width: 1,
            height: lineHeight
        )
    }
}

final class TextCaretResolverTests: XCTestCase {
    private static let textEditField = CGRect(x: 181, y: 134, width: 656, height: 384)
    private static let textEditText = "First line of sample text here\nSecond line with more words inside\n\nFourth line after an empty one\n"

    private func resolve(_ source: FakeCaretGeometry, measurer: FixedGlyphMeasurer = FixedGlyphMeasurer()) -> TextCaretReport {
        TextCaretResolver(source: source, measurer: measurer).resolve()
    }

    private func assertRect(_ report: TextCaretReport, _ x: CGFloat, _ y: CGFloat, _ height: CGFloat, path: TextCaretPath, file: StaticString = #filePath, line: UInt = #line) {
        guard let resolution = report.resolution else {
            XCTFail("caret not resolved: \(report.trace)", file: file, line: line)
            return
        }
        XCTAssertEqual(resolution.rect.minX, x, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(resolution.rect.minY, y, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(resolution.rect.height, height, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(resolution.rect.width, 1, file: file, line: line)
        XCTAssertEqual(resolution.path, path, file: file, line: line)
    }

    private func makeTextEdit(caret: Int, length: Int = 0) -> FakeCaretGeometry {
        let source = FakeCaretGeometry()
        source.text = Self.textEditText
        source.fieldFrame = Self.textEditField
        source.selectedRange = CFRange(location: caret - length, length: length)
        return source
    }

    // Values below were captured from TextEdit (NSTextView) with AXBoundsForRange.

    func testAppKitCaretInMiddleOfLineUsesPreviousCharacterTrailingEdge() {
        let source = makeTextEdit(caret: 12)
        source.rangeBounds["12,0"] = CGRect(x: 270.47, y: 121, width: 0, height: 13)
        source.rangeBounds["11,1"] = CGRect(x: 263.848, y: 134, width: 6.6226, height: 13)
        source.rangeBounds["12,1"] = CGRect(x: 270.47, y: 134, width: 6.6226, height: 13)

        assertRect(resolve(source), 270.4706, 134, 13, path: .rangePreviousCharacter)
    }

    func testAppKitStartOfLineUsesNextCharacterWhenPreviousIsLineBreak() {
        let source = makeTextEdit(caret: 31)
        source.rangeBounds["31,0"] = CGRect(x: 191, y: 134, width: 0, height: 13)
        source.rangeBounds["30,1"] = CGRect(x: 389.677, y: 134, width: 437.323, height: 13)
        source.rangeBounds["31,1"] = CGRect(x: 191, y: 147, width: 6.6226, height: 13)

        let report = resolve(source)
        assertRect(report, 191, 147, 13, path: .rangeNextCharacter)
        XCTAssertTrue(report.trace.contains("range: previous character is a line break"))
    }

    func testAppKitEndOfLineUsesPreviousCharacter() {
        let source = makeTextEdit(caret: 65)
        source.rangeBounds["65,0"] = CGRect(x: 416.167, y: 134, width: 0, height: 13)
        source.rangeBounds["64,1"] = CGRect(x: 409.544, y: 147, width: 6.6226, height: 13)
        source.rangeBounds["65,1"] = CGRect(x: 416.167, y: 147, width: 410.833, height: 13)

        assertRect(resolve(source), 416.1666, 147, 13, path: .rangePreviousCharacter)
    }

    func testAppKitEmptyLineUsesLeadingEdgeOfItsLineBreak() {
        let source = makeTextEdit(caret: 66)
        source.rangeBounds["66,0"] = CGRect(x: 191, y: 147, width: 0, height: 13)
        source.rangeBounds["65,1"] = CGRect(x: 416.167, y: 147, width: 410.833, height: 13)
        source.rangeBounds["66,1"] = CGRect(x: 191, y: 160, width: 636, height: 13)

        assertRect(resolve(source), 191, 160, 13, path: .rangeNextCharacter)
    }

    func testAppKitFourthLineOfMultilineField() {
        let source = makeTextEdit(caret: 77)
        source.rangeBounds["77,0"] = CGRect(x: 257.226, y: 160, width: 0, height: 13)
        source.rangeBounds["76,1"] = CGRect(x: 250.603, y: 173, width: 6.6226, height: 13)
        source.rangeBounds["77,1"] = CGRect(x: 257.226, y: 173, width: 6.6226, height: 13)

        assertRect(resolve(source), 257.2256, 173, 13, path: .rangePreviousCharacter)
    }

    func testAppKitSelectionAnchorsAtSelectionEnd() {
        let source = makeTextEdit(caret: 13, length: 2)
        source.rangeBounds["13,0"] = CGRect(x: 277.093, y: 121, width: 0, height: 13)
        source.rangeBounds["12,1"] = CGRect(x: 270.47, y: 134, width: 6.6226, height: 13)
        source.rangeBounds["13,1"] = CGRect(x: 277.093, y: 134, width: 6.6226, height: 13)
        source.rangeBounds["11,2"] = CGRect(x: 263.848, y: 134, width: 13.245, height: 13)

        assertRect(resolve(source), 277.0926, 134, 13, path: .rangePreviousCharacter)
    }

    func testAppKitCaretAfterTrailingLineBreakShiftsZeroLengthBoundsBelowTheBreak() {
        let source = makeTextEdit(caret: 98)
        source.rangeBounds["98,0"] = CGRect(x: 191, y: 173, width: 0, height: 13)
        source.rangeBounds["97,1"] = CGRect(x: 389.677, y: 173, width: 437.323, height: 13)

        let report = resolve(source)
        assertRect(report, 191, 186, 13, path: .rangeZeroLengthShifted)
        XCTAssertTrue(report.trace.contains("range: caret is at the end of the text"))
    }

    func testAppKitEmptyTextAreaShiftsZeroLengthBoundsIntoTheField() {
        let source = FakeCaretGeometry()
        source.fieldFrame = Self.textEditField
        source.selectedRange = CFRange(location: 0, length: 0)
        source.rangeBounds["0,0"] = CGRect(x: 191, y: 114, width: 0, height: 20)

        assertRect(resolve(source), 191, 134, 20, path: .rangeZeroLengthShifted)
    }

    func testAppKitEmptySearchFieldShiftsZeroLengthBoundsIntoTheField() {
        let source = FakeCaretGeometry()
        source.fieldFrame = CGRect(x: 188, y: 139, width: 477.5, height: 22)
        source.selectedRange = CFRange(location: 0, length: 0)
        source.rangeBounds["0,0"] = CGRect(x: 218, y: 130, width: 0, height: 13)

        assertRect(resolve(source), 218, 143, 13, path: .rangeZeroLengthShifted)
    }

    func testAppKitZeroLengthBoundsInsideTheFieldAreKeptWhenNothingContradictsThem() {
        let source = FakeCaretGeometry()
        source.fieldFrame = Self.textEditField
        source.selectedRange = CFRange(location: 0, length: 0)
        source.rangeBounds["0,0"] = CGRect(x: 191, y: 134, width: 0, height: 20)

        assertRect(resolve(source), 191, 134, 20, path: .rangeZeroLength)
    }

    func testAppKitRejectsWholeLineAndWholeFieldRects() {
        let source = makeTextEdit(caret: 12)
        source.text = String(repeating: "x", count: 98)
        source.rangeBounds["11,1"] = CGRect(x: 191, y: 134, width: 636, height: 13)
        source.rangeBounds["12,1"] = Self.textEditField
        source.rangeBounds["12,0"] = CGRect(x: 10, y: 10, width: 0, height: 13)

        let report = resolve(source)
        XCTAssertNil(report.resolution)
        XCTAssertTrue(report.trace.contains { $0.hasPrefix("range: previous character bounds") && $0.hasSuffix("wider than a character") }, "\(report.trace)")
        XCTAssertTrue(report.trace.contains { $0.hasPrefix("range: next character bounds") && $0.hasSuffix("matches the whole field") }, "\(report.trace)")
        XCTAssertTrue(report.trace.contains { $0.hasPrefix("range: zero-length bounds") && $0.hasSuffix("outside the field") }, "\(report.trace)")
    }

    func testAppKitRejectsNonFiniteBounds() {
        let source = makeTextEdit(caret: 12)
        source.rangeBounds["11,1"] = CGRect(x: CGFloat.nan, y: 134, width: 6, height: 13)
        source.rangeBounds["12,1"] = CGRect(x: 270, y: CGFloat.infinity, width: 6, height: 13)

        let report = resolve(source)
        XCTAssertNil(report.resolution)
        XCTAssertEqual(report.trace.filter { $0.hasSuffix("non-finite") }.count, 2, "\(report.trace)")
    }

    // Values below were captured from the Codex composer (Chromium without inline text boxes).

    private static let codexField = CGRect(x: 380, y: 882, width: 712, height: 44)
    private static let codexText = "alpha beta gamma delta epsilon\nsecond line zeta eta theta"

    private func makeCodex(caret: Int) -> FakeCaretGeometry {
        let source = FakeCaretGeometry()
        source.text = Self.codexText
        source.fieldFrame = Self.codexField
        source.selectedRange = CFRange(location: caret, length: 0)
        source.markerSelection = TextMarkerRange(start: caret, end: caret)
        for offset in 0...30 {
            source.containers[offset] = "text1"
        }
        for offset in 31...57 {
            source.containers[offset] = "text2"
        }
        source.frames["text1"] = CGRect(x: 380, y: 902, width: 230, height: 20)
        source.frames["text2"] = CGRect(x: 380, y: 922, width: 200, height: 20)
        source.frames["paragraph1"] = CGRect(x: 380, y: 902, width: 712, height: 20)
        source.frames["paragraph2"] = CGRect(x: 380, y: 922, width: 712, height: 20)
        source.elementRanges["text1"] = TextMarkerRange(start: 0, end: 31)
        source.elementRanges["text2"] = TextMarkerRange(start: 31, end: 57)
        source.parents = ["text1": "paragraph1", "text2": "paragraph2", "paragraph1": "field", "paragraph2": "field"]
        return source
    }

    func testWebCaretInMiddleOfLineWithoutCharacterBoundsIsMeasuredInsideItsTextRun() {
        let source = makeCodex(caret: 21)
        let measurer = FixedGlyphMeasurer()

        let report = resolve(source, measurer: measurer)
        assertRect(report, 380 + 21 * 7, 902, 20, path: .markerMeasuredRun)
        XCTAssertEqual(measurer.recorder.calls.count, 1)
        XCTAssertEqual(measurer.recorder.calls.first?.prefix, 21)
        XCTAssertEqual(measurer.recorder.calls.first?.text, "alpha beta gamma delta epsilon")
        XCTAssertEqual(measurer.recorder.calls.first?.wrapWidth, 712)
        XCTAssertTrue(report.trace.contains("marker: collapsed bounds unavailable"))
        XCTAssertTrue(report.trace.contains("marker: previous character bounds unavailable"))
        XCTAssertTrue(report.trace.contains("marker: next character bounds unavailable"))
    }

    func testWebCaretAtStartAndEndOfLineUsesRunEdges() {
        assertRect(resolve(makeCodex(caret: 31)), 380, 922, 20, path: .markerMeasuredRun)
        assertRect(resolve(makeCodex(caret: 30)), 380 + 30 * 7, 902, 20, path: .markerMeasuredRun)
    }

    func testWebCaretAtEndOfTextRejectsNextMarkerThatCrossesIntoControls() {
        let source = makeCodex(caret: 56)
        source.nextMarkerOverrides[56] = 58
        source.markerStrings["56-58"] = "\u{FFFC}\u{FFFC}"
        source.markerBounds["56-58"] = CGRect(x: 560, y: 922, width: 134, height: 20)

        let report = resolve(source)
        assertRect(report, 380 + 25 * 7, 922, 20, path: .markerMeasuredRun)
        XCTAssertTrue(report.trace.contains { $0.hasPrefix("marker: next character bounds") && $0.hasSuffix("spans more than one character") }, "\(report.trace)")
    }

    func testWebCaretOnEmptyLineUsesLeadingEdgeOfEmptyContainer() {
        let source = FakeCaretGeometry()
        source.text = "short\n\n"
        source.fieldFrame = CGRect(x: 380, y: 846, width: 712, height: 80)
        source.markerSelection = TextMarkerRange(start: 6, end: 6)
        source.containers[6] = "empty"
        source.frames["empty"] = CGRect(x: 380, y: 906, width: 712, height: 20)
        source.elementRanges["empty"] = TextMarkerRange(start: 6, end: 7)
        source.parents["empty"] = "field"

        assertRect(resolve(source), 380, 906, 20, path: .markerEmptyContainer)
    }

    func testWebCaretInWrappedRunLandsOnSecondVisualLine() {
        let paragraph = String(repeating: "abcdefghij", count: 16) + "xyz"
        let source = FakeCaretGeometry()
        source.text = paragraph + "\n"
        source.fieldFrame = CGRect(x: 380, y: 846, width: 712, height: 80)
        source.markerSelection = TextMarkerRange(start: 120, end: 120)
        source.containers[120] = "text"
        source.frames["text"] = CGRect(x: 380, y: 848, width: 687, height: 36)
        source.frames["paragraph"] = CGRect(x: 380, y: 846, width: 712, height: 40)
        source.elementRanges["text"] = TextMarkerRange(start: 0, end: 164)
        source.parents = ["text": "paragraph", "paragraph": "field"]

        assertRect(resolve(source), 380 + 19 * 7, 866, 18, path: .markerMeasuredRun)
    }

    func testWebNextMarkerOnFollowingLineIsRejectedInFavourOfRunEnd() {
        let source = FakeCaretGeometry()
        source.text = "short\n\n"
        source.fieldFrame = CGRect(x: 304, y: 846, width: 690, height: 80)
        source.markerSelection = TextMarkerRange(start: 5, end: 5)
        source.containers[5] = "short"
        source.frames["short"] = CGRect(x: 304, y: 888, width: 34, height: 16)
        source.frames["paragraph"] = CGRect(x: 304, y: 886, width: 690, height: 20)
        source.elementRanges["short"] = TextMarkerRange(start: 0, end: 6)
        source.parents = ["short": "paragraph", "paragraph": "field"]
        source.markerBounds["5-6"] = CGRect(x: 304, y: 906, width: 690, height: 20)

        let report = resolve(source)
        assertRect(report, 304 + 5 * 7, 888, 16, path: .markerMeasuredRun)
        XCTAssertTrue(report.trace.contains { $0.hasPrefix("marker: next character bounds") && $0.hasSuffix("outside the caret container") }, "\(report.trace)")
    }

    func testWebContainerOutsideFocusedFieldIsRejected() {
        let source = makeCodex(caret: 21)
        source.parents["paragraph1"] = "sidebar"

        let report = resolve(source)
        XCTAssertNil(report.resolution)
        XCTAssertTrue(report.trace.contains("marker: caret container is outside the focused field"))
    }

    func testWebContainerMatchingWholeFieldIsRejected() {
        let source = makeCodex(caret: 21)
        source.frames["text1"] = Self.codexField

        let report = resolve(source)
        XCTAssertNil(report.resolution)
        XCTAssertTrue(report.trace.contains { $0.hasPrefix("marker: caret container frame") && $0.hasSuffix("matches the whole field") }, "\(report.trace)")
    }

    // WebKit-style sources expose real character geometry through text markers.

    func testWebCollapsedMarkerBoundsWinWhenAvailable() {
        let source = makeCodex(caret: 21)
        source.markerBounds["21-21"] = CGRect(x: 527, y: 902, width: 0, height: 20)

        assertRect(resolve(source), 527, 902, 20, path: .markerCollapsed)
    }

    func testWebWholeLineCollapsedBoundsAreRejectedInFavourOfPreviousCharacter() {
        let source = makeCodex(caret: 21)
        source.markerBounds["21-21"] = CGRect(x: 380, y: 902, width: 712, height: 20)
        source.markerBounds["20-21"] = CGRect(x: 520, y: 902, width: 7, height: 20)

        let report = resolve(source)
        assertRect(report, 527, 902, 20, path: .markerPreviousCharacter)
        XCTAssertTrue(report.trace.contains { $0.hasPrefix("marker: collapsed bounds") && $0.hasSuffix("wider than a caret") }, "\(report.trace)")
    }

    func testWebStartOfLineUsesNextMarkerWhenPreviousIsLineBreak() {
        let source = makeCodex(caret: 31)
        source.markerBounds["30-31"] = CGRect(x: 610, y: 902, width: 300, height: 20)
        source.markerBounds["31-32"] = CGRect(x: 380, y: 922, width: 7, height: 20)

        let report = resolve(source)
        assertRect(report, 380, 922, 20, path: .markerNextCharacter)
        XCTAssertTrue(report.trace.contains("marker: previous character is a line break"))
    }

    func testWebSelectionAnchorsAtSelectionEnd() {
        let source = makeCodex(caret: 21)
        source.markerSelection = TextMarkerRange(start: 15, end: 21)
        source.markerBounds["20-21"] = CGRect(x: 520, y: 902, width: 7, height: 20)

        assertRect(resolve(source), 527, 902, 20, path: .markerPreviousCharacter)
    }

    func testNothingResolvesWithoutSelectionInformation() {
        let source = FakeCaretGeometry()
        source.fieldFrame = Self.textEditField

        let report = resolve(source)
        XCTAssertNil(report.resolution)
        XCTAssertEqual(report.trace, ["marker: no selected text marker range", "range: no selected text range"])
    }
}

@MainActor
final class TextKitRunMeasurerTests: XCTestCase {
    private let measurer = TextKitRunMeasurer()

    func testSingleLineRunMapsPrefixMonotonicallyBetweenRunEdges() throws {
        let text = "alpha beta gamma delta epsilon"
        let run = CGRect(x: 380, y: 902, width: 230, height: 20)

        let start = try XCTUnwrap(measurer.caretRect(prefixLength: 0, in: text, runFrame: run, wrapWidth: 712))
        let end = try XCTUnwrap(measurer.caretRect(prefixLength: text.utf16.count, in: text, runFrame: run, wrapWidth: 712))
        XCTAssertEqual(start.minX, run.minX, accuracy: 0.01)
        XCTAssertEqual(end.minX, run.maxX, accuracy: 0.5)
        XCTAssertEqual(start.minY, 902)
        XCTAssertEqual(start.height, 20)

        var previous = start.minX
        for prefix in 1...text.utf16.count {
            let caret = try XCTUnwrap(measurer.caretRect(prefixLength: prefix, in: text, runFrame: run, wrapWidth: 712))
            XCTAssertGreaterThan(caret.minX, previous, "prefix \(prefix)")
            XCTAssertLessThanOrEqual(caret.minX, run.maxX + 0.5)
            XCTAssertEqual(caret.minY, 902)
            previous = caret.minX
        }
    }

    func testWrappedRunPlacesLaterCaretsOnLowerLines() throws {
        let text = "The quick brown fox jumps over the lazy dog while the cat watches quietly from the window and the birds sing in the trees outside the old house near the river bank"
        let run = CGRect(x: 380, y: 848, width: 687, height: 36)

        let first = try XCTUnwrap(measurer.caretRect(prefixLength: 10, in: text, runFrame: run, wrapWidth: 712))
        let last = try XCTUnwrap(measurer.caretRect(prefixLength: text.utf16.count, in: text, runFrame: run, wrapWidth: 712))
        XCTAssertEqual(first.minY, 848, accuracy: 0.01)
        XCTAssertEqual(first.height, 18, accuracy: 0.01)
        XCTAssertEqual(last.minY, 866, accuracy: 0.01)
        XCTAssertGreaterThan(first.minX, run.minX)
        XCTAssertLessThan(first.minX, run.midX)
        XCTAssertLessThanOrEqual(last.minX, run.maxX + 0.5)
    }

    func testRefusesEmptyTextAndDegenerateFrames() {
        XCTAssertNil(measurer.caretRect(prefixLength: 0, in: "", runFrame: CGRect(x: 0, y: 0, width: 100, height: 20), wrapWidth: 300))
        XCTAssertNil(measurer.caretRect(prefixLength: 2, in: "abc", runFrame: CGRect(x: 0, y: 0, width: 100, height: 0), wrapWidth: 300))
        XCTAssertNil(measurer.caretRect(prefixLength: 2, in: "abc", runFrame: CGRect(x: 0, y: 0, width: 0, height: 20), wrapWidth: 300))
    }
}
