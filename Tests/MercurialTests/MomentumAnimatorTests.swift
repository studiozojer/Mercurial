import XCTest
@testable import Mercurial

final class Momentum1DAnimatorTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialState() {
        let animator = Momentum1DAnimator()
        XCTAssertEqual(animator.position, 0)
        XCTAssertEqual(animator.velocity, 0)
        XCTAssertEqual(animator.state, .idle)
        XCTAssertFalse(animator.isActive)
    }

    func testInitialPositionCustom() {
        let animator = Momentum1DAnimator(initialPosition: 100)
        XCTAssertEqual(animator.position, 100)
    }

    // MARK: - Start Tests

    func testStartWithVelocity() {
        let animator = Momentum1DAnimator()
        animator.start(velocity: 500)

        XCTAssertEqual(animator.velocity, 500)
        XCTAssertEqual(animator.state, .momentum)
        XCTAssertTrue(animator.isActive)
    }

    func testStartWithLowVelocityIgnored() {
        let animator = Momentum1DAnimator()
        animator.start(velocity: 10)  // Below default minimumVelocity of 50

        XCTAssertEqual(animator.velocity, 0)
        XCTAssertEqual(animator.state, .idle)
        XCTAssertFalse(animator.isActive)
    }

    func testStartWithNegativeVelocity() {
        let animator = Momentum1DAnimator()
        animator.start(velocity: -500)

        XCTAssertEqual(animator.velocity, -500)
        XCTAssertTrue(animator.isActive)
    }

    // MARK: - Stop Tests

    func testStop() {
        let animator = Momentum1DAnimator()
        animator.start(velocity: 500)
        animator.stop()

        XCTAssertEqual(animator.velocity, 0)
        XCTAssertEqual(animator.state, .idle)
        XCTAssertFalse(animator.isActive)
    }

    // MARK: - Set Position Tests

    func testSetPosition() {
        let animator = Momentum1DAnimator()
        animator.setPosition(200)
        XCTAssertEqual(animator.position, 200)
    }

    // MARK: - Update Tests

    func testUpdateWhenIdle() {
        let animator = Momentum1DAnimator()
        let result = animator.update()
        XCTAssertFalse(result)
    }

    func testUpdateDecreasesVelocity() {
        let animator = Momentum1DAnimator()
        animator.start(velocity: 500)

        // First update initializes time, second update applies physics
        _ = animator.update()
        Thread.sleep(forTimeInterval: 0.02)  // Wait a bit
        _ = animator.update()

        XCTAssertLessThan(animator.velocity, 500)
    }

    func testUpdateMovesPosition() {
        let animator = Momentum1DAnimator()
        animator.start(velocity: 500)

        _ = animator.update()
        Thread.sleep(forTimeInterval: 0.02)
        _ = animator.update()

        XCTAssertGreaterThan(animator.position, 0)
    }

    // MARK: - Boundary Tests

    func testBoundsSet() {
        let animator = Momentum1DAnimator()
        animator.bounds = (min: 0, max: 100)
        XCTAssertEqual(animator.bounds?.min, 0)
        XCTAssertEqual(animator.bounds?.max, 100)
    }

    func testBounceWhenPastBoundary() {
        let animator = Momentum1DAnimator()
        animator.bounds = (min: 0, max: 100)
        animator.setPosition(150)  // Past max boundary
        // Use velocity moving further away from boundary
        animator.start(velocity: 100)

        // Should trigger bouncing state on update
        _ = animator.update()
        Thread.sleep(forTimeInterval: 0.02)
        _ = animator.update()

        // State should be bouncing (spring pulling back toward boundary)
        XCTAssertEqual(animator.state, .bouncing)
    }
}

