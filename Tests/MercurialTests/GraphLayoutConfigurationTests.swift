import XCTest
@testable import Mercurial

final class GraphLayoutConfigurationTests: XCTestCase {

    func testGraphNodeDefaultRadius() {
        let node = GraphNode(id: "A")
        XCTAssertEqual(node.radius, 12)
    }

    func testGraphNodeCustomRadius() {
        let node = GraphNode(id: "A", radius: 20)
        XCTAssertEqual(node.radius, 20)
    }

    func testGraphNodeIdentifiable() {
        let node = GraphNode(id: "test")
        XCTAssertEqual(node.id, "test")
    }

    func testGraphEdgeDefaultWeight() {
        let edge = GraphEdge(source: "A", target: "B")
        XCTAssertEqual(edge.weight, 0.5)
    }

    func testGraphEdgeWeightClampsHigh() {
        let edge = GraphEdge(source: "A", target: "B", weight: 5.0)
        XCTAssertEqual(edge.weight, 1.0)
    }

    func testGraphEdgeWeightClampsLowToFloor() {
        let edge = GraphEdge(source: "A", target: "B", weight: 0.0)
        XCTAssertEqual(edge.weight, 0.01, accuracy: 0.001)
    }

    func testGraphEdgeWeightClampsNegativeToFloor() {
        let edge = GraphEdge(source: "A", target: "B", weight: -1.0)
        XCTAssertEqual(edge.weight, 0.01, accuracy: 0.001)
    }

    func testPositionedGraphNodeHittable() {
        let node = PositionedGraphNode(id: "A", position: CGPoint(x: 100, y: 100), hitRadius: 22)
        XCTAssertTrue(node.hitTest(location: CGPoint(x: 110, y: 110)))
        XCTAssertFalse(node.hitTest(location: CGPoint(x: 200, y: 200)))
    }

    func testDefaultConfigurationValues() {
        let config = GraphLayoutConfiguration.default
        XCTAssertEqual(config.spacing, 60)
        XCTAssertEqual(config.weightExponent, 1.5)
        XCTAssertEqual(config.padding, 20)
        XCTAssertEqual(config.maxIterations, 50)
    }

    func testCompactHasSmallerSpacing() {
        XCTAssertLessThan(
            GraphLayoutConfiguration.compact.spacing,
            GraphLayoutConfiguration.default.spacing
        )
    }

    func testSpreadHasLargerSpacing() {
        XCTAssertGreaterThan(
            GraphLayoutConfiguration.spread.spacing,
            GraphLayoutConfiguration.default.spacing
        )
    }

    func testAnimationDefaultValues() {
        let config = GraphAnimationConfiguration.default
        XCTAssertEqual(config.stiffness, 120)
        XCTAssertEqual(config.damping, 18)
        XCTAssertEqual(config.friction, 0.85)
    }
}
