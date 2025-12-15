import XCTest
@testable import Mercurial

final class TransformConfigurationTests: XCTestCase {

    func testDefaultConfiguration() {
        let config = TransformConfiguration.default
        XCTAssertEqual(config.minScale, 1.0)
        XCTAssertEqual(config.maxScale, 3.0)
        XCTAssertEqual(config.hitAreaMultiplier, 0.3)
        XCTAssertEqual(config.textMultiplier, 0.4)
        XCTAssertEqual(config.glyphMultiplier, 0.5)
    }

    func testMapConfiguration() {
        let config = TransformConfiguration.map
        XCTAssertEqual(config.minScale, 0.5)
        XCTAssertEqual(config.maxScale, 5.0)
    }

    func testImageViewerConfiguration() {
        let config = TransformConfiguration.imageViewer
        XCTAssertEqual(config.minScale, 1.0)
        XCTAssertEqual(config.maxScale, 10.0)
    }

    func testCustomConfiguration() {
        let config = TransformConfiguration(
            minScale: 0.25,
            maxScale: 8.0,
            hitAreaMultiplier: 0.5,
            textMultiplier: 0.6,
            glyphMultiplier: 0.7
        )
        XCTAssertEqual(config.minScale, 0.25)
        XCTAssertEqual(config.maxScale, 8.0)
        XCTAssertEqual(config.hitAreaMultiplier, 0.5)
        XCTAssertEqual(config.textMultiplier, 0.6)
        XCTAssertEqual(config.glyphMultiplier, 0.7)
    }
}

final class TransformTests: XCTestCase {

    // MARK: - Initialization Tests

    func testIdentityTransform() {
        let transform = Transform.identity
        XCTAssertEqual(transform.scale, 1.0)
        XCTAssertEqual(transform.offset, .zero)
        XCTAssertTrue(transform.isIdentity)
    }

    func testScaleClamping() {
        // Below minimum
        let belowMin = Transform(scale: 0.5, offset: .zero)
        XCTAssertEqual(belowMin.scale, 1.0)  // Clamped to min

        // Above maximum
        let aboveMax = Transform(scale: 5.0, offset: .zero)
        XCTAssertEqual(aboveMax.scale, 3.0)  // Clamped to max

        // Within range
        let inRange = Transform(scale: 2.0, offset: .zero)
        XCTAssertEqual(inRange.scale, 2.0)
    }

    func testScaleClampingWithCustomConfig() {
        let config = TransformConfiguration(minScale: 0.5, maxScale: 5.0)
        let transform = Transform(scale: 0.25, offset: .zero, configuration: config)
        XCTAssertEqual(transform.scale, 0.5)  // Clamped to custom min
    }

    // MARK: - Immutable Update Tests

    func testWithScale() {
        let original = Transform(scale: 1.0, offset: CGPoint(x: 10, y: 20))
        let updated = original.withScale(2.0)

        XCTAssertEqual(updated.scale, 2.0)
        XCTAssertEqual(updated.offset, original.offset)
        XCTAssertEqual(original.scale, 1.0)  // Original unchanged
    }

    func testWithOffset() {
        let original = Transform(scale: 2.0, offset: .zero)
        let updated = original.withOffset(CGPoint(x: 50, y: 100))

        XCTAssertEqual(updated.offset.x, 50)
        XCTAssertEqual(updated.offset.y, 100)
        XCTAssertEqual(updated.scale, 2.0)
        XCTAssertEqual(original.offset, .zero)  // Original unchanged
    }

    func testOffsetBy() {
        let original = Transform(scale: 1.0, offset: CGPoint(x: 10, y: 20))
        let updated = original.offsetBy(CGPoint(x: 5, y: -10))

        XCTAssertEqual(updated.offset.x, 15)
        XCTAssertEqual(updated.offset.y, 10)
    }

    // MARK: - Coordinate Transformation Tests

    func testToViewportIdentity() {
        let transform = Transform.identity
        let center = CGPoint(x: 200, y: 200)
        let canvasPoint = CGPoint(x: 150, y: 250)

        let viewportPoint = transform.toViewport(canvasPoint, center: center)

        XCTAssertEqual(viewportPoint.x, canvasPoint.x, accuracy: 0.001)
        XCTAssertEqual(viewportPoint.y, canvasPoint.y, accuracy: 0.001)
    }

