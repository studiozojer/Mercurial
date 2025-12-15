import XCTest
@testable import Mercurial

// MARK: - Test Fixtures

struct TestHittableNode: Hittable, Sendable {
    let id: String
    var position: CGPoint
    var hitRadius: CGFloat

    init(id: String, x: CGFloat, y: CGFloat, radius: CGFloat = 22) {
        self.id = id
        self.position = CGPoint(x: x, y: y)
        self.hitRadius = radius
    }
}

// MARK: - Initialization Tests

@MainActor
final class GestureCoordinatorInitTests: XCTestCase {

    func testDefaultInitialization() {
        let coordinator = GestureCoordinator()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(coordinator.transform.scale, 1.0)
        XCTAssertEqual(coordinator.transform.offset, .zero)
        XCTAssertFalse(coordinator.isAnimating)
    }

    func testCustomConfiguration() {
        let config = GestureCoordinatorConfiguration(
            transform: TransformConfiguration(minScale: 0.5, maxScale: 5.0),
            minimumMomentumVelocity: 100
        )
        let coordinator = GestureCoordinator(configuration: config)

        XCTAssertEqual(coordinator.configuration.transform.minScale, 0.5)
        XCTAssertEqual(coordinator.configuration.transform.maxScale, 5.0)
        XCTAssertEqual(coordinator.configuration.minimumMomentumVelocity, 100)
    }
}

// MARK: - Pan Gesture Tests

@MainActor
final class GestureCoordinatorPanTests: XCTestCase {

    let center = CGPoint(x: 200, y: 200)

    func testPanBeganSetsState() {
        let coordinator = GestureCoordinator()
        coordinator.panBegan()

        XCTAssertEqual(coordinator.state, .dragging)
    }

    func testPanChangedUpdatesOffset() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)

        XCTAssertEqual(coordinator.state, .dragging)
        XCTAssertEqual(coordinator.transform.offset.x, 50, accuracy: 0.001)
        XCTAssertEqual(coordinator.transform.offset.y, 30, accuracy: 0.001)
    }

    func testPanChangedIsAdditive() {
        let coordinator = GestureCoordinator()

        // First drag
        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)
        coordinator.panEnded(velocity: .zero, center: center)

        // Second drag
        coordinator.panChanged(CGPoint(x: 20, y: 10), center: center)

        // Should be relative to where we ended, not cumulative
        // panChanged uses dragStartOffset which was captured at panBegan
        // So after ending at (50, 30), next pan starts fresh
        XCTAssertEqual(coordinator.transform.offset.x, 70, accuracy: 0.001)
        XCTAssertEqual(coordinator.transform.offset.y, 40, accuracy: 0.001)
    }

    func testPanEndedWithLowVelocityGoesIdle() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)
        coordinator.panEnded(velocity: CGPoint(x: 10, y: 10), center: center)

        XCTAssertEqual(coordinator.state, .idle)
    }

    func testPanEndedWithHighVelocityStartsMomentum() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)
        coordinator.panEnded(velocity: CGPoint(x: 500, y: 300), center: center)

        XCTAssertEqual(coordinator.state, .momentum)
        XCTAssertTrue(coordinator.isAnimating)
    }

    func testPanCancelledGoesIdle() {
        let coordinator = GestureCoordinator()
        coordinator.panBegan()
        coordinator.panCancelled()

        XCTAssertEqual(coordinator.state, .idle)
    }
}

// MARK: - Zoom Gesture Tests

@MainActor
final class GestureCoordinatorZoomTests: XCTestCase {

    let center = CGPoint(x: 200, y: 200)

    func testZoomBeganSetsState() {
        let coordinator = GestureCoordinator()
        coordinator.zoomBegan()

        XCTAssertEqual(coordinator.state, .zooming)
    }

    func testZoomChangedUpdatesScale() {
        let coordinator = GestureCoordinator()
        coordinator.zoomChanged(scale: 2.0, anchor: center, center: center)

        XCTAssertEqual(coordinator.state, .zooming)
        XCTAssertEqual(coordinator.transform.scale, 2.0, accuracy: 0.001)
    }

    func testZoomChangedRespectsScaleLimits() {
        let config = GestureCoordinatorConfiguration(
            transform: TransformConfiguration(minScale: 1.0, maxScale: 3.0)
        )
        let coordinator = GestureCoordinator(configuration: config)

        // Try to zoom to 5x (should clamp to 3x)
        coordinator.zoomChanged(scale: 5.0, anchor: center, center: center)

        XCTAssertEqual(coordinator.transform.scale, 3.0, accuracy: 0.001)
    }

