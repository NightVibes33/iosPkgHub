import XCTest
@testable import PKGSender

final class ByteRangeCoverageTests: XCTestCase {
    func testOutOfOrderRangesReachFullCoverageOnlyWhenGapsAreFilled() {
        var coverage = ByteRangeCoverage()

        coverage.add(start: 60, length: 40, limit: 100)
        XCTAssertEqual(coverage.coveredBytes, 40)

        coverage.add(start: 0, length: 30, limit: 100)
        XCTAssertEqual(coverage.coveredBytes, 70)

        coverage.add(start: 30, length: 30, limit: 100)
        XCTAssertEqual(coverage.coveredBytes, 100)
    }

    func testOverlappingAndDuplicateRangesAreCountedOnce() {
        var coverage = ByteRangeCoverage()

        coverage.add(start: 0, length: 40, limit: 100)
        XCTAssertEqual(coverage.coveredBytes, 40)

        coverage.add(start: 20, length: 30, limit: 100)
        XCTAssertEqual(coverage.coveredBytes, 50)

        coverage.add(start: 20, length: 30, limit: 100)
        XCTAssertEqual(coverage.coveredBytes, 50)

        coverage.add(start: 0, length: 40, limit: 100)
        XCTAssertEqual(coverage.coveredBytes, 50)

        coverage.add(start: 50, length: 50, limit: 100)
        XCTAssertEqual(coverage.coveredBytes, 100)
    }

    func testRangesAreClampedToFileSizeAndIgnoreOutOfBoundsReads() {
        var coverage = ByteRangeCoverage()

        coverage.add(start: 80, length: 100, limit: 100)
        coverage.add(start: 100, length: 20, limit: 100)
        coverage.add(start: 10, length: 0, limit: 100)

        XCTAssertEqual(coverage.coveredBytes, 20)
    }

    func testResetClearsAllCoverage() {
        var coverage = ByteRangeCoverage()
        coverage.add(start: 0, length: 50, limit: 100)
        coverage.reset()

        XCTAssertEqual(coverage.coveredBytes, 0)
        coverage.add(start: 50, length: 50, limit: 100)
        XCTAssertEqual(coverage.coveredBytes, 50)
    }
}
