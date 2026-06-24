import XCTest
@testable import Mercurial

final class FreeBodyAnimatorLifecycleTests: XCTestCase {
    func testInitialState() {
        let a = FreeBodyAnimator()
        XCTAssertEqual(a.pose, .identity)
        XCTAssertEqual(a.linearVelocity, .zero)
        XCTAssertEqual(a.angularVelocity, 0)
        XCTAssertEqual(a.state, .idle)
        XCTAssertFalse(a.isActive)
    }
    func testRevivalConstructsAtRest() {
        // The save/restore path: born at an arbitrary pose, idle, no physics.
        let saved = Pose(position: CGPoint(x: 40, y: 90), rotation: 1.1)
        let a = FreeBodyAnimator(initialPose: saved)
        XCTAssertEqual(a.pose, saved)
        XCTAssertEqual(a.state, .idle)
        XCTAssertFalse(a.isActive)
    }
    func testStartWithRealVelocityActivates() {
        let a = FreeBodyAnimator()
        a.start(linearVelocity: CGPoint(x: 300, y: 0), angularVelocity: 0)
        XCTAssertTrue(a.isActive)
    }
    func testStartWithNegligibleVelocityStaysIdle() {
        let a = FreeBodyAnimator()
        a.start(linearVelocity: CGPoint(x: 1, y: 1), angularVelocity: 0.01)
        XCTAssertFalse(a.isActive)
    }
    func testAngularOnlyFlickActivates() {
        let a = FreeBodyAnimator()
        a.start(linearVelocity: .zero, angularVelocity: 6)   // well above engageBelow
        XCTAssertTrue(a.isActive)
    }
    func testStop() {
        let a = FreeBodyAnimator()
        a.start(linearVelocity: CGPoint(x: 300, y: 0), angularVelocity: 0)
        a.stop()
        XCTAssertEqual(a.linearVelocity, .zero)
        XCTAssertEqual(a.angularVelocity, 0)
        XCTAssertEqual(a.state, .idle)
    }
    func testSetPoseDoesNotAnimate() {
        let a = FreeBodyAnimator()
        a.setPose(Pose(position: CGPoint(x: 5, y: 6), rotation: 0.2))
        XCTAssertEqual(a.pose, Pose(position: CGPoint(x: 5, y: 6), rotation: 0.2))
        XCTAssertFalse(a.isActive)
    }
    func testUpdateWhenIdleReturnsFalse() {
        XCTAssertFalse(FreeBodyAnimator().update())
    }
}
