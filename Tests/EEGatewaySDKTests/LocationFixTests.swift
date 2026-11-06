import XCTest
@testable import EEGatewaySDK

final class LocationFixTests: XCTestCase {

    private let fix = LocationFix(
        latitude: 40.5,
        longitude: -74.25,
        accuracyM: 14.0,
        capturedAtMillis: 1_785_545_340_000
    )

    // MARK: staleness gate

    func testFreshWithinGate() {
        XCTAssertTrue(fix.isFresh(nowMillis: fix.capturedAtMillis + 24_999))
    }

    func testFreshAtExactly25s() {
        XCTAssertTrue(fix.isFresh(nowMillis: fix.capturedAtMillis + 25_000))
    }

    func testStaleBeyond25s() {
        XCTAssertFalse(fix.isFresh(nowMillis: fix.capturedAtMillis + 25_001))
    }

    func testFutureFixCountsAsFresh() {
        // Clock skew between GPS time and wall clock: server clamps, we
        // don't drop.
        XCTAssertTrue(fix.isFresh(nowMillis: fix.capturedAtMillis - 5_000))
    }

    // MARK: ingest sanity rules (one bad value 422s a whole batch upstream)

    func testOfAcceptsValidFix() {
        let f = LocationFix.of(latitude: 40.5, longitude: -74.25, accuracyM: 14.0, capturedAtMillis: 1_785_545_340_000)
        XCTAssertNotNil(f)
        XCTAssertEqual(f?.accuracyM, 14.0)
    }

    func testOfRejectsNullIsland() {
        XCTAssertNil(LocationFix.of(latitude: 0.0, longitude: 0.0, accuracyM: 14.0, capturedAtMillis: 1_785_545_340_000))
    }

    func testOfAcceptsZeroLatitudeAlone() {
        // Equator is a real place; only the exact (0, 0) pair is the tell.
        XCTAssertNotNil(LocationFix.of(latitude: 0.0, longitude: -74.25, accuracyM: 14.0, capturedAtMillis: 1_785_545_340_000))
    }

    func testOfRejectsOutOfRangeCoords() {
        XCTAssertNil(LocationFix.of(latitude: 90.5, longitude: -74.25, accuracyM: 14.0, capturedAtMillis: 1_785_545_340_000))
        XCTAssertNil(LocationFix.of(latitude: 40.5, longitude: -180.25, accuracyM: 14.0, capturedAtMillis: 1_785_545_340_000))
    }

    func testOfRejectsNonFiniteCoords() {
        // NaN passes abs(x) > 90 (false), then explodes inside JSON
        // serialization. Guarded at the gate instead.
        XCTAssertNil(LocationFix.of(latitude: .nan, longitude: -74.25, accuracyM: 14.0, capturedAtMillis: 1_785_545_340_000))
        XCTAssertNil(LocationFix.of(latitude: 40.5, longitude: .nan, accuracyM: 14.0, capturedAtMillis: 1_785_545_340_000))
        XCTAssertNil(LocationFix.of(latitude: .infinity, longitude: -74.25, accuracyM: 14.0, capturedAtMillis: 1_785_545_340_000))
        XCTAssertNil(LocationFix.of(latitude: 40.5, longitude: -.infinity, accuracyM: 14.0, capturedAtMillis: 1_785_545_340_000))
    }

    func testOfRejectsNonFiniteAccuracy() {
        XCTAssertNil(LocationFix.of(latitude: 40.5, longitude: -74.25, accuracyM: .nan, capturedAtMillis: 1_785_545_340_000))
        XCTAssertNil(LocationFix.of(latitude: 40.5, longitude: -74.25, accuracyM: .infinity, capturedAtMillis: 1_785_545_340_000))
    }

    func testOfRejectsNonPositiveCaptureTime() {
        XCTAssertNil(LocationFix.of(latitude: 40.5, longitude: -74.25, accuracyM: 14.0, capturedAtMillis: 0))
        XCTAssertNil(LocationFix.of(latitude: 40.5, longitude: -74.25, accuracyM: 14.0, capturedAtMillis: -1))
    }

    func testOfRejectsAccuracyWorseThan10km() {
        // Rural cell-tower fix: real occurrence, and ee-web 422s the batch.
        XCTAssertNil(LocationFix.of(latitude: 40.5, longitude: -74.25, accuracyM: 10_000.1, capturedAtMillis: 1_785_545_340_000))
    }

    func testOfAcceptsAccuracyAtExactly10km() {
        XCTAssertNotNil(LocationFix.of(latitude: 40.5, longitude: -74.25, accuracyM: 10_000.0, capturedAtMillis: 1_785_545_340_000))
    }

    func testOfDropsNonPositiveAccuracyButKeepsFix() {
        // accuracy_m <= 0 is batch-rejected upstream; the position itself
        // is still good, so keep the fix and omit the field.
        let f = LocationFix.of(latitude: 40.5, longitude: -74.25, accuracyM: 0.0, capturedAtMillis: 1_785_545_340_000)
        XCTAssertNotNil(f)
        XCTAssertNil(f?.accuracyM)
    }

    func testOfKeepsFixWithNoAccuracy() {
        let f = LocationFix.of(latitude: 40.5, longitude: -74.25, accuracyM: nil, capturedAtMillis: 1_785_545_340_000)
        XCTAssertNotNil(f)
        XCTAssertNil(f?.accuracyM)
    }
}
