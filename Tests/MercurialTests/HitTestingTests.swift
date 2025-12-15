import XCTest
@testable import Mercurial

// MARK: - Test Fixtures

struct TestNode: Hittable, Sendable {
    let id: String
    var position: CGPoint
    var hitRadius: CGFloat

    init(id: String, x: CGFloat, y: CGFloat, radius: CGFloat = 22) {
        self.id = id
        self.position = CGPoint(x: x, y: y)
        self.hitRadius = radius
    }
}

struct TestRectNode: RectHittable {
    let id: String
    var position: CGPoint
    var hitSize: CGSize

    init(id: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.id = id
        self.position = CGPoint(x: x, y: y)
        self.hitSize = CGSize(width: width, height: height)
    }
}

// MARK: - Hittable Protocol Tests

final class HittableTests: XCTestCase {

    func testHitTestCenter() {
        let node = TestNode(id: "test", x: 100, y: 100, radius: 22)
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 100, y: 100)))
    }

    func testHitTestWithinRadius() {
        let node = TestNode(id: "test", x: 100, y: 100, radius: 22)
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 110, y: 100)))  // 10pt away
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 100, y: 120)))  // 20pt away
    }

    func testHitTestOnEdge() {
        let node = TestNode(id: "test", x: 100, y: 100, radius: 22)
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 122, y: 100)))  // Exactly on edge
    }

    func testHitTestOutsideRadius() {
        let node = TestNode(id: "test", x: 100, y: 100, radius: 22)
        XCTAssertFalse(node.hitTest(location: CGPoint(x: 130, y: 100)))  // 30pt away
        XCTAssertFalse(node.hitTest(location: CGPoint(x: 100, y: 130)))  // 30pt away
    }

    func testHitTestDiagonal() {
        let node = TestNode(id: "test", x: 100, y: 100, radius: 22)
        // Diagonal distance: sqrt(15^2 + 15^2) ≈ 21.2pt < 22pt
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 115, y: 115)))
        // Diagonal distance: sqrt(20^2 + 20^2) ≈ 28.3pt > 22pt
        XCTAssertFalse(node.hitTest(location: CGPoint(x: 120, y: 120)))
    }

    func testDistanceTo() {
        let node = TestNode(id: "test", x: 0, y: 0, radius: 22)
        XCTAssertEqual(node.distance(to: CGPoint(x: 3, y: 4)), 5, accuracy: 0.001)
    }
}

// MARK: - RectHittable Tests

final class RectHittableTests: XCTestCase {

    func testHitTestCenter() {
        let node = TestRectNode(id: "test", x: 100, y: 100, width: 44, height: 44)
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 100, y: 100)))
    }

    func testHitTestWithinRect() {
        let node = TestRectNode(id: "test", x: 100, y: 100, width: 44, height: 44)
        // Rectangle spans 78-122 in x, 78-122 in y
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 80, y: 80)))
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 120, y: 120)))
    }

    func testHitTestOnEdge() {
        let node = TestRectNode(id: "test", x: 100, y: 100, width: 44, height: 44)
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 78, y: 100)))  // Left edge
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 122, y: 100))) // Right edge
    }

    func testHitTestOutsideRect() {
        let node = TestRectNode(id: "test", x: 100, y: 100, width: 44, height: 44)
        XCTAssertFalse(node.hitTest(location: CGPoint(x: 77, y: 100)))  // Just outside left
        XCTAssertFalse(node.hitTest(location: CGPoint(x: 123, y: 100))) // Just outside right
    }

    func testHitTestNonSquare() {
        let node = TestRectNode(id: "test", x: 100, y: 100, width: 100, height: 20)
        // Rectangle spans 50-150 in x, 90-110 in y
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 60, y: 100)))   // Wide reach in x
        XCTAssertFalse(node.hitTest(location: CGPoint(x: 100, y: 80)))  // Short reach in y
    }
}

// MARK: - HitTest Helper Tests

final class HitTestHelpersTests: XCTestCase {

    let nodes = [
        TestNode(id: "A", x: 100, y: 100, radius: 22),
        TestNode(id: "B", x: 200, y: 100, radius: 22),
        TestNode(id: "C", x: 150, y: 150, radius: 22),
    ]

    func testFindHitsNone() {
        let hits = HitTest.findHits(at: CGPoint(x: 0, y: 0), in: nodes)
        XCTAssertTrue(hits.isEmpty)
    }

    func testFindHitsSingle() {
        let hits = HitTest.findHits(at: CGPoint(x: 100, y: 100), in: nodes)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.id, "A")
    }

    func testFindHitsMultiple() {
        // Create overlapping nodes
        let overlapping = [
            TestNode(id: "A", x: 100, y: 100, radius: 30),
            TestNode(id: "B", x: 120, y: 100, radius: 30),  // Overlaps with A
        ]
        let hits = HitTest.findHits(at: CGPoint(x: 110, y: 100), in: overlapping)
        XCTAssertEqual(hits.count, 2)
    }

    func testFindClosestNone() {
        let closest = HitTest.findClosest(at: CGPoint(x: 0, y: 0), in: nodes)
        XCTAssertNil(closest)
    }

    func testFindClosestSingle() {
        let closest = HitTest.findClosest(at: CGPoint(x: 100, y: 100), in: nodes)
        XCTAssertEqual(closest?.id, "A")
    }

    func testFindClosestFromMultiple() {
        // Create overlapping nodes
        let overlapping = [
            TestNode(id: "A", x: 100, y: 100, radius: 30),
            TestNode(id: "B", x: 120, y: 100, radius: 30),
        ]
        // Tap at 115, which is closer to B (5pt) than A (15pt)
        let closest = HitTest.findClosest(at: CGPoint(x: 115, y: 100), in: overlapping)
        XCTAssertEqual(closest?.id, "B")
    }
}

