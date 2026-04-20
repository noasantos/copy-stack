import Accelerate
import Foundation
import NaturalLanguage
import os

private let logger = Logger(subsystem: "com.startapse.ClipStack", category: "semantic-index")

protocol SemanticIndexing: Sendable {
    func rebuild(items: [(id: UUID, text: String)]) async
    func add(id: UUID, text: String) async
    func remove(id: UUID) async
    func clear() async
    func search(query: String, allItems: [ClipboardItem]) async -> [ClipboardItem]
}

protocol SemanticVectorProviding: Sendable {
    func vector(for text: String) -> [Float]?
}

final class NaturalLanguageSentenceVectorProvider: SemanticVectorProviding, @unchecked Sendable {
    private var didLoadEmbeddings = false
    private var englishEmbedding: NLEmbedding?
    private var portugueseEmbedding: NLEmbedding?

    func vector(for text: String) -> [Float]? {
        loadEmbeddingsIfNeeded()
        let embedding = preferredEmbedding(for: text)
        return embedding?.vector(for: text)?.map { Float($0) }
    }

    private func loadEmbeddingsIfNeeded() {
        guard !didLoadEmbeddings else {
            return
        }

        englishEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        portugueseEmbedding = NLEmbedding.sentenceEmbedding(for: .portuguese)
        didLoadEmbeddings = true

        if englishEmbedding == nil && portugueseEmbedding == nil {
            logger.warning("ClipStack semantic search unavailable: no sentence embeddings found")
        }
    }

    private func preferredEmbedding(for text: String) -> NLEmbedding? {
        if NLLanguageRecognizer.dominantLanguage(for: text) == .portuguese,
           let portugueseEmbedding {
            return portugueseEmbedding
        }

        return englishEmbedding ?? portugueseEmbedding
    }
}

actor SemanticIndex: SemanticIndexing {
    private var vectors: [UUID: [Float]] = [:]
    private let vectorProvider: any SemanticVectorProviding
    private let minimumScore: Float
    private let substringBoost: Float
    private let maxResults: Int

    init(
        vectorProvider: any SemanticVectorProviding = NaturalLanguageSentenceVectorProvider(),
        minimumScore: Float = 0.30,
        substringBoost: Float = 0.15,
        maxResults: Int = 50
    ) {
        self.vectorProvider = vectorProvider
        self.minimumScore = minimumScore
        self.substringBoost = substringBoost
        self.maxResults = maxResults
    }

    func rebuild(items: [(id: UUID, text: String)]) async {
        vectors.removeAll(keepingCapacity: true)

        for item in items {
            guard let vector = vectorProvider.vector(for: item.text) else {
                continue
            }

            vectors[item.id] = vector
        }
    }

    func add(id: UUID, text: String) async {
        guard let vector = vectorProvider.vector(for: text) else {
            vectors.removeValue(forKey: id)
            return
        }

        vectors[id] = vector
    }

    func remove(id: UUID) async {
        vectors.removeValue(forKey: id)
    }

    func clear() async {
        vectors.removeAll(keepingCapacity: true)
    }

    func search(query: String, allItems: [ClipboardItem]) async -> [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let literalMatches = substringMatches(query: trimmedQuery, allItems: allItems)
        guard literalMatches.count < maxResults else {
            return Array(literalMatches.prefix(maxResults))
        }

        guard trimmedQuery.count >= 3 else {
            return literalMatches
        }

        guard let queryVector = vectorProvider.vector(for: trimmedQuery) else {
            return literalMatches
        }

        var itemsByID: [UUID: ClipboardItem] = [:]
        var orderByID: [UUID: Int] = [:]
        for (offset, item) in allItems.enumerated() where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
            orderByID[item.id] = offset
        }
        let literalMatchIDs = Set(literalMatches.map(\.id))

        let scoredItems: [(item: ClipboardItem, score: Float)] = vectors.compactMap { id, vector in
            guard !literalMatchIDs.contains(id),
                  let item = itemsByID[id],
                  let score = cosineSimilarity(queryVector, vector) else {
                return nil
            }

            guard score >= minimumScore else {
                return nil
            }

            return (item, score)
        }

        let semanticMatches = scoredItems
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return (orderByID[lhs.item.id] ?? Int.max) < (orderByID[rhs.item.id] ?? Int.max)
                }

                return lhs.score > rhs.score
            }
            .map(\.item)

        return Array((literalMatches + semanticMatches).prefix(maxResults))
    }

    private func substringMatches(query: String, allItems: [ClipboardItem]) -> [ClipboardItem] {
        var seenIDs = Set<UUID>()

        return allItems.filter { item in
            guard !seenIDs.contains(item.id),
                  containsSubstring(item, query: query) else {
                return false
            }

            seenIDs.insert(item.id)
            return true
        }
    }

    private func containsSubstring(_ item: ClipboardItem, query: String) -> Bool {
        item.textValue?.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return nil
        }

        let count = vDSP_Length(lhs.count)
        var dotProduct: Float = 0
        var lhsSumOfSquares: Float = 0
        var rhsSumOfSquares: Float = 0

        vDSP_dotpr(lhs, 1, rhs, 1, &dotProduct, count)
        vDSP_svesq(lhs, 1, &lhsSumOfSquares, count)
        vDSP_svesq(rhs, 1, &rhsSumOfSquares, count)

        let denominator = sqrt(lhsSumOfSquares) * sqrt(rhsSumOfSquares)
        guard denominator > 0 else {
            return nil
        }

        return dotProduct / denominator
    }
}
