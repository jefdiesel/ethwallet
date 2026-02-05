import XCTest
@testable import EthWalletCore

final class EthWalletTests: XCTestCase {

    // MARK: - HexUtils Tests

    func testHexEncode() {
        let data = Data([0x01, 0x02, 0x03, 0xAB, 0xCD, 0xEF])
        let hex = HexUtils.encode(data)
        XCTAssertEqual(hex, "0x010203abcdef")
    }

    func testHexDecode() {
        let hex = "0x010203abcdef"
        let data = HexUtils.decode(hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(data, Data([0x01, 0x02, 0x03, 0xAB, 0xCD, 0xEF]))
    }

    func testHexDecodeWithoutPrefix() {
        let hex = "abcdef"
        let data = HexUtils.decode(hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(data, Data([0xAB, 0xCD, 0xEF]))
    }

    func testIsValidAddress() {
        XCTAssertTrue(HexUtils.isValidAddress("0x1234567890abcdef1234567890abcdef12345678"))
        XCTAssertTrue(HexUtils.isValidAddress("0xABCDEF1234567890ABCDEF1234567890ABCDEF12"))
        XCTAssertFalse(HexUtils.isValidAddress("1234567890abcdef1234567890abcdef12345678")) // No 0x prefix
        XCTAssertFalse(HexUtils.isValidAddress("0x1234567890abcdef1234567890abcdef1234567")) // Too short
        XCTAssertFalse(HexUtils.isValidAddress("0x1234567890abcdef1234567890abcdef123456789")) // Too long
        XCTAssertFalse(HexUtils.isValidAddress("0x1234567890ghijkl1234567890abcdef12345678")) // Invalid chars
    }

    func testIsValidTxHash() {
        XCTAssertTrue(HexUtils.isValidTxHash("0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"))
        XCTAssertFalse(HexUtils.isValidTxHash("0x1234567890abcdef1234567890abcdef12345678")) // Too short
    }

    func testPadLeft() {
        let result = HexUtils.padLeft("abc", toBytes: 4)
        XCTAssertEqual(result, "0x00000abc")
    }

    // MARK: - DataURIEncoder Tests

    func testDataURIEncode() throws {
        let content = "Hello, World!".data(using: .utf8)!
        let dataURI = try DataURIEncoder.encode(content: content, mimeType: "text/plain")
        XCTAssertTrue(dataURI.hasPrefix("data:text/plain;base64,"))
    }

    func testDataURIEncodeWithESIP6() throws {
        let content = "Test".data(using: .utf8)!
        let dataURI = try DataURIEncoder.encode(content: content, mimeType: "text/plain", allowDuplicate: true)
        XCTAssertTrue(dataURI.contains("rule=esip6"))
    }

    func testDataURIParse() {
        let dataURI = "data:text/plain;base64,SGVsbG8sIFdvcmxkIQ=="
        let components = DataURIEncoder.parse(dataURI)

        XCTAssertNotNil(components)
        XCTAssertEqual(components?.mimeType, "text/plain")
        XCTAssertTrue(components?.isBase64 ?? false)
        XCTAssertEqual(String(data: components?.data ?? Data(), encoding: .utf8), "Hello, World!")
    }

    func testDataURIParseWithESIP6() {
        let dataURI = "data:text/plain;rule=esip6;base64,SGVsbG8="
        let components = DataURIEncoder.parse(dataURI)

        XCTAssertNotNil(components)
        XCTAssertTrue(components?.isESIP6 ?? false)
    }

    // MARK: - ABIEncoder Tests

    func testABIEncodeAddress() {
        let encoded = ABIEncoder.encodeParameter(.address("0x1234567890abcdef1234567890abcdef12345678"))
        XCTAssertEqual(encoded.count, 64)
        XCTAssertTrue(encoded.hasSuffix("1234567890abcdef1234567890abcdef12345678"))
    }

    func testABIEncodeUInt256() {
        let encoded = ABIEncoder.encodeParameter(.uint256(256))
        XCTAssertEqual(encoded.count, 64)
        XCTAssertEqual(encoded, "0000000000000000000000000000000000000000000000000000000000000100")
    }

    func testABIEncodeBool() {
        let encodedTrue = ABIEncoder.encodeParameter(.bool(true))
        let encodedFalse = ABIEncoder.encodeParameter(.bool(false))

        XCTAssertTrue(encodedTrue.hasSuffix("1"))
        XCTAssertTrue(encodedFalse.hasSuffix("0"))
    }

    func testABIDecodeAddress() {
        let hex = "0x0000000000000000000000001234567890abcdef1234567890abcdef12345678"
        let address = ABIEncoder.decodeAddress(hex)

        XCTAssertEqual(address, "0x1234567890abcdef1234567890abcdef12345678")
    }

    func testABIDecodeUInt256() {
        let hex = "0x0000000000000000000000000000000000000000000000000000000000000100"
        let value = ABIEncoder.decodeUInt256(hex)

        XCTAssertEqual(value, 256)
    }

    // MARK: - Network Tests

    func testNetworkDefaults() {
        XCTAssertEqual(Network.ethereum.id, 1)
        XCTAssertEqual(Network.sepolia.id, 11155111)
        XCTAssertEqual(Network.base.id, 8453)

        XCTAssertFalse(Network.ethereum.isTestnet)
        XCTAssertTrue(Network.sepolia.isTestnet)
        XCTAssertFalse(Network.base.isTestnet)
    }

    func testNetworkExplorerURLs() {
        let txHash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        let txURL = Network.ethereum.explorerTransactionURL(txHash)

        XCTAssertNotNil(txURL)
        XCTAssertTrue(txURL?.absoluteString.contains("etherscan.io") ?? false)
        XCTAssertTrue(txURL?.absoluteString.contains(txHash) ?? false)
    }

    // MARK: - Account Tests

    func testAccountDerivationPath() {
        let account0 = Account(index: 0, address: "0x...")
        let account5 = Account(index: 5, address: "0x...")

        XCTAssertEqual(account0.derivationPath, "m/44'/60'/0'/0/0")
        XCTAssertEqual(account5.derivationPath, "m/44'/60'/0'/0/5")
    }

    func testAccountShortAddress() {
        let account = Account(index: 0, address: "0x1234567890abcdef1234567890abcdef12345678")
        XCTAssertEqual(account.shortAddress, "0x1234...5678")
    }

    // MARK: - Ethscription Tests

    func testEthscriptionTransferCalldata() {
        let id = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        let transfer = EthscriptionTransfer.single(ethscriptionId: id, to: "0x...")

        XCTAssertEqual(transfer.calldata, id)
    }

    func testEthscriptionBulkTransferCalldata() {
        let ids = [
            "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
            "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"
        ]
        let transfer = EthscriptionTransfer.bulk(ethscriptionIds: ids, to: "0x...")

        let expected = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"
        XCTAssertEqual(transfer.calldata, expected)
    }

    // MARK: - ContentValidation Tests

    func testContentSizeLimit() {
        let maxSize = EthscriptionService.maxContentSize
        XCTAssertEqual(maxSize, 90 * 1024) // 90KB
    }

    // MARK: - TokenMetadata Tests

    func testAttributeValueDecoding() throws {
        let stringJSON = #""test value""#.data(using: .utf8)!
        let numberJSON = "42.5".data(using: .utf8)!
        let boolJSON = "true".data(using: .utf8)!

        let stringValue = try JSONDecoder().decode(AttributeValue.self, from: stringJSON)
        let numberValue = try JSONDecoder().decode(AttributeValue.self, from: numberJSON)
        let boolValue = try JSONDecoder().decode(AttributeValue.self, from: boolJSON)

        if case .string(let str) = stringValue {
            XCTAssertEqual(str, "test value")
        } else {
            XCTFail("Expected string value")
        }

        if case .number(let num) = numberValue {
            XCTAssertEqual(num, 42.5)
        } else {
            XCTFail("Expected number value")
        }

        if case .boolean(let bool) = boolValue {
            XCTAssertTrue(bool)
        } else {
            XCTFail("Expected boolean value")
        }
    }

    func testAttributeValueDisplayValue() {
        XCTAssertEqual(AttributeValue.string("test").displayValue, "test")
        XCTAssertEqual(AttributeValue.number(42.5).displayValue, "42.50")
        XCTAssertEqual(AttributeValue.boolean(true).displayValue, "Yes")
        XCTAssertEqual(AttributeValue.boolean(false).displayValue, "No")
    }
}