// MARK: - Transform-Aware Hit Testing Tests

final class TransformAwareHitTestingTests: XCTestCase {

    let nodes = [
        TestNode(id: "A", x: 100, y: 100, radius: 22),
        TestNode(id: "B", x: 200, y: 100, radius: 22),
    ]
    let center = CGPoint(x: 200, y: 200)

    func testHitTestWithIdentityTransform() {
        let transform = Transform.identity

        let hits = HitTest.findHits(
            at: CGPoint(x: 100, y: 100),
            in: nodes,
            transform: transform,
            center: center
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.id, "A")
    }

    func testHitTestWithZoom() {
        // At 2x zoom, node A at canvas (100, 100) appears at viewport position
        // that's offset from center
        let transform = Transform(scale: 2.0, offset: .zero)

        // Node A is at canvas (100, 100)
        // Center is (200, 200), so node is 100pt left and 100pt up from center
        // At 2x zoom, it appears 200pt left and 200pt up from center
        // So viewport position is (0, 0)
        let hits = HitTest.findHits(
            at: CGPoint(x: 0, y: 0),
            in: nodes,
            transform: transform,
            center: center
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.id, "A")
    }

    func testHitTestWithPan() {
        let transform = Transform(scale: 1.0, offset: CGPoint(x: 50, y: 0))

        // Node A is at canvas (100, 100)
        // With +50 pan, it appears at viewport (150, 100)
        let hits = HitTest.findHits(
            at: CGPoint(x: 150, y: 100),
            in: nodes,
            transform: transform,
            center: center
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.id, "A")
    }

    func testHitAreaScaling() {
        let transform = Transform(scale: 3.0, offset: .zero)
        // At 3x with 0.3 multiplier, hit areas scale to 1.6x
        // Original radius 22 * 1.6 = 35.2

        // Node A at canvas (100, 100)
        // At 3x zoom relative to center (200, 200):
        // - Distance from center: -100, -100
        // - Scaled distance: -300, -300
        // - Viewport position: -100, -100

        // Tap 30pt from node center (within scaled radius 35.2, outside original 22)
        let nodeViewport = transform.toViewport(CGPoint(x: 100, y: 100), center: center)
        let tapLocation = CGPoint(x: nodeViewport.x + 30, y: nodeViewport.y)

        let hits = HitTest.findHits(
            at: tapLocation,
            in: nodes,
            transform: transform,
            center: center
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.id, "A")
    }

    func testWouldHit() {
        let transform = Transform.identity

        XCTAssertTrue(HitTest.wouldHit(
            at: CGPoint(x: 100, y: 100),
            in: nodes,
            transform: transform,
            center: center
        ))

        XCTAssertFalse(HitTest.wouldHit(
            at: CGPoint(x: 0, y: 0),
            in: nodes,
            transform: transform,
            center: center
        ))
    }

    func testFindClosestWithTransform() {
        let transform = Transform.identity

        let closest = HitTest.findClosest(
            at: CGPoint(x: 100, y: 100),
            in: nodes,
            transform: transform,
            center: center
        )
        XCTAssertEqual(closest?.id, "A")
    }
}

// MARK: - HitTestResult Tests

final class HitTestResultTests: XCTestCase {

    let nodes = [
        TestNode(id: "A", x: 100, y: 100, radius: 22),
        TestNode(id: "B", x: 200, y: 100, radius: 22),
    ]
    let center = CGPoint(x: 200, y: 200)

    func testResultWithHits() {
        let transform = Transform.identity

        let result = HitTest.test(
            at: CGPoint(x: 100, y: 100),
            in: nodes,
            transform: transform,
            center: center
        )

        XCTAssertTrue(result.didHit)
        XCTAssertFalse(result.isEmptySpaceTap)
        XCTAssertEqual(result.hits.count, 1)
        XCTAssertEqual(result.closest?.id, "A")
        XCTAssertEqual(result.canvasLocation.x, 100, accuracy: 0.001)
        XCTAssertEqual(result.canvasLocation.y, 100, accuracy: 0.001)
    }

    func testResultEmptySpace() {
        let transform = Transform.identity

        let result = HitTest.test(
            at: CGPoint(x: 0, y: 0),
            in: nodes,
            transform: transform,
            center: center
        )

        XCTAssertFalse(result.didHit)
        XCTAssertTrue(result.isEmptySpaceTap)
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertNil(result.closest)
    }

    func testResultCanvasLocation() {
        let transform = Transform(scale: 2.0, offset: CGPoint(x: 50, y: 30))

        let result = HitTest.test(
            at: CGPoint(x: 250, y: 230),
            in: nodes,
            transform: transform,
            center: center
        )

        // Verify canvas location is correctly transformed
        let expectedCanvas = transform.toCanvas(CGPoint(x: 250, y: 230), center: center)
        XCTAssertEqual(result.canvasLocation.x, expectedCanvas.x, accuracy: 0.001)
        XCTAssertEqual(result.canvasLocation.y, expectedCanvas.y, accuracy: 0.001)
    }
}
