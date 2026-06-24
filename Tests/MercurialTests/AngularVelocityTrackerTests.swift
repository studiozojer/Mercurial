import XCTest
@testable import Mercurial

final class AngularVelocityTrackerTests: XCTestCase {
    func testInstantaneousVelocityFromTwoSamples() {
        let t = AngularVelocityTracker()
        t.record(angle: 0, at: 0)
        t.record(angle: 0.5, at: 0.1)          // 0.5 rad over 0.1s = 5 rad/s
        XCTAssertEqual(t.velocity(asOf: 0.1), 5, accuracy: 1e-6)
    }
    func testStaleSampleReadsZero() {
        let t = AngularVelocityTracker()
        t.record(angle: 0, at: 0)
        t.record(angle: 0.5, at: 0.1)
        // maxReleaseAge default 0.1s; 0.3 is well past it.
        XCTAssertEqual(t.velocity(asOf: 0.3), 0, accuracy: 1e-9)
    }
    func testResetClears() {
        let t = AngularVelocityTracker()
        t.record(angle: 0, at: 0)
        t.record(angle: 0.5, at: 0.1)
        t.reset()
        XCTAssertEqual(t.velocity(asOf: 0.1), 0, accuracy: 1e-9)
    }
}
