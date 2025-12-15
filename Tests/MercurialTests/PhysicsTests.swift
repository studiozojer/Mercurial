import XCTest
@testable import Mercurial

final class PhysicsTests: XCTestCase {

    // MARK: - 1D Rubber Band Tests

    func testRubberBandZeroOffset() {
        let result = Physics.rubberBand(offset: 0, limit: 100, coefficient: 0.55)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    func testRubberBandPositiveOffset() {
        let result = Physics.rubberBand(offset: 100, limit: 100, coefficient: 0.55)
        XCTAssertGreaterThan(result, 0)
        XCTAssertLessThan(result, 100)
    }

    func testRubberBandNegativeOffset() {
        let result = Physics.rubberBand(offset: -100, limit: 100, coefficient: 0.55)
        XCTAssertLessThan(result, 0)
        XCTAssertGreaterThan(result, -100)
    }

    func testRubberBandSymmetry() {
        let positive = Physics.rubberBand(offset: 50, limit: 100, coefficient: 0.55)
        let negative = Physics.rubberBand(offset: -50, limit: 100, coefficient: 0.55)
        XCTAssertEqual(positive, -negative, accuracy: 0.001)
    }

    func testRubberBandAsymptoticLimit() {
        let result = Physics.rubberBand(offset: 10000, limit: 100, coefficient: 0.55)
        XCTAssertLessThan(result, 100)
        XCTAssertGreaterThan(result, 90)
    }

    func testRubberBandHigherCoefficientLessResistance() {
        let lowCoeff = Physics.rubberBand(offset: 100, limit: 100, coefficient: 0.3)
        let highCoeff = Physics.rubberBand(offset: 100, limit: 100, coefficient: 0.8)
        XCTAssertGreaterThan(highCoeff, lowCoeff)
    }

    func testRubberBandMonotonicallyIncreasing() {
        var previousResult: CGFloat = 0
        for offset in stride(from: 0.0, through: 500.0, by: 50.0) {
            let result = Physics.rubberBand(offset: CGFloat(offset), limit: 100, coefficient: 0.55)
            XCTAssertGreaterThanOrEqual(result, previousResult)
            previousResult = result
        }
    }

    // MARK: - 1D Spring Force Tests

    func testSpringForceAtRest() {
        let force = Physics.springForce(
            displacement: 0,
            velocity: 0,
            stiffness: 200,
            damping: 30
        )
        XCTAssertEqual(force, 0, accuracy: 0.001)
    }

    func testSpringForcePositiveDisplacement() {
        let force = Physics.springForce(
            displacement: 10,
            velocity: 0,
            stiffness: 200,
            damping: 30
        )
        XCTAssertLessThan(force, 0)
    }

    func testSpringForceNegativeDisplacement() {
        let force = Physics.springForce(
            displacement: -10,
            velocity: 0,
            stiffness: 200,
            damping: 30
        )
        XCTAssertGreaterThan(force, 0)
    }

    func testSpringForceDampingReducesVelocity() {
        let forceStill = Physics.springForce(
            displacement: 10,
            velocity: 0,
            stiffness: 200,
            damping: 30
        )
        let forceMoving = Physics.springForce(
            displacement: 10,
            velocity: 100,
            stiffness: 200,
            damping: 30
        )
        XCTAssertLessThan(forceMoving, forceStill)
    }

    func testSpringForceHigherStiffnessStrongerForce() {
        let lowStiffness = Physics.springForce(
            displacement: 10,
            velocity: 0,
            stiffness: 100,
            damping: 30
        )
        let highStiffness = Physics.springForce(
            displacement: 10,
            velocity: 0,
            stiffness: 300,
            damping: 30
        )
        XCTAssertLessThan(highStiffness, lowStiffness)
    }

    // MARK: - 1D Friction Tests

    func testFrictionReducesVelocity() {
        let initial: CGFloat = 100
        let result = Physics.applyFriction(velocity: initial, friction: 0.95)
        XCTAssertEqual(result, 95, accuracy: 0.001)
    }

    func testFrictionZeroVelocity() {
        let result = Physics.applyFriction(velocity: 0, friction: 0.95)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    func testFrictionNegativeVelocity() {
        let result = Physics.applyFriction(velocity: -100, friction: 0.95)
        XCTAssertEqual(result, -95, accuracy: 0.001)
    }

    func testFrictionDecayOverTime() {
        var velocity: CGFloat = 100
        for _ in 0..<60 {
            velocity = Physics.applyFriction(velocity: velocity, friction: 0.95)
        }
        XCTAssertLessThan(velocity, 6)
        XCTAssertGreaterThan(velocity, 4)
    }

    // MARK: - 1D Integration Tests

    func testIntegratePositiveVelocity() {
        let result = Physics.integrate(
            position: 100,
            velocity: 50,
            deltaTime: 1.0 / 60.0
        )
        let expected = 100 + 50 * (1.0 / 60.0)
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }

    func testIntegrateNegativeVelocity() {
        let result = Physics.integrate(
            position: 100,
            velocity: -50,
            deltaTime: 1.0 / 60.0
        )
        let expected = 100 - 50 * (1.0 / 60.0)
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }

    func testIntegrateZeroVelocity() {
        let result = Physics.integrate(
            position: 100,
            velocity: 0,
            deltaTime: 1.0 / 60.0
        )
        XCTAssertEqual(result, 100, accuracy: 0.001)
    }

    func testIntegrateZeroDeltaTime() {
        let result = Physics.integrate(
            position: 100,
            velocity: 1000,
            deltaTime: 0
        )
        XCTAssertEqual(result, 100, accuracy: 0.001)
    }

    // MARK: - Quadratic Decay Tests

    func testQuadraticDecayAtZero() {
        let result = Physics.quadraticDecay(progress: 0)
        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    func testQuadraticDecayAtOne() {
        let result = Physics.quadraticDecay(progress: 1)
        XCTAssertEqual(result, 0.0, accuracy: 0.001)
    }

    func testQuadraticDecayAtHalf() {
        let result = Physics.quadraticDecay(progress: 0.5)
        XCTAssertEqual(result, 0.75, accuracy: 0.001)
    }

    // MARK: - 2D Rubber Band Tests

    func testRubberBand2DZeroOffset() {
        let result = Physics.rubberBand(offset: .zero, limit: 100, coefficient: 0.55)
        XCTAssertEqual(result.x, 0, accuracy: 0.001)
        XCTAssertEqual(result.y, 0, accuracy: 0.001)
    }

    func testRubberBand2DIndependentAxes() {
        let result = Physics.rubberBand(
            offset: CGPoint(x: 50, y: 100),
            limit: 100,
            coefficient: 0.55
        )
        let expected1D_50 = Physics.rubberBand(offset: 50, limit: 100, coefficient: 0.55)
        let expected1D_100 = Physics.rubberBand(offset: 100, limit: 100, coefficient: 0.55)
        XCTAssertEqual(result.x, expected1D_50, accuracy: 0.001)
        XCTAssertEqual(result.y, expected1D_100, accuracy: 0.001)
    }

    func testRubberBand2DPerAxisLimits() {
        let result = Physics.rubberBand(
            offset: CGPoint(x: 100, y: 100),
            limits: CGPoint(x: 50, y: 200),
            coefficient: 0.55
        )
        // X should be more constrained (smaller limit)
        // Y should be less constrained (larger limit)
        let xExpected = Physics.rubberBand(offset: 100, limit: 50, coefficient: 0.55)
        let yExpected = Physics.rubberBand(offset: 100, limit: 200, coefficient: 0.55)
        XCTAssertEqual(result.x, xExpected, accuracy: 0.001)
        XCTAssertEqual(result.y, yExpected, accuracy: 0.001)
    }

    // MARK: - 2D Spring Force Tests

    func testSpringForce2DAtRest() {
        let force = Physics.springForce(
            displacement: .zero,
            velocity: .zero,
            stiffness: 200,
            damping: 30
        )
        XCTAssertEqual(force.x, 0, accuracy: 0.001)
        XCTAssertEqual(force.y, 0, accuracy: 0.001)
    }

    func testSpringForce2DIndependentAxes() {
        let force = Physics.springForce(
            displacement: CGPoint(x: 10, y: -20),
            velocity: CGPoint(x: 5, y: -10),
            stiffness: 200,
            damping: 30
        )
        let expectedX = Physics.springForce(displacement: 10, velocity: 5, stiffness: 200, damping: 30)
        let expectedY = Physics.springForce(displacement: -20, velocity: -10, stiffness: 200, damping: 30)
        XCTAssertEqual(force.x, expectedX, accuracy: 0.001)
        XCTAssertEqual(force.y, expectedY, accuracy: 0.001)
    }

    // MARK: - 2D Friction Tests

    func testFriction2D() {
        let result = Physics.applyFriction(
            velocity: CGPoint(x: 100, y: -200),
            friction: 0.95
        )
        XCTAssertEqual(result.x, 95, accuracy: 0.001)
        XCTAssertEqual(result.y, -190, accuracy: 0.001)
    }

    // MARK: - 2D Integration Tests

    func testIntegrate2D() {
        let result = Physics.integrate(
            position: CGPoint(x: 100, y: 200),
            velocity: CGPoint(x: 60, y: -60),
            deltaTime: 1.0 / 60.0
        )
        XCTAssertEqual(result.x, 101, accuracy: 0.001)
        XCTAssertEqual(result.y, 199, accuracy: 0.001)
    }

    // MARK: - Speed Tests

    func testSpeedZero() {
        let result = Physics.speed(.zero)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    func testSpeedHorizontal() {
        let result = Physics.speed(CGPoint(x: 100, y: 0))
        XCTAssertEqual(result, 100, accuracy: 0.001)
    }

    func testSpeedVertical() {
        let result = Physics.speed(CGPoint(x: 0, y: 100))
        XCTAssertEqual(result, 100, accuracy: 0.001)
    }

    func testSpeedDiagonal() {
        let result = Physics.speed(CGPoint(x: 3, y: 4))
        XCTAssertEqual(result, 5, accuracy: 0.001)
    }

    // MARK: - Combined Simulation Tests

    func testMomentumDecaySimulation() {
        var position: CGFloat = 0
        var velocity: CGFloat = 500
        let friction: CGFloat = 0.95
        let frameTime: CGFloat = 1.0 / 60.0

        for _ in 0..<60 {
            position = Physics.integrate(position: position, velocity: velocity, deltaTime: frameTime)
            velocity = Physics.applyFriction(velocity: velocity, friction: friction)
        }

        XCTAssertGreaterThan(position, 100)
        XCTAssertLessThan(abs(velocity), 30)
    }

    func testBounceSimulation() {
        var position: CGFloat = 50
        var velocity: CGFloat = 0
        let stiffness: CGFloat = 200
        let damping: CGFloat = 30
        let frameTime: CGFloat = 1.0 / 60.0

        for _ in 0..<120 {
            let force = Physics.springForce(
                displacement: position,
                velocity: velocity,
                stiffness: stiffness,
                damping: damping
            )
            velocity += force * frameTime
            position = Physics.integrate(position: position, velocity: velocity, deltaTime: frameTime)
        }

        XCTAssertLessThan(abs(position), 1)
        XCTAssertLessThan(abs(velocity), 1)
    }
}

// MARK: - CGPoint Arithmetic Tests

final class CGPointArithmeticTests: XCTestCase {

    func testAddition() {
        let a = CGPoint(x: 1, y: 2)
        let b = CGPoint(x: 3, y: 4)
        let result = a + b
        XCTAssertEqual(result.x, 4, accuracy: 0.001)
        XCTAssertEqual(result.y, 6, accuracy: 0.001)
    }

    func testSubtraction() {
        let a = CGPoint(x: 5, y: 7)
        let b = CGPoint(x: 2, y: 3)
        let result = a - b
        XCTAssertEqual(result.x, 3, accuracy: 0.001)
        XCTAssertEqual(result.y, 4, accuracy: 0.001)
    }

    func testScalarMultiplication() {
        let point = CGPoint(x: 2, y: 3)
        let result = point * 4
        XCTAssertEqual(result.x, 8, accuracy: 0.001)
        XCTAssertEqual(result.y, 12, accuracy: 0.001)
    }

    func testAddAssign() {
        var point = CGPoint(x: 1, y: 2)
        point += CGPoint(x: 3, y: 4)
        XCTAssertEqual(point.x, 4, accuracy: 0.001)
        XCTAssertEqual(point.y, 6, accuracy: 0.001)
    }

    func testSubtractAssign() {
        var point = CGPoint(x: 5, y: 7)
        point -= CGPoint(x: 2, y: 3)
        XCTAssertEqual(point.x, 3, accuracy: 0.001)
        XCTAssertEqual(point.y, 4, accuracy: 0.001)
    }
}
