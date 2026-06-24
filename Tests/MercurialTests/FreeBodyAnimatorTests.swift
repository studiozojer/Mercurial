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

final class FreeBodyAnimatorLinearTests: XCTestCase {
    private func run(_ a: FreeBodyAnimator, steps: Int, dt: CGFloat = 1.0 / 60) {
        for _ in 0..<steps where a.isActive { _ = a.step(deltaTime: dt) }
    }
    func testLinearFlickMovesAndDecays() {
        let a = FreeBodyAnimator()
        a.start(linearVelocity: CGPoint(x: 600, y: 0), angularVelocity: 0)
        run(a, steps: 1)
        XCTAssertGreaterThan(a.pose.position.x, 0)
        let speedAfter1 = Physics.speed(a.linearVelocity)
        run(a, steps: 1)
        XCTAssertLessThan(Physics.speed(a.linearVelocity), speedAfter1)   // friction
    }
    func testLinearFlickLeavesRotationUntouched() {
        let a = FreeBodyAnimator()
        a.start(linearVelocity: CGPoint(x: 600, y: 0), angularVelocity: 0)
        run(a, steps: 120)
        XCTAssertEqual(a.pose.rotation, 0, accuracy: 1e-9)   // angular channel inert (A7)
    }
    func testSettlesInsideBounds() {
        let a = FreeBodyAnimator()
        a.bounds = PhysicsBounds(min: CGPoint(x: 0, y: 0), max: CGPoint(x: 100, y: 100))
        a.setPose(Pose(position: CGPoint(x: 90, y: 50)))
        a.start(linearVelocity: CGPoint(x: 1500, y: 0), angularVelocity: 0)  // flick into the wall
        run(a, steps: 600)
        XCTAssertFalse(a.isActive)
        XCTAssertLessThanOrEqual(a.pose.position.x, 100.5)   // sprung back inside
        XCTAssertGreaterThanOrEqual(a.pose.position.x, -0.5)
    }
}

final class FreeBodyAnimatorAngularTests: XCTestCase {
    private func run(_ a: FreeBodyAnimator, steps: Int, dt: CGFloat = 1.0 / 60) {
        for _ in 0..<steps where a.isActive { _ = a.step(deltaTime: dt) }
    }
    func testSpinEndsExactlyOnDetent() {
        let a = FreeBodyAnimator()
        a.angularSettle = AngularSettleConfiguration(snap: .nearest([0, .pi / 2]))
        a.setPose(Pose(position: .zero, rotation: 0.2))
        a.start(linearVelocity: .zero, angularVelocity: 5)   // spins forward, then eases
        run(a, steps: 1200)
        XCTAssertFalse(a.isActive)
        let landed = a.angularSettle.settleTarget(for: a.pose.rotation)!
        XCTAssertEqual(Physics.shortestAngleDelta(from: a.pose.rotation, to: landed), 0, accuracy: 1e-3)
    }
    func testFreeSettleRestsAtArbitraryAngle() {
        let a = FreeBodyAnimator()              // angularSettle defaults to .free
        a.setPose(Pose(position: .zero, rotation: 0.37))
        a.start(linearVelocity: .zero, angularVelocity: 4)
        run(a, steps: 1200)
        XCTAssertFalse(a.isActive)
        // No detent: rotation simply stopped somewhere, not snapped to a grid.
        XCTAssertNotEqual(a.pose.rotation, 0, accuracy: 1e-6)
    }
    func testAngularFlickLeavesPositionUntouched() {
        let a = FreeBodyAnimator()
        a.setPose(Pose(position: CGPoint(x: 10, y: 20), rotation: 0))
        a.start(linearVelocity: .zero, angularVelocity: 6)
        run(a, steps: 300)
        XCTAssertEqual(a.pose.position, CGPoint(x: 10, y: 20))
    }
}
