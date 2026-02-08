//
//  SentenceExtractionTests.swift
//  ClawKTests
//
//  Tests for NLTokenizer-based sentence extraction used in TTS streaming
//

import XCTest
import NaturalLanguage
// Source files compiled directly into test target

final class SentenceExtractionTests: XCTestCase {

    // MARK: - NLTokenizer Sentence Splitting

    /// Verifies NLTokenizer correctly splits sentences — the same approach used
    /// in TalkConversationManager.extractAndEnqueueSentences
    func testSingleSentence() {
        let sentences = extractSentences("Hello world.")
        XCTAssertEqual(sentences, ["Hello world."])
    }

    func testMultipleSentences() {
        let sentences = extractSentences("First sentence. Second sentence. Third sentence.")
        XCTAssertEqual(sentences.count, 3)
        XCTAssertEqual(sentences[0], "First sentence.")
        XCTAssertEqual(sentences[1], "Second sentence.")
        XCTAssertEqual(sentences[2], "Third sentence.")
    }

    func testSentenceWithQuestion() {
        let sentences = extractSentences("How are you? I'm fine. Thanks for asking!")
        XCTAssertEqual(sentences.count, 3)
        XCTAssertTrue(sentences[0].contains("How are you"))
    }

    func testEmptyString() {
        let sentences = extractSentences("")
        XCTAssertEqual(sentences.count, 0)
    }

    func testIncompleteSentence() {
        // No trailing period — NLTokenizer may treat it as one sentence
        let sentences = extractSentences("Hello world")
        XCTAssertTrue(sentences.count >= 1)
    }

    func testSentenceWithNewlines() {
        let sentences = extractSentences("First line.\nSecond line.\nThird line.")
        XCTAssertEqual(sentences.count, 3)
    }

    func testLongParagraph() {
        let text = "The quick brown fox jumps over the lazy dog. " +
                   "Pack my box with five dozen liquor jugs. " +
                   "How vexingly quick daft zebras jump."
        let sentences = extractSentences(text)
        XCTAssertEqual(sentences.count, 3)
    }

    // MARK: - Streaming Simulation

    /// Simulates the incremental sentence extraction used during streaming.
    /// Only "complete" sentences (where the tokenizer sees a boundary before the end
    /// of the text) should be enqueued.
    func testStreamingExtractionOnlyCompleteSentences() {
        // Simulate partial stream: "Hello world. This is"
        // Should only extract "Hello world." — the rest is incomplete
        let text = "Hello world. This is"
        let completeSentences = extractCompleteSentences(text)
        XCTAssertEqual(completeSentences.count, 1)
        XCTAssertEqual(completeSentences[0], "Hello world.")
    }

    func testStreamingExtractionTwoComplete() {
        let text = "First. Second. Still typing"
        let completeSentences = extractCompleteSentences(text)
        XCTAssertEqual(completeSentences.count, 2)
        XCTAssertEqual(completeSentences[0], "First.")
        XCTAssertEqual(completeSentences[1], "Second.")
    }

    func testStreamingExtractionAllComplete() {
        let text = "First. Second."
        let completeSentences = extractCompleteSentences(text)
        // Both are complete since they end at the boundary
        XCTAssertTrue(completeSentences.count >= 1)
    }

    // MARK: - Helpers

    /// Extract all sentences from text using NLTokenizer
    private func extractSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                result.append(sentence)
            }
            return true
        }
        return result
    }

    /// Extract only "complete" sentences — those where the tokenizer boundary
    /// is before the end of the full text (matching TalkConversationManager logic)
    private func extractCompleteSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty && range.upperBound < text.endIndex {
                result.append(sentence)
            }
            return true
        }
        return result
    }
}