    func testToCanvasIdentity() {
        let transform = Transform.identity
        let center = CGPoint(x: 200, y: 200)
        let viewportPoint = CGPoint(x: 150, y: 250)

        let canvasPoint = transform.toCanvas(viewportPoint, center: center)

        XCTAssertEqual(canvasPoint.x, viewportPoint.x, accuracy: 0.001)
        XCTAssertEqual(canvasPoint.y, viewportPoint.y, accuracy: 0.001)
    }

    func testToViewportWithScale() {
        let transform = Transform(scale: 2.0, offset: .zero)
        let center = CGPoint(x: 200, y: 200)

        // Point at center should stay at center
        let centerResult = transform.toViewport(center, center: center)
        XCTAssertEqual(centerResult.x, center.x, accuracy: 0.001)
        XCTAssertEqual(centerResult.y, center.y, accuracy: 0.001)

        // Point away from center should move further away
        let awayPoint = CGPoint(x: 250, y: 200)  // 50pt right of center
        let awayResult = transform.toViewport(awayPoint, center: center)
        XCTAssertEqual(awayResult.x, 300, accuracy: 0.001)  // 100pt right of center (2x)
        XCTAssertEqual(awayResult.y, 200, accuracy: 0.001)
    }

    func testToCanvasWithScale() {
        let transform = Transform(scale: 2.0, offset: .zero)
        let center = CGPoint(x: 200, y: 200)

        // Point 100pt from center in viewport = 50pt from center in canvas
        let viewportPoint = CGPoint(x: 300, y: 200)
        let canvasPoint = transform.toCanvas(viewportPoint, center: center)
        XCTAssertEqual(canvasPoint.x, 250, accuracy: 0.001)
        XCTAssertEqual(canvasPoint.y, 200, accuracy: 0.001)
    }

    func testToViewportWithOffset() {
        let transform = Transform(scale: 1.0, offset: CGPoint(x: 50, y: -30))
        let center = CGPoint(x: 200, y: 200)
        let canvasPoint = CGPoint(x: 100, y: 100)

        let viewportPoint = transform.toViewport(canvasPoint, center: center)
        XCTAssertEqual(viewportPoint.x, 150, accuracy: 0.001)  // 100 + 50
        XCTAssertEqual(viewportPoint.y, 70, accuracy: 0.001)   // 100 - 30
    }

    func testRoundTrip() {
        let transform = Transform(scale: 2.5, offset: CGPoint(x: 75, y: -40))
        let center = CGPoint(x: 200, y: 200)
        let originalCanvas = CGPoint(x: 123, y: 456)

        let viewport = transform.toViewport(originalCanvas, center: center)
        let backToCanvas = transform.toCanvas(viewport, center: center)

        XCTAssertEqual(backToCanvas.x, originalCanvas.x, accuracy: 0.001)
        XCTAssertEqual(backToCanvas.y, originalCanvas.y, accuracy: 0.001)
    }

    func testSizeConversion() {
        let transform = Transform(scale: 2.0, offset: .zero)

        XCTAssertEqual(transform.toViewport(50), 100, accuracy: 0.001)
        XCTAssertEqual(transform.toCanvas(100), 50, accuracy: 0.001)
    }

    // MARK: - Element Scaling Tests

    func testHitAreaScale() {
        let transform = Transform(scale: 3.0, offset: .zero)
        // At 3x with 0.3 multiplier: 1.0 + (3.0 - 1.0) * 0.3 = 1.6
        XCTAssertEqual(transform.hitAreaScale(), 1.6, accuracy: 0.001)
    }

    func testTextScale() {
        let transform = Transform(scale: 3.0, offset: .zero)
        // At 3x with 0.4 multiplier: 1.0 + (3.0 - 1.0) * 0.4 = 1.8
        XCTAssertEqual(transform.textScale(), 1.8, accuracy: 0.001)
    }