    func testZoomChangedPreservesAnchorPoint() {
        let coordinator = GestureCoordinator()
        let anchor = CGPoint(x: 300, y: 200) // Right of center

        // Get canvas position of anchor before zoom
        let anchorCanvasBefore = coordinator.toCanvas(anchor, center: center)

        // Zoom 2x around anchor
        coordinator.zoomChanged(scale: 2.0, anchor: anchor, center: center)

        // Anchor should stay at same viewport position
        let anchorViewportAfter = coordinator.toViewport(anchorCanvasBefore, center: center)
        XCTAssertEqual(anchorViewportAfter.x, anchor.x, accuracy: 1.0)
        XCTAssertEqual(anchorViewportAfter.y, anchor.y, accuracy: 1.0)
    }

    func testZoomEndedGoesIdle() {
        let coordinator = GestureCoordinator()
        coordinator.zoomBegan()
        coordinator.zoomEnded(center: center)

        XCTAssertEqual(coordinator.state, .idle)
    }

    func testZoomCancelledGoesIdle() {
        let coordinator = GestureCoordinator()
        coordinator.zoomBegan()
        coordinator.zoomCancelled()

        XCTAssertEqual(coordinator.state, .idle)
    }
}

// MARK: - Gesture Transition Tests

@MainActor
final class GestureCoordinatorTransitionTests: XCTestCase {

    let center = CGPoint(x: 200, y: 200)

    func testTransitionFromZoomToPanSetsState() {
        let coordinator = GestureCoordinator()
        coordinator.zoomBegan()
        coordinator.zoomChanged(scale: 2.0, anchor: center, center: center)

        coordinator.transitionFromZoomToPan(currentTranslation: CGPoint(x: 50, y: 30))

        XCTAssertEqual(coordinator.state, .dragging)
    }

    func testTransitionFromZoomToPanPreservesOffset() {
        let coordinator = GestureCoordinator()
        coordinator.zoomBegan()
        coordinator.zoomChanged(scale: 2.0, anchor: center, center: center)

        let offsetBeforeTransition = coordinator.transform.offset
        coordinator.transitionFromZoomToPan(currentTranslation: CGPoint(x: 50, y: 30))

        // Offset should remain unchanged immediately after transition
        XCTAssertEqual(coordinator.transform.offset, offsetBeforeTransition)
    }

    func testTransitionFromZoomToPanContinuesSmoothly() {
        let coordinator = GestureCoordinator()
        coordinator.zoomBegan()
        coordinator.zoomChanged(scale: 2.0, anchor: center, center: center)

        let offsetBeforeTransition = coordinator.transform.offset

        // Transition with current translation of (50, 30)
        coordinator.transitionFromZoomToPan(currentTranslation: CGPoint(x: 50, y: 30))

        // Pan with a slightly increased translation (user moved finger 10pt right)
        coordinator.panChanged(CGPoint(x: 60, y: 30), center: center)

        // Offset should only change by the delta (10, 0), not by the full translation
        XCTAssertEqual(coordinator.transform.offset.x, offsetBeforeTransition.x + 10, accuracy: 0.001)
        XCTAssertEqual(coordinator.transform.offset.y, offsetBeforeTransition.y, accuracy: 0.001)
    }

    func testTransitionFromPanToZoomSetsState() {
        let coordinator = GestureCoordinator()
        coordinator.panBegan()
        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)

        coordinator.transitionFromPanToZoom(currentScale: 1.0, center: center)

        XCTAssertEqual(coordinator.state, .zooming)
    }

    func testTransitionFromPanToZoomPreservesTransform() {
        let coordinator = GestureCoordinator()
        coordinator.panBegan()
        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)

        let transformBeforeTransition = coordinator.transform

        coordinator.transitionFromPanToZoom(currentScale: 1.0, center: center)

        // Transform should remain unchanged immediately after transition
        XCTAssertEqual(coordinator.transform.scale, transformBeforeTransition.scale, accuracy: 0.001)
        XCTAssertEqual(coordinator.transform.offset.x, transformBeforeTransition.offset.x, accuracy: 0.001)
        XCTAssertEqual(coordinator.transform.offset.y, transformBeforeTransition.offset.y, accuracy: 0.001)
    }

    func testTransitionFromPanToZoomHandlesCumulativeScale() {
        let coordinator = GestureCoordinator()

        // Start with a zoom to 2x
        coordinator.zoomChanged(scale: 2.0, anchor: center, center: center)
        coordinator.zoomEnded(center: center)

        // Pan around
        coordinator.panBegan()
        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)

        // Transition to zoom - gesture reports cumulative scale of 2.0 from original gesture
        coordinator.transitionFromPanToZoom(currentScale: 2.0, center: center)

        // Now zoom a tiny bit more - gesture reports 2.1 (5% more than baseline)
        coordinator.zoomChanged(scale: 2.1, anchor: center, center: center)

        // Scale should be 2.0 * (2.1 / 2.0) = 2.1, NOT 2.0 * 2.1 = 4.2
        XCTAssertEqual(coordinator.transform.scale, 2.1, accuracy: 0.01)
    }

    func testNormalPanDoesNotUseBaseline() {
        // Verify that normal pan gestures (starting fresh) work correctly
        let coordinator = GestureCoordinator()

        // Fresh pan should start from zero
        coordinator.panBegan()
        coordinator.panChanged(CGPoint(x: 100, y: 50), center: center)

        XCTAssertEqual(coordinator.transform.offset.x, 100, accuracy: 0.001)
        XCTAssertEqual(coordinator.transform.offset.y, 50, accuracy: 0.001)
    }
}

