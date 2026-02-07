import XCTest
@testable import EthscriptionNames

final class EthscriptionNameTests: XCTestCase {

    // MARK: - Parsing Tests

    func testBasicNameParsing() throws {
        let name = try EthscriptionName("alice")
        XCTAssertEqual(name.name, "alice")
        XCTAssertEqual(name.displayName, "alice.eths")
    }

    func testNameWithEthsSuffix() throws {
        let name = try EthscriptionName("bob.eths")
        XCTAssertEqual(name.name, "bob")
        XCTAssertEqual(name.displayName, "bob.eths")
    }

    func testUppercaseNormalization() throws {
        let name = try EthscriptionName("ALICE")
        XCTAssertEqual(name.name, "alice")
    }

    func testMixedCaseNormalization() throws {
        let name = try EthscriptionName("AlIcE.ETHS")
        XCTAssertEqual(name.name, "alice")
    }

    func testWhitespaceTriming() throws {
        let name = try EthscriptionName("  alice  ")
        XCTAssertEqual(name.name, "alice")
    }

    // MARK: - Content URI Tests

    func testContentURI() throws {
        let name = try EthscriptionName("alice")
        XCTAssertEqual(name.contentURI, "data:,alice")
    }

    func testContentURIWithNumbers() throws {
        let name = try EthscriptionName("user123")
        XCTAssertEqual(name.contentURI, "data:,user123")
    }

    // MARK: - Calldata Tests

    func testCalldata() throws {
        let name = try EthscriptionName("hi")
        // "data:,hi" in hex
        // d=64, a=61, t=74, a=61, :=3a, ,=2c, h=68, i=69
        XCTAssertEqual(name.calldata, "0x646174613a2c6869")
    }

    func testCalldataFormat() throws {
        let name = try EthscriptionName("test")
        XCTAssertTrue(name.calldata.hasPrefix("0x"))
        XCTAssertTrue(name.calldata.count > 2)
        // Should be even length (hex pairs)
        XCTAssertEqual((name.calldata.count - 2) % 2, 0)
    }

    // MARK: - Content Hash Tests

    func testContentHashFormat() throws {
        let name = try EthscriptionName("alice")
        XCTAssertTrue(name.contentHash.hasPrefix("0x"))
        // SHA-256 hash = 32 bytes = 64 hex chars + "0x" prefix
        XCTAssertEqual(name.contentHash.count, 66)
    }

    func testContentHashConsistency() throws {
        // Same name should always produce same hash
        let name1 = try EthscriptionName("test")
        let name2 = try EthscriptionName("TEST")
        XCTAssertEqual(name1.contentHash, name2.contentHash)
    }

    func testDifferentNamesHaveDifferentHashes() throws {
        let name1 = try EthscriptionName("alice")
        let name2 = try EthscriptionName("bob")
        XCTAssertNotEqual(name1.contentHash, name2.contentHash)
    }

    // MARK: - Validation Tests

    func testValidNames() {
        XCTAssertTrue(EthscriptionName.isValid("alice"))
        XCTAssertTrue(EthscriptionName.isValid("bob123"))
        XCTAssertTrue(EthscriptionName.isValid("my-name"))
        XCTAssertTrue(EthscriptionName.isValid("user_1"))
        XCTAssertTrue(EthscriptionName.isValid("a.b.c"))
        XCTAssertTrue(EthscriptionName.isValid("x"))
        XCTAssertTrue(EthscriptionName.isValid("alice.eths"))
    }

    func testInvalidNames() {
        XCTAssertFalse(EthscriptionName.isValid(""))
        XCTAssertFalse(EthscriptionName.isValid("   "))
        XCTAssertFalse(EthscriptionName.isValid("alice bob"))  // space
        XCTAssertFalse(EthscriptionName.isValid("alice!"))     // special char
        XCTAssertFalse(EthscriptionName.isValid("@alice"))     // special char
        XCTAssertFalse(EthscriptionName.isValid("-alice"))     // starts with hyphen
        XCTAssertFalse(EthscriptionName.isValid("alice-"))     // ends with hyphen
    }

    func testLongName() {
        let longName = String(repeating: "a", count: 64)
        XCTAssertTrue(EthscriptionName.isValid(longName))

        let tooLong = String(repeating: "a", count: 65)
        XCTAssertFalse(EthscriptionName.isValid(tooLong))
    }

    // MARK: - Error Tests

    func testEmptyNameThrows() {
        XCTAssertThrowsError(try EthscriptionName("")) { error in
            guard let nameError = error as? EthscriptionNameError else {
                XCTFail("Expected EthscriptionNameError")
                return
            }
            if case .emptyName = nameError {
                // Expected
            } else {
                XCTFail("Expected emptyName error")
            }
        }
    }

    func testInvalidFormatThrows() {
        XCTAssertThrowsError(try EthscriptionName("alice bob")) { error in
            guard let nameError = error as? EthscriptionNameError else {
                XCTFail("Expected EthscriptionNameError")
                return
            }
            if case .invalidFormat = nameError {
                // Expected
            } else {
                XCTFail("Expected invalidFormat error")
            }
        }
    }

    // MARK: - Codable Tests

    func testEncode() throws {
        let name = try EthscriptionName("alice")
        let encoder = JSONEncoder()
        let data = try encoder.encode(name)
        let json = String(data: data, encoding: .utf8)
        XCTAssertEqual(json, "\"alice\"")
    }

    func testDecode() throws {
        let json = "\"bob\""
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let name = try decoder.decode(EthscriptionName.self, from: data)
        XCTAssertEqual(name.name, "bob")
    }

    // MARK: - Hashable Tests

    func testHashable() throws {
        let name1 = try EthscriptionName("alice")
        let name2 = try EthscriptionName("ALICE")
        let name3 = try EthscriptionName("bob")

        var set = Set<EthscriptionName>()
        set.insert(name1)
        set.insert(name2)
        set.insert(name3)

        // name1 and name2 are the same after normalization
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - String Extension Tests

    func testStringExtension() {
        XCTAssertTrue("alice".isValidEthscriptionName)
        XCTAssertFalse("alice bob".isValidEthscriptionName)

        XCTAssertNotNil("alice".asEthscriptionName)
        XCTAssertNil("".asEthscriptionName)
    }

    func testIsEthereumAddress() {
        XCTAssertTrue("0x1234567890123456789012345678901234567890".isEthereumAddress)
        XCTAssertTrue("0xABCDEF0123456789ABCDEF0123456789ABCDEF01".isEthereumAddress)
        XCTAssertFalse("alice".isEthereumAddress)
        XCTAssertFalse("0x123".isEthereumAddress)
        XCTAssertFalse("1234567890123456789012345678901234567890".isEthereumAddress)
    }
}