    func testGlyphScale() {
        let transform = Transform(scale: 3.0, offset: .zero)
        // At 3x with 0.5 multiplier: 1.0 + (3.0 - 1.0) * 0.5 = 2.0
        XCTAssertEqual(transform.glyphScale(), 2.0, accuracy: 0.001)
    }

    func testElementScaleCustom() {
        let transform = Transform(scale: 2.0, offset: .zero)
        // At 2x with 0.6 multiplier: 1.0 + (2.0 - 1.0) * 0.6 = 1.6
        XCTAssertEqual(transform.elementScale(multiplier: 0.6), 1.6, accuracy: 0.001)
    }

    func testElementScaleAtIdentity() {
        let transform = Transform.identity
        // At 1x, all element scales should be 1.0
        XCTAssertEqual(transform.hitAreaScale(), 1.0, accuracy: 0.001)
        XCTAssertEqual(transform.textScale(), 1.0, accuracy: 0.001)
        XCTAssertEqual(transform.glyphScale(), 1.0, accuracy: 0.001)
    }

    // MARK: - State Query Tests

    func testIsZoomed() {
        XCTAssertFalse(Transform.identity.isZoomed)
        XCTAssertTrue(Transform(scale: 1.5, offset: .zero).isZoomed)
    }

    func testIsPanned() {
        XCTAssertFalse(Transform.identity.isPanned)
        XCTAssertTrue(Transform(scale: 1.0, offset: CGPoint(x: 1, y: 0)).isPanned)
    }

    func testIsIdentity() {
        XCTAssertTrue(Transform.identity.isIdentity)
        XCTAssertFalse(Transform(scale: 1.5, offset: .zero).isIdentity)
        XCTAssertFalse(Transform(scale: 1.0, offset: CGPoint(x: 1, y: 0)).isIdentity)
    }

    func testIsAtMinMaxScale() {
        let config = TransformConfiguration(minScale: 0.5, maxScale: 5.0)

        let atMin = Transform(scale: 0.5, offset: .zero, configuration: config)
        XCTAssertTrue(atMin.isAtMinScale)
        XCTAssertFalse(atMin.isAtMaxScale)

        let atMax = Transform(scale: 5.0, offset: .zero, configuration: config)
        XCTAssertFalse(atMax.isAtMinScale)
        XCTAssertTrue(atMax.isAtMaxScale)

        let inMiddle = Transform(scale: 2.0, offset: .zero, configuration: config)
        XCTAssertFalse(inMiddle.isAtMinScale)
        XCTAssertFalse(inMiddle.isAtMaxScale)
    }

    // MARK: - Anchor Point Scaling Tests

    func testScaledByAnchor() {
        let transform = Transform(scale: 1.0, offset: .zero)
        let center = CGPoint(x: 200, y: 200)
        let anchor = CGPoint(x: 300, y: 200)  // Right of center

        let scaled = transform.scaled(by: 2.0, anchor: anchor, center: center)

        // Scale should double
        XCTAssertEqual(scaled.scale, 2.0, accuracy: 0.001)

        // Anchor point should stay at same viewport position
        let anchorInCanvas = transform.toCanvas(anchor, center: center)
        let anchorAfter = scaled.toViewport(anchorInCanvas, center: center)
        XCTAssertEqual(anchorAfter.x, anchor.x, accuracy: 0.01)
        XCTAssertEqual(anchorAfter.y, anchor.y, accuracy: 0.01)
    }
}

// MARK: - CGPoint Distance Tests

final class CGPointDistanceTests: XCTestCase {

    func testDistanceToSelf() {
        let point = CGPoint(x: 100, y: 200)
        XCTAssertEqual(point.distance(to: point), 0, accuracy: 0.001)
    }

    func testDistanceHorizontal() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 100, y: 0)
        XCTAssertEqual(a.distance(to: b), 100, accuracy: 0.001)
    }

    func testDistanceVertical() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 0, y: 100)
        XCTAssertEqual(a.distance(to: b), 100, accuracy: 0.001)
    }

    func testDistanceDiagonal() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 3, y: 4)
        XCTAssertEqual(a.distance(to: b), 5, accuracy: 0.001)  // 3-4-5 triangle
    }
}
