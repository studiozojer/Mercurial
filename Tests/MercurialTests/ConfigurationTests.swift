import XCTest
@testable import Mercurial

final class ConfigurationTests: XCTestCase {

    // MARK: - Momentum Configuration Tests

    func testMomentumConfigurationDefaults() {
        let config = MomentumConfiguration.default
        XCTAssertEqual(config.friction, 0.95)
        XCTAssertEqual(config.minimumVelocity, 50)
        XCTAssertEqual(config.maxDeltaTime, 1.0 / 30.0, accuracy: 0.001)
    }

    func testMomentumConfigurationSnappy() {
        let config = MomentumConfiguration.snappy
        XCTAssertEqual(config.friction, 0.90)
    }

    func testMomentumConfigurationSmooth() {
        let config = MomentumConfiguration.smooth
        XCTAssertEqual(config.friction, 0.97)
    }

    func testMomentumConfigurationCustom() {
        let config = MomentumConfiguration(
            friction: 0.85,
            minimumVelocity: 100,
            maxDeltaTime: 0.05
        )
        XCTAssertEqual(config.friction, 0.85)
        XCTAssertEqual(config.minimumVelocity, 100)
        XCTAssertEqual(config.maxDeltaTime, 0.05)
    }

    // MARK: - Spring Configuration Tests

    func testSpringConfigurationDefaults() {
        let config = SpringConfiguration.default
        XCTAssertEqual(config.stiffness, 200)
        XCTAssertEqual(config.damping, 30)
    }

    func testSpringConfigurationBouncy() {
        let config = SpringConfiguration.bouncy
        XCTAssertEqual(config.stiffness, 300)
        XCTAssertEqual(config.damping, 15)
    }

    func testSpringConfigurationSoft() {
        let config = SpringConfiguration.soft
        XCTAssertEqual(config.stiffness, 100)
        XCTAssertEqual(config.damping, 20)
    }

    func testSpringConfigurationCustom() {
        let config = SpringConfiguration(stiffness: 250, damping: 25)
        XCTAssertEqual(config.stiffness, 250)
        XCTAssertEqual(config.damping, 25)
    }

    // MARK: - Rubber Band Configuration Tests

    func testRubberBandConfigurationDefaults() {
        let config = RubberBandConfiguration.default
        XCTAssertEqual(config.coefficient, 0.55)
        XCTAssertEqual(config.limit, 240)
    }

    func testRubberBandConfigurationTight() {
        let config = RubberBandConfiguration.tight
        XCTAssertEqual(config.coefficient, 0.3)
        XCTAssertEqual(config.limit, 150)
    }

    func testRubberBandConfigurationLoose() {
        let config = RubberBandConfiguration.loose
        XCTAssertEqual(config.coefficient, 0.7)
        XCTAssertEqual(config.limit, 300)
    }

    func testRubberBandConfigurationCustom() {
        let config = RubberBandConfiguration(coefficient: 0.5, limit: 200)
        XCTAssertEqual(config.coefficient, 0.5)
        XCTAssertEqual(config.limit, 200)
    }

    // MARK: - Physics Configuration Tests

    func testPhysicsConfigurationDefaults() {
        let config = PhysicsConfiguration.default
        XCTAssertEqual(config.momentum.friction, 0.95)
        XCTAssertEqual(config.spring.stiffness, 200)
        XCTAssertEqual(config.rubberBand.coefficient, 0.55)
    }

    func testPhysicsConfigurationCustom() {
        let config = PhysicsConfiguration(
            momentum: .snappy,
            spring: .bouncy,
            rubberBand: .tight
        )
        XCTAssertEqual(config.momentum.friction, 0.90)
        XCTAssertEqual(config.spring.stiffness, 300)
        XCTAssertEqual(config.rubberBand.coefficient, 0.3)
    }

    // MARK: - Physics Bounds Tests

    func testBoundsContainsInside() {
        let bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )
        XCTAssertTrue(bounds.contains(CGPoint(x: 50, y: 50)))
    }

    func testBoundsContainsOnEdge() {
        let bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )
        XCTAssertTrue(bounds.contains(CGPoint(x: 0, y: 0)))
        XCTAssertTrue(bounds.contains(CGPoint(x: 100, y: 100)))
    }

    func testBoundsContainsOutside() {
        let bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )
        XCTAssertFalse(bounds.contains(CGPoint(x: -1, y: 50)))
        XCTAssertFalse(bounds.contains(CGPoint(x: 50, y: 101)))
    }

    func testBoundsClamp() {
        let bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )

        // Inside - unchanged
        let inside = bounds.clamp(CGPoint(x: 50, y: 50))
        XCTAssertEqual(inside.x, 50, accuracy: 0.001)
        XCTAssertEqual(inside.y, 50, accuracy: 0.001)

        // Below min
        let belowMin = bounds.clamp(CGPoint(x: -10, y: -20))
        XCTAssertEqual(belowMin.x, 0, accuracy: 0.001)
        XCTAssertEqual(belowMin.y, 0, accuracy: 0.001)

        // Above max
        let aboveMax = bounds.clamp(CGPoint(x: 150, y: 200))
        XCTAssertEqual(aboveMax.x, 100, accuracy: 0.001)
        XCTAssertEqual(aboveMax.y, 100, accuracy: 0.001)
    }

    func testBoundsDisplacementInside() {
        let bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )
        let displacement = bounds.displacement(from: CGPoint(x: 50, y: 50))
        XCTAssertEqual(displacement.x, 0, accuracy: 0.001)
        XCTAssertEqual(displacement.y, 0, accuracy: 0.001)
    }

    func testBoundsDisplacementBelowMin() {
        let bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )
        let displacement = bounds.displacement(from: CGPoint(x: -10, y: -20))
        XCTAssertEqual(displacement.x, -10, accuracy: 0.001)
        XCTAssertEqual(displacement.y, -20, accuracy: 0.001)
    }

    func testBoundsDisplacementAboveMax() {
        let bounds = PhysicsBounds(
            min: CGPoint(x: 0, y: 0),
            max: CGPoint(x: 100, y: 100)
        )
        let displacement = bounds.displacement(from: CGPoint(x: 150, y: 200))
        XCTAssertEqual(displacement.x, 50, accuracy: 0.001)
        XCTAssertEqual(displacement.y, 100, accuracy: 0.001)
    }

    func testBoundsFromRect() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
        let bounds = PhysicsBounds(rect: rect)
        XCTAssertEqual(bounds.min.x, 10, accuracy: 0.001)
        XCTAssertEqual(bounds.min.y, 20, accuracy: 0.001)
        XCTAssertEqual(bounds.max.x, 110, accuracy: 0.001)
        XCTAssertEqual(bounds.max.y, 220, accuracy: 0.001)
    }

    func testBoundsUnbounded() {
        let bounds = PhysicsBounds.unbounded
        XCTAssertTrue(bounds.contains(CGPoint(x: 1_000_000, y: -1_000_000)))
        XCTAssertEqual(bounds.displacement(from: CGPoint(x: 1_000_000, y: -1_000_000)).x, 0)
    }
}
