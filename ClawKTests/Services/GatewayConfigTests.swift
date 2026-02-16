import XCTest
@testable import ClawK

final class GatewayConfigTests: XCTestCase {

    private let config = GatewayConfig.shared

    // Save/restore state across tests to avoid polluting the singleton
    private var savedCustomURL: String = ""
    private var savedStoredToken: String = ""

    override func setUp() {
        super.setUp()
        savedCustomURL = config.customURL
        savedStoredToken = config.storedToken
    }

    override func tearDown() {
        config.customURL = savedCustomURL
        config.storedToken = savedStoredToken
        super.tearDown()
    }

    // MARK: - defaultURL

    func testDefaultURLFormat() {
        let url = config.defaultURL
        XCTAssertTrue(url.hasPrefix("http://"))
        XCTAssertTrue(url.contains("127.0.0.1"))
    }

    // MARK: - baseURL

    func testBaseURLUsesDefaultWhenCustomEmpty() {
        config.customURL = ""
        XCTAssertEqual(config.baseURL, config.defaultURL)
    }

    func testBaseURLUsesCustomWhenSet() {
        config.customURL = "http://192.168.1.100:9000"
        XCTAssertEqual(config.baseURL, "http://192.168.1.100:9000")
    }

    func testBaseURLTrimsWhitespace() {
        config.customURL = "  "
        XCTAssertEqual(config.baseURL, config.defaultURL)
    }

    // MARK: - isUsingCustomURL

    func testIsUsingCustomURLFalseWhenEmpty() {
        config.customURL = ""
        XCTAssertFalse(config.isUsingCustomURL)
    }

    func testIsUsingCustomURLFalseWhenWhitespace() {
        config.customURL = "   "
        XCTAssertFalse(config.isUsingCustomURL)
    }

    func testIsUsingCustomURLTrue() {
        config.customURL = "http://custom:8080"
        XCTAssertTrue(config.isUsingCustomURL)
    }

    // MARK: - hasToken

    func testHasTokenFalseWhenEmpty() {
        config.storedToken = ""
        XCTAssertFalse(config.hasToken)
    }

    func testHasTokenFalseWhenWhitespace() {
        config.storedToken = "   "
        XCTAssertFalse(config.hasToken)
    }

    func testHasTokenTrue() {
        config.storedToken = "my-token-123"
        XCTAssertTrue(config.hasToken)
    }

    // MARK: - token

    func testTokenNilWhenEmpty() {
        config.storedToken = ""
        XCTAssertNil(config.token)
    }

    func testTokenNilWhenWhitespace() {
        config.storedToken = "  \n  "
        XCTAssertNil(config.token)
    }

    func testTokenTrimsWhitespace() {
        config.storedToken = "  my-token  "
        XCTAssertEqual(config.token, "my-token")
    }

    func testTokenReturnsValue() {
        config.storedToken = "valid-token"
        XCTAssertEqual(config.token, "valid-token")
    }
}
