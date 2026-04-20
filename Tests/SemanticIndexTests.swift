import AppKit
@testable import ClipStack
import XCTest

final class SemanticIndexTests: XCTestCase {
    func testSubstringFallbackForShortQuery() async {
        let provider = CountingNilVectorProvider()
        let matchingItem = ClipboardItem.text("hello world")
        let nonMatchingItem = ClipboardItem.text("meeting notes")
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [
            (matchingItem.id, matchingItem.textValue!),
            (nonMatchingItem.id, nonMatchingItem.textValue!)
        ])
        provider.resetCallCount()

        let results = await index.search(query: "he", allItems: [nonMatchingItem, matchingItem])

        XCTAssertEqual(results.map(\.id), [matchingItem.id])
        XCTAssertEqual(provider.callCount, 0)
    }

    func testRankingBoostsExactSubstringMatches() async {
        let semanticOnlyItem = ClipboardItem.text("agenda for call")
        let substringItem = ClipboardItem.text("meeting minutes")
        let provider = DictionaryVectorProvider(vectors: [
            "meeting": [1, 0],
            "agenda for call": [0.99, 0.10],
            "meeting minutes": [0.90, 0.10]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [
            (semanticOnlyItem.id, semanticOnlyItem.textValue!),
            (substringItem.id, substringItem.textValue!)
        ])

        let results = await index.search(query: "meeting", allItems: [semanticOnlyItem, substringItem])

        XCTAssertEqual(results.first?.id, substringItem.id)
    }

    func testLiteralSubstringMatchSurvivesCrossLanguageVectorDimensionMismatch() async {
        let item = ClipboardItem.text("texto com prompt pronto")
        let provider = DictionaryVectorProvider(vectors: [
            "prompt": [1, 0],
            "texto com prompt pronto": [1, 0, 0]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [(item.id, item.textValue!)])

        let results = await index.search(query: "prompt", allItems: [item])

        XCTAssertEqual(results.map(\.id), [item.id])
    }

    func testLiteralSubstringMatchSurvivesLowSemanticScore() async {
        let item = ClipboardItem.text("prompt pronto")
        let provider = DictionaryVectorProvider(vectors: [
            "prompt": [1, 0],
            "prompt pronto": [0, 1]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [(item.id, item.textValue!)])

        let results = await index.search(query: "prompt", allItems: [item])

        XCTAssertEqual(results.map(\.id), [item.id])
    }

    func testLiteralSubstringMatchSurvivesMissingIndexedVector() async {
        let item = ClipboardItem.text("prompt pronto")
        let provider = DictionaryVectorProvider(vectors: [
            "prompt": [1, 0]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [(item.id, item.textValue!)])

        let results = await index.search(query: "prompt", allItems: [item])

        XCTAssertEqual(results.map(\.id), [item.id])
    }

    func testLiteralSubstringMatchWorksWhenIndexIsEmpty() async {
        let item = ClipboardItem.text("prompt pronto")
        let provider = DictionaryVectorProvider(vectors: [
            "prompt": [1, 0]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        let results = await index.search(query: "prompt", allItems: [item])

        XCTAssertEqual(results.map(\.id), [item.id])
    }

    func testLiteralMatchesRankBeforeSemanticOnlyMatches() async {
        let semanticOnlyItem = ClipboardItem.text("agenda for call")
        let literalItem = ClipboardItem.text("prompt pronto")
        let provider = DictionaryVectorProvider(vectors: [
            "prompt": [1, 0],
            "agenda for call": [0.90, 0.44],
            "prompt pronto": [0.35, 0.94]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [
            (semanticOnlyItem.id, semanticOnlyItem.textValue!),
            (literalItem.id, literalItem.textValue!)
        ])

        let results = await index.search(query: "prompt", allItems: [semanticOnlyItem, literalItem])

        XCTAssertEqual(results.map(\.id), [literalItem.id, semanticOnlyItem.id])
    }

    func testDiacriticInsensitiveLiteralMatchesAreGuaranteed() async {
        let item = ClipboardItem.text("implementação pronta")
        let provider = DictionaryVectorProvider(vectors: [
            "implementacao": [1, 0],
            "implementação pronta": [0, 1]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [(item.id, item.textValue!)])

        let results = await index.search(query: "implementacao", allItems: [item])

        XCTAssertEqual(results.map(\.id), [item.id])
    }

    func testSemanticOnlyMatchStillReturnsWhenAboveThreshold() async {
        let item = ClipboardItem.text("agenda for call")
        let provider = DictionaryVectorProvider(vectors: [
            "meeting": [1, 0],
            "agenda for call": [0.90, 0.44]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [(item.id, item.textValue!)])

        let results = await index.search(query: "meeting", allItems: [item])

        XCTAssertEqual(results.map(\.id), [item.id])
    }

    func testClearRemovesIndex() async {
        let item = ClipboardItem.text("agenda for call")
        let provider = DictionaryVectorProvider(vectors: [
            "meeting": [1, 0],
            "agenda for call": [1, 0]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [(item.id, item.textValue!)])
        await index.clear()

        let results = await index.search(query: "meeting", allItems: [item])

        XCTAssertTrue(results.isEmpty)
    }

    func testRebuildRestoresIndex() async {
        let item = ClipboardItem.text("meeting notes")
        let provider = DictionaryVectorProvider(vectors: [
            "meeting": [1, 0],
            "meeting notes": [1, 0]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.clear()
        await index.rebuild(items: [(item.id, item.textValue!)])

        let results = await index.search(query: "meeting", allItems: [item])

        XCTAssertEqual(results.map(\.id), [item.id])
    }

    func testImageItemsExcludedFromSearch() async {
        let textItem = ClipboardItem.text("meeting notes")
        let imageItem = ClipboardItem.image(.onePixelTestImage())
        let provider = DictionaryVectorProvider(vectors: [
            "meeting": [1, 0],
            "meeting notes": [1, 0]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [(textItem.id, textItem.textValue!)])

        let results = await index.search(query: "meeting", allItems: [imageItem, textItem])

        XCTAssertEqual(results.map(\.id), [textItem.id])
        XCTAssertFalse(results.contains { $0.imageValue != nil })
    }

    func testNilEmbeddingFallback() async {
        let matchingItem = ClipboardItem.text("invoice due tomorrow")
        let nonMatchingItem = ClipboardItem.text("meeting notes")
        let index = SemanticIndex(vectorProvider: CountingNilVectorProvider())

        await index.rebuild(items: [
            (matchingItem.id, matchingItem.textValue!),
            (nonMatchingItem.id, nonMatchingItem.textValue!)
        ])

        let results = await index.search(query: "invoice", allItems: [nonMatchingItem, matchingItem])

        XCTAssertEqual(results.map(\.id), [matchingItem.id])
    }

    func testQueryBelowThresholdReturnsEmpty() async {
        let item = ClipboardItem.text("invoice due tomorrow")
        let provider = DictionaryVectorProvider(vectors: [
            "zzzzz": [1, 0],
            "invoice due tomorrow": [0, 1]
        ])
        let index = SemanticIndex(vectorProvider: provider)

        await index.rebuild(items: [(item.id, item.textValue!)])

        let results = await index.search(query: "zzzzz", allItems: [item])

        XCTAssertTrue(results.isEmpty)
    }
}

private final class DictionaryVectorProvider: SemanticVectorProviding, @unchecked Sendable {
    private let vectors: [String: [Float]]

    init(vectors: [String: [Float]]) {
        self.vectors = vectors
    }

    func vector(for text: String) -> [Float]? {
        vectors[text]
    }
}

private final class CountingNilVectorProvider: SemanticVectorProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock {
            calls
        }
    }

    func vector(for text: String) -> [Float]? {
        lock.withLock {
            calls += 1
        }
        return nil
    }

    func resetCallCount() {
        lock.withLock {
            calls = 0
        }
    }
}
