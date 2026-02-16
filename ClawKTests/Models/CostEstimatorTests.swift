import XCTest
@testable import ClawK

final class CostEstimatorTests: XCTestCase {

    private var savedOutputRatio: Double = 0.30

    override func setUp() {
        super.setUp()
        savedOutputRatio = CostEstimator.outputRatio
        CostEstimator.outputRatio = 0.30 // Reset to default for tests
    }

    override func tearDown() {
        CostEstimator.outputRatio = savedOutputRatio
        super.tearDown()
    }

    // MARK: - estimateCost

    func testEstimateCostSonnet() {
        // Sonnet: input $3/1M, output $15/1M
        // 1_000_000 tokens, 30% output ratio
        // Input: 700K * $3/1M = $2.10
        // Output: 300K * $15/1M = $4.50
        // Total = $6.60
        let cost = CostEstimator.estimateCost(model: "sonnet", totalTokens: 1_000_000)
        XCTAssertEqual(cost, 6.60, accuracy: 0.01)
    }

    func testEstimateCostOpus() {
        // Opus: input $15/1M, output $75/1M
        // 1_000_000 tokens, 30% output ratio
        // Input: 700K * $15/1M = $10.50
        // Output: 300K * $75/1M = $22.50
        // Total = $33.00
        let cost = CostEstimator.estimateCost(model: "opus", totalTokens: 1_000_000)
        XCTAssertEqual(cost, 33.00, accuracy: 0.01)
    }

    func testEstimateCostHaiku() {
        // Haiku: input $0.25/1M, output $1.25/1M
        // 1_000_000 tokens, 30% output ratio
        // Input: 700K * $0.25/1M = $0.175
        // Output: 300K * $1.25/1M = $0.375
        // Total = $0.55
        let cost = CostEstimator.estimateCost(model: "haiku", totalTokens: 1_000_000)
        XCTAssertEqual(cost, 0.55, accuracy: 0.01)
    }

    func testEstimateCostNilModelDefaultsToSonnet() {
        let costNil = CostEstimator.estimateCost(model: nil, totalTokens: 1_000_000)
        let costSonnet = CostEstimator.estimateCost(model: "sonnet", totalTokens: 1_000_000)
        XCTAssertEqual(costNil, costSonnet, accuracy: 0.001)
    }

    func testEstimateCostFullModelPath() {
        // "anthropic/claude-sonnet-4-5" should normalize to sonnet pricing
        let costFullPath = CostEstimator.estimateCost(model: "anthropic/claude-sonnet-4-5", totalTokens: 1_000_000)
        let costSonnet = CostEstimator.estimateCost(model: "sonnet", totalTokens: 1_000_000)
        XCTAssertEqual(costFullPath, costSonnet, accuracy: 0.001)
    }

    func testEstimateCostZeroTokens() {
        let cost = CostEstimator.estimateCost(model: "opus", totalTokens: 0)
        XCTAssertEqual(cost, 0.0, accuracy: 0.001)
    }

    // MARK: - formatCost

    func testFormatCostBelowOneCent() {
        XCTAssertEqual(CostEstimator.formatCost(0.001), "<$0.01")
        XCTAssertEqual(CostEstimator.formatCost(0.0), "<$0.01")
    }

    func testFormatCostBelowOneDollar() {
        XCTAssertEqual(CostEstimator.formatCost(0.55), "$0.55")
    }

    func testFormatCostBelowTenDollars() {
        XCTAssertEqual(CostEstimator.formatCost(6.60), "$6.60")
    }

    func testFormatCostAboveTenDollars() {
        XCTAssertEqual(CostEstimator.formatCost(33.0), "$33")
    }

    func testFormatCostWithDisclaimer() {
        let result = CostEstimator.formatCost(5.0, includeDisclaimer: true)
        XCTAssertTrue(result.hasSuffix("*"))
    }

    func testFormatCostWithoutDisclaimer() {
        let result = CostEstimator.formatCost(5.0, includeDisclaimer: false)
        XCTAssertFalse(result.hasSuffix("*"))
    }

    // MARK: - getModelTier

    func testGetModelTierOpus() {
        XCTAssertEqual(CostEstimator.getModelTier("claude-opus-4"), "💎 Opus")
    }

    func testGetModelTierSonnet() {
        XCTAssertEqual(CostEstimator.getModelTier("claude-sonnet-4"), "✨ Sonnet")
    }

    func testGetModelTierHaiku() {
        XCTAssertEqual(CostEstimator.getModelTier("claude-haiku-4"), "⚡ Haiku")
    }

    func testGetModelTierNilDefaultsToSonnet() {
        XCTAssertEqual(CostEstimator.getModelTier(nil), "✨ Sonnet")
    }

    func testGetModelTierUnknownDefaultsToSonnet() {
        XCTAssertEqual(CostEstimator.getModelTier("gpt-4"), "✨ Sonnet")
    }

    // MARK: - outputRatio

    func testOutputRatioAffectsCost() {
        CostEstimator.outputRatio = 0.20
        let cost20 = CostEstimator.estimateCost(model: "sonnet", totalTokens: 1_000_000)

        CostEstimator.outputRatio = 0.40
        let cost40 = CostEstimator.estimateCost(model: "sonnet", totalTokens: 1_000_000)

        // Higher output ratio = higher cost (since output is more expensive)
        XCTAssertGreaterThan(cost40, cost20)
    }

    func testOutputRatioLabel() {
        CostEstimator.outputRatio = 0.30
        XCTAssertEqual(CostEstimator.outputRatioLabel, "30%")
    }
}