// MARK: - Rubber Band Tests

@MainActor
final class GestureCoordinatorRubberBandTests: XCTestCase {

    let center = CGPoint(x: 200, y: 200)

    func testRubberBandAppliesAtBounds() {
        let config = GestureCoordinatorConfiguration(
            contentBounds: PhysicsBounds(
                min: CGPoint(x: -100, y: -100),
                max: CGPoint(x: 100, y: 100)
            ),
            rubberBandEnabled: true
        )
        let coordinator = GestureCoordinator(configuration: config)

        // Drag way past the max bound
        coordinator.panChanged(CGPoint(x: 300, y: 0), center: center)

        // Should be less than 300 due to rubber-band
        XCTAssertLessThan(coordinator.transform.offset.x, 300)
        // But more than the bound
        XCTAssertGreaterThan(coordinator.transform.offset.x, 100)
    }

    func testRubberBandDisabled() {
        let config = GestureCoordinatorConfiguration(
            contentBounds: PhysicsBounds(
                min: CGPoint(x: -100, y: -100),
                max: CGPoint(x: 100, y: 100)
            ),
            rubberBandEnabled: false
        )
        let coordinator = GestureCoordinator(configuration: config)

        // Drag past bounds
        coordinator.panChanged(CGPoint(x: 300, y: 0), center: center)

        // Should be exactly 300 (no rubber-band)
        XCTAssertEqual(coordinator.transform.offset.x, 300, accuracy: 0.001)
    }
}

// MARK: - Animation Tests

@MainActor
final class GestureCoordinatorAnimationTests: XCTestCase {

    let center = CGPoint(x: 200, y: 200)

    func testMomentumUpdatesPosition() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(CGPoint(x: 0, y: 0), center: center)
        coordinator.panEnded(velocity: CGPoint(x: 500, y: 0), center: center)

        XCTAssertEqual(coordinator.state, .momentum)

        let initialOffset = coordinator.transform.offset

        // Run a few update cycles
        for _ in 0..<10 {
            coordinator.update()
        }

        // Position should have changed
        XCTAssertNotEqual(coordinator.transform.offset.x, initialOffset.x)
    }

    func testMomentumEventuallyStops() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(.zero, center: center)
        coordinator.panEnded(velocity: CGPoint(x: 100, y: 0), center: center)

        // Run many updates until it stops
        var iterations = 0
        while coordinator.isAnimating && iterations < 1000 {
            coordinator.update()
            iterations += 1
        }

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(coordinator.isAnimating)
    }

    func testStopAnimationStopsImmediately() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(.zero, center: center)
        coordinator.panEnded(velocity: CGPoint(x: 500, y: 0), center: center)

        XCTAssertTrue(coordinator.isAnimating)

        coordinator.stopAnimation()

        XCTAssertFalse(coordinator.isAnimating)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testUpdateReturnsFalseWhenIdle() {
        let coordinator = GestureCoordinator()
        let result = coordinator.update()

        XCTAssertFalse(result)
    }
}

// MARK: - State Management Tests

@MainActor
final class GestureCoordinatorStateTests: XCTestCase {

    let center = CGPoint(x: 200, y: 200)