final class Momentum2DAnimatorTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialState() {
        let animator = Momentum2DAnimator()
        XCTAssertEqual(animator.position.x, 0)
        XCTAssertEqual(animator.position.y, 0)
        XCTAssertEqual(animator.velocity.x, 0)
        XCTAssertEqual(animator.velocity.y, 0)
        XCTAssertEqual(animator.state, .idle)
        XCTAssertFalse(animator.isActive)
    }

    func testInitialPositionCustom() {
        let animator = Momentum2DAnimator(initialPosition: CGPoint(x: 100, y: 200))
        XCTAssertEqual(animator.position.x, 100)
        XCTAssertEqual(animator.position.y, 200)
    }

    // MARK: - Start Tests

    func testStartWithVelocity() {
        let animator = Momentum2DAnimator()
        animator.start(velocity: CGPoint(x: 300, y: 400))

        XCTAssertEqual(animator.velocity.x, 300)
        XCTAssertEqual(animator.velocity.y, 400)
        XCTAssertEqual(animator.state, .momentum)
        XCTAssertTrue(animator.isActive)
    }

    func testStartWithLowVelocityIgnored() {
        let animator = Momentum2DAnimator()
        // Speed = sqrt(3^2 + 4^2) = 5, below minimumVelocity of 50
        animator.start(velocity: CGPoint(x: 3, y: 4))

        XCTAssertEqual(animator.velocity.x, 0)
        XCTAssertEqual(animator.velocity.y, 0)
        XCTAssertEqual(animator.state, .idle)
        XCTAssertFalse(animator.isActive)
    }

    func testStartWithSingleAxisVelocity() {
        let animator = Momentum2DAnimator()
        animator.start(velocity: CGPoint(x: 100, y: 0))

        XCTAssertTrue(animator.isActive)
        XCTAssertEqual(animator.velocity.x, 100)
        XCTAssertEqual(animator.velocity.y, 0)
    }

    // MARK: - Stop Tests

    func testStop() {
        let animator = Momentum2DAnimator()
        animator.start(velocity: CGPoint(x: 300, y: 400))
        animator.stop()

        XCTAssertEqual(animator.velocity.x, 0)
        XCTAssertEqual(animator.velocity.y, 0)
        XCTAssertEqual(animator.state, .idle)
        XCTAssertFalse(animator.isActive)
    }

    // MARK: - Set Position Tests

    func testSetPosition() {
        let animator = Momentum2DAnimator()
        animator.setPosition(CGPoint(x: 200, y: 300))
        XCTAssertEqual(animator.position.x, 200)
        XCTAssertEqual(animator.position.y, 300)
    }

    // MARK: - Update Tests

    func testUpdateWhenIdle() {
        let animator = Momentum2DAnimator()
        let result = animator.update()
        XCTAssertFalse(result)
    }

    func testUpdateDecreasesSpeed() {
        let animator = Momentum2DAnimator()
        animator.start(velocity: CGPoint(x: 300, y: 400))
        let initialSpeed = Physics.speed(animator.velocity)

        _ = animator.update()
        Thread.sleep(forTimeInterval: 0.02)
        _ = animator.update()

        let newSpeed = Physics.speed(animator.velocity)
        XCTAssertLessThan(newSpeed, initialSpeed)
    }

    func testUpdateMovesPosition() {
        let animator = Momentum2DAnimator()
        animator.start(velocity: CGPoint(x: 300, y: 400))

        _ = animator.update()
        Thread.sleep(forTimeInterval: 0.02)
        _ = animator.update()

        XCTAssertGreaterThan(animator.position.x, 0)
        XCTAssertGreaterThan(animator.position.y, 0)
    }

    // MARK: - Boundary Tests

    func testBoundsSet() {
        let animator = Momentum2DAnimator()
        animator.bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(animator.bounds?.min.x, 0)
        XCTAssertEqual(animator.bounds?.max.y, 100)
    }

    func testBounceWhenPastBoundary() {
        let animator = Momentum2DAnimator()
        animator.bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )
        animator.setPosition(CGPoint(x: 150, y: 150))  // Past boundaries
        // Use velocity moving further away from boundary
        animator.start(velocity: CGPoint(x: 100, y: 100))

        _ = animator.update()
        Thread.sleep(forTimeInterval: 0.02)
        _ = animator.update()

        // State should be bouncing (spring pulling back toward boundary)
        XCTAssertEqual(animator.state, .bouncing)
    }

    // MARK: - Rubber Band Tests

    func testRubberBandOffsetNoBounds() {
        let animator = Momentum2DAnimator()
        // No bounds set - should return raw offset unchanged
        let result = animator.rubberBandOffset(CGPoint(x: 100, y: 100))
        XCTAssertEqual(result.x, 100, accuracy: 0.001)
        XCTAssertEqual(result.y, 100, accuracy: 0.001)
    }

    func testRubberBandOffsetWithinBounds() {
        let animator = Momentum2DAnimator()
        animator.bounds = PhysicsBounds(
            min: CGPoint(x: -100, y: -100),
            max: CGPoint(x: 100, y: 100)
        )
        animator.setPosition(.zero)

        // Small offset within bounds - should return unchanged
        let result = animator.rubberBandOffset(CGPoint(x: 50, y: 50))
        XCTAssertEqual(result.x, 50, accuracy: 0.001)
        XCTAssertEqual(result.y, 50, accuracy: 0.001)
    }

    func testRubberBandOffsetPastBounds() {
        let animator = Momentum2DAnimator()
        animator.bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )
        animator.setPosition(CGPoint(x: 50, y: 50))

        // Offset that would put us past max
        let result = animator.rubberBandOffset(CGPoint(x: 100, y: 100))

        // Result should be less than raw offset due to rubber band
        XCTAssertLessThan(result.x, 100)
        XCTAssertLessThan(result.y, 100)
        // But still positive
        XCTAssertGreaterThan(result.x, 50)
        XCTAssertGreaterThan(result.y, 50)
    }
}
