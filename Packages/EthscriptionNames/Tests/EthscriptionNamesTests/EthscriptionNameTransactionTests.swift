import XCTest
@testable import EthscriptionNames

final class EthscriptionNameTransactionTests: XCTestCase {

    let testAddress = "0x1234567890123456789012345678901234567890"
    let recipientAddress = "0xabcdef0123456789abcdef0123456789abcdef01"
    let testTxHash = "0x" + String(repeating: "a", count: 64)

    // MARK: - Claim Transaction Tests

    func testClaimTransaction() throws {
        let tx = try EthscriptionNameTransaction.claim("alice", from: testAddress)

        XCTAssertEqual(tx.to, testAddress.lowercased())
        XCTAssertEqual(tx.value, "0x0")
        XCTAssertTrue(tx.calldata.hasPrefix("0x"))
    }

    func testClaimTransactionCalldata() throws {
        let tx = try EthscriptionNameTransaction.claim("hi", from: testAddress)

        // "data:,hi" = 0x646174613a2c6869
        XCTAssertEqual(tx.calldata, "0x646174613a2c6869")
    }

    func testClaimSameAddressForSenderAndRecipient() throws {
        let tx = try EthscriptionNameTransaction.claim("test", from: testAddress)

        // For claiming, transaction goes to yourself
        XCTAssertEqual(tx.to, testAddress.lowercased())
    }

    // MARK: - Transfer Transaction Tests

    func testTransferTransaction() {
        let tx = EthscriptionNameTransaction.transfer(
            ethscriptionId: testTxHash,
            to: recipientAddress
        )

        XCTAssertEqual(tx.to, recipientAddress.lowercased())
        XCTAssertEqual(tx.value, "0x0")
        XCTAssertEqual(tx.calldata, testTxHash.lowercased())
    }

    func testTransferAdds0xPrefix() {
        let hashWithout0x = String(repeating: "b", count: 64)
        let tx = EthscriptionNameTransaction.transfer(
            ethscriptionId: hashWithout0x,
            to: recipientAddress
        )

        XCTAssertTrue(tx.calldata.hasPrefix("0x"))
    }

    // MARK: - Bulk Transfer Tests

    func testBulkTransfer() {
        let hash1 = "0x" + String(repeating: "1", count: 64)
        let hash2 = "0x" + String(repeating: "2", count: 64)
        let hash3 = "0x" + String(repeating: "3", count: 64)

        let tx = EthscriptionNameTransaction.bulkTransfer(
            ethscriptionIds: [hash1, hash2, hash3],
            to: recipientAddress
        )

        XCTAssertEqual(tx.to, recipientAddress.lowercased())

        // ESIP-5: Concatenated hashes without individual 0x prefixes
        let expectedCalldata = "0x" +
            String(repeating: "1", count: 64) +
            String(repeating: "2", count: 64) +
            String(repeating: "3", count: 64)
        XCTAssertEqual(tx.calldata, expectedCalldata)
    }

    func testBulkTransferLength() {
        let hashes = (0..<5).map { _ in "0x" + String(repeating: "a", count: 64) }
        let tx = EthscriptionNameTransaction.bulkTransfer(
            ethscriptionIds: hashes,
            to: recipientAddress
        )

        // 5 hashes * 64 chars each + "0x" prefix = 322 chars
        XCTAssertEqual(tx.calldata.count, 322)
    }

    // MARK: - Validation Tests

    func testIsValidAddress() {
        XCTAssertTrue(EthscriptionNameTransaction.isValidAddress(testAddress))
        XCTAssertTrue(EthscriptionNameTransaction.isValidAddress(testAddress.uppercased()))
        XCTAssertFalse(EthscriptionNameTransaction.isValidAddress("0x123"))
        XCTAssertFalse(EthscriptionNameTransaction.isValidAddress("alice"))
        XCTAssertFalse(EthscriptionNameTransaction.isValidAddress(""))
    }

    func testIsValidTransactionHash() {
        XCTAssertTrue(EthscriptionNameTransaction.isValidTransactionHash(testTxHash))
        XCTAssertFalse(EthscriptionNameTransaction.isValidTransactionHash("0x123"))
        XCTAssertFalse(EthscriptionNameTransaction.isValidTransactionHash(testAddress))
        XCTAssertFalse(EthscriptionNameTransaction.isValidTransactionHash(""))
    }

    // MARK: - Gas Estimation Tests

    func testEstimatedGasLimit() throws {
        let tx = try EthscriptionNameTransaction.claim("test", from: testAddress)

        // Should be at least base gas (21000)
        XCTAssertGreaterThan(tx.estimatedGasLimit, 21000)
    }

    func testLongerCalldataHigherGas() throws {
        let shortTx = try EthscriptionNameTransaction.claim("a", from: testAddress)
        let longTx = try EthscriptionNameTransaction.claim("this-is-a-very-long-name", from: testAddress)

        XCTAssertGreaterThan(longTx.estimatedGasLimit, shortTx.estimatedGasLimit)
    }

    func testEstimateCost() throws {
        let tx = try EthscriptionNameTransaction.claim("test", from: testAddress)
        let gasPrice: UInt64 = 30_000_000_000  // 30 gwei

        let cost = tx.estimateCost(gasPriceWei: gasPrice)
        XCTAssertGreaterThan(cost, 0)
        XCTAssertEqual(cost, tx.estimatedGasLimit * gasPrice)
    }

    // MARK: - Description Tests

    func testClaimDescription() throws {
        let tx = try EthscriptionNameTransaction.claim("alice", from: testAddress)
        let desc = tx.description

        XCTAssertTrue(desc.contains("alice.eths"))
        XCTAssertTrue(desc.contains("Claim"))
    }

    func testTransferDescription() {
        let tx = EthscriptionNameTransaction.transfer(
            ethscriptionId: testTxHash,
            to: recipientAddress
        )
        let desc = tx.description

        XCTAssertTrue(desc.contains("Transfer"))
        XCTAssertTrue(desc.contains("..."))  // Truncated addresses
    }
}