    func testReset() {
        let coordinator = GestureCoordinator()

        // Make some changes
        coordinator.panChanged(CGPoint(x: 100, y: 50), center: center)
        coordinator.zoomChanged(scale: 2.0, anchor: center, center: center)

        coordinator.reset()

        XCTAssertEqual(coordinator.transform.scale, 1.0)
        XCTAssertEqual(coordinator.transform.offset, .zero)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testSetTransformDirectly() {
        let coordinator = GestureCoordinator()

        let newTransform = Transform(scale: 1.5, offset: CGPoint(x: 50, y: 30))
        coordinator.setTransformDirectly(newTransform)

        XCTAssertEqual(coordinator.transform.scale, 1.5, accuracy: 0.001)
        XCTAssertEqual(coordinator.transform.offset.x, 50, accuracy: 0.001)
        XCTAssertEqual(coordinator.transform.offset.y, 30, accuracy: 0.001)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testSetTransformDirectlyStopsAnimation() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(.zero, center: center)
        coordinator.panEnded(velocity: CGPoint(x: 500, y: 0), center: center)

        XCTAssertTrue(coordinator.isAnimating)

        let newTransform = Transform(scale: 1.0, offset: CGPoint(x: 100, y: 0))
        coordinator.setTransformDirectly(newTransform)

        XCTAssertFalse(coordinator.isAnimating)
        XCTAssertEqual(coordinator.transform.offset.x, 100, accuracy: 0.001)
    }

    func testOnTransformChangedCallback() {
        let coordinator = GestureCoordinator()
        var callbackCount = 0
        var lastTransform: Transform?

        coordinator.onTransformChanged = { transform in
            callbackCount += 1
            lastTransform = transform
        }

        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)

        XCTAssertEqual(callbackCount, 1)
        XCTAssertNotNil(lastTransform)
        XCTAssertEqual(lastTransform!.offset.x, 50, accuracy: 0.001)
    }

    func testOnStateChangedCallback() {
        let coordinator = GestureCoordinator()
        var stateChanges: [GestureState] = []

        coordinator.onStateChanged = { state in
            stateChanges.append(state)
        }

        coordinator.panBegan()
        coordinator.panEnded(velocity: .zero, center: center)

        XCTAssertEqual(stateChanges, [.dragging, .idle])
    }
}

// MARK: - Hit Testing Integration Tests

@MainActor
final class GestureCoordinatorHitTestingTests: XCTestCase {

    let center = CGPoint(x: 200, y: 200)
    let nodes = [
        TestHittableNode(id: "A", x: 100, y: 100, radius: 22),
        TestHittableNode(id: "B", x: 200, y: 100, radius: 22),
    ]

    func testHitTestWithIdentityTransform() {
        let coordinator = GestureCoordinator()

        let result = coordinator.hitTest(at: CGPoint(x: 100, y: 100), in: nodes, center: center)

        XCTAssertTrue(result.didHit)
        XCTAssertEqual(result.closest?.id, "A")
    }

    func testHitTestWithPannedTransform() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(CGPoint(x: 50, y: 0), center: center)

        // Node A at canvas (100, 100) now appears at viewport (150, 100)
        let result = coordinator.hitTest(at: CGPoint(x: 150, y: 100), in: nodes, center: center)

        XCTAssertTrue(result.didHit)
        XCTAssertEqual(result.closest?.id, "A")
    }

    func testWouldHit() {
        let coordinator = GestureCoordinator()

        XCTAssertTrue(coordinator.wouldHit(at: CGPoint(x: 100, y: 100), in: nodes, center: center))
        XCTAssertFalse(coordinator.wouldHit(at: CGPoint(x: 0, y: 0), in: nodes, center: center))
    }

    func testToCanvasConversion() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)

        let viewportPoint = CGPoint(x: 150, y: 130)
        let canvasPoint = coordinator.toCanvas(viewportPoint, center: center)

        // With +50, +30 offset, viewport (150, 130) should map to canvas (100, 100)
        XCTAssertEqual(canvasPoint.x, 100, accuracy: 0.001)
        XCTAssertEqual(canvasPoint.y, 100, accuracy: 0.001)
    }

    func testToViewportConversion() {
        let coordinator = GestureCoordinator()
        coordinator.panChanged(CGPoint(x: 50, y: 30), center: center)

        let canvasPoint = CGPoint(x: 100, y: 100)
        let viewportPoint = coordinator.toViewport(canvasPoint, center: center)

        // With +50, +30 offset, canvas (100, 100) should map to viewport (150, 130)
        XCTAssertEqual(viewportPoint.x, 150, accuracy: 0.001)
        XCTAssertEqual(viewportPoint.y, 130, accuracy: 0.001)
    }
}

// MARK: - Configuration Update Tests

@MainActor
final class GestureCoordinatorConfigurationTests: XCTestCase {

    func testConfigurationUpdateUpdatesTransform() {
        let coordinator = GestureCoordinator()

        // Set scale to 2.0
        coordinator.zoomChanged(scale: 2.0, anchor: CGPoint(x: 200, y: 200), center: CGPoint(x: 200, y: 200))
        coordinator.zoomEnded(center: CGPoint(x: 200, y: 200))

        // Now update configuration with lower max scale
        var newConfig = GestureCoordinatorConfiguration()
        newConfig.transform = TransformConfiguration(minScale: 1.0, maxScale: 1.5)
        coordinator.configuration = newConfig

        // Scale should be clamped to new max
        XCTAssertEqual(coordinator.transform.scale, 1.5, accuracy: 0.001)
    }
}
