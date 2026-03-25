// Tests/MercurialTests/GraphLayoutTests.swift

import XCTest
@testable import Mercurial

final class GraphLayoutTests: XCTestCase {

    let canvasSize = CGSize(width: 300, height: 200)

    // MARK: - Edge Cases

    func testEmptyNodesReturnsEmptyResult() {
        let result = GraphLayout.compute(nodes: [], edges: [], size: canvasSize)
        XCTAssertTrue(result.positions.isEmpty)
        XCTAssertEqual(result.stress, 0)
        XCTAssertEqual(result.iterations, 0)
    }

    func testSingleNodePlacedAtCenter() {
        let nodes = [GraphNode(id: "A")]
        let result = GraphLayout.compute(nodes: nodes, edges: [], size: canvasSize)
        XCTAssertEqual(result.positions.count, 1)
        let pos = result.positions["A"]!
        XCTAssertEqual(pos.x, 150, accuracy: 1)
        XCTAssertEqual(pos.y, 100, accuracy: 1)
        XCTAssertEqual(result.iterations, 0)
    }

    func testAllNodesGetPositions() {
        let nodes = ["A", "B", "C", "D"].map { GraphNode(id: $0) }
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 0.8),
            GraphEdge(source: "B", target: "C", weight: 0.5),
            GraphEdge(source: "C", target: "D", weight: 0.3),
        ]
        let result = GraphLayout.compute(nodes: nodes, edges: edges, size: canvasSize)
        XCTAssertEqual(result.positions.count, 4)
        for node in nodes {
            XCTAssertNotNil(result.positions[node.id])
        }
    }

    // MARK: - Clustering (weight → proximity)

    func testHighWeightEdgeProducesCloserNodes() {
        let nodes = ["A", "B", "C"].map { GraphNode(id: $0) }
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 1.0),  // tight
            GraphEdge(source: "A", target: "C", weight: 0.1),  // loose
        ]
        let result = GraphLayout.compute(nodes: nodes, edges: edges, size: canvasSize)

        let posA = result.positions["A"]!
        let posB = result.positions["B"]!
        let posC = result.positions["C"]!

        let distAB = posA.distance(to: posB)
        let distAC = posA.distance(to: posC)

        XCTAssertLessThan(distAB, distAC, "High-weight edge (A-B) should produce closer nodes than low-weight (A-C)")
    }

    // MARK: - Bounds

    func testPositionsWithinBounds() {
        let nodes = (0..<10).map { GraphNode(id: "N\($0)") }
        var edges: [GraphEdge] = []
        for i in 0..<9 {
            edges.append(GraphEdge(source: "N\(i)", target: "N\(i+1)", weight: 0.5))
        }
        let config = GraphLayoutConfiguration(padding: 10)
        let result = GraphLayout.compute(nodes: nodes, edges: edges, size: canvasSize, configuration: config)

        for (_, pos) in result.positions {
            XCTAssertGreaterThanOrEqual(pos.x, 0, "Node should be within horizontal bounds")
            XCTAssertLessThanOrEqual(pos.x, canvasSize.width, "Node should be within horizontal bounds")
            XCTAssertGreaterThanOrEqual(pos.y, 0, "Node should be within vertical bounds")
            XCTAssertLessThanOrEqual(pos.y, canvasSize.height, "Node should be within vertical bounds")
        }
    }

    // MARK: - No Edges (disconnected)

    func testNoEdgesProducesSpreadLayout() {
        let nodes = ["A", "B", "C"].map { GraphNode(id: $0) }
        let result = GraphLayout.compute(nodes: nodes, edges: [], size: canvasSize)

        let posA = result.positions["A"]!
        let posB = result.positions["B"]!
        let posC = result.positions["C"]!

        // All three should be distinct positions
        XCTAssertGreaterThan(posA.distance(to: posB), 10)
        XCTAssertGreaterThan(posB.distance(to: posC), 10)
        XCTAssertGreaterThan(posA.distance(to: posC), 10)
    }

    // MARK: - Collision Avoidance

    func testNodesDoNotOverlap() {
        let nodes = (0..<6).map { GraphNode(id: "N\($0)", radius: 15) }
        // All connected to N0 — hub graph that wants to cluster
        var edges: [GraphEdge] = []
        for i in 1..<6 {
            edges.append(GraphEdge(source: "N0", target: "N\(i)", weight: 1.0))
        }
        let result = GraphLayout.compute(nodes: nodes, edges: edges, size: canvasSize)

        // Check all pairs for minimum distance
        let ids = nodes.map(\.id)
        for i in 0..<ids.count {
            for j in (i+1)..<ids.count {
                let pi = result.positions[ids[i]]!
                let pj = result.positions[ids[j]]!
                let minDist = nodes[i].radius + nodes[j].radius
                let dist = pi.distance(to: pj)
                XCTAssertGreaterThanOrEqual(dist, minDist - 1, "Nodes \(ids[i]) and \(ids[j]) overlap")
            }
        }
    }

    // MARK: - Convergence

    func testSolverConverges() {
        let nodes = ["A", "B", "C", "D"].map { GraphNode(id: $0) }
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 0.8),
            GraphEdge(source: "B", target: "C", weight: 0.6),
            GraphEdge(source: "C", target: "D", weight: 0.4),
            GraphEdge(source: "D", target: "A", weight: 0.5),
        ]
        let config = GraphLayoutConfiguration(maxIterations: 100)
        let result = GraphLayout.compute(nodes: nodes, edges: edges, size: canvasSize, configuration: config)

        XCTAssertGreaterThan(result.iterations, 0, "Solver should run at least one iteration")
        XCTAssertLessThan(result.iterations, 100, "Solver should converge before max iterations")
    }

    // MARK: - Duplicate Edges

    func testDuplicateEdgesUsesMaxWeight() {
        let nodes = ["A", "B", "C"].map { GraphNode(id: $0) }
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 0.2),
            GraphEdge(source: "A", target: "B", weight: 0.9),  // duplicate, higher weight
            GraphEdge(source: "B", target: "C", weight: 0.2),
        ]
        let result = GraphLayout.compute(nodes: nodes, edges: edges, size: canvasSize)

        let posA = result.positions["A"]!
        let posB = result.positions["B"]!
        let posC = result.positions["C"]!

        // A-B should be closer than B-C due to the max weight (0.9 vs 0.2)
        XCTAssertLessThan(posA.distance(to: posB), posB.distance(to: posC))
    }

    // MARK: - Previous Positions

    func testPreviousPositionsUsedAsInitial() {
        let nodes = ["A", "B"].map { GraphNode(id: $0) }
        let edges = [GraphEdge(source: "A", target: "B", weight: 0.5)]

        let prev: [String: CGPoint] = [
            "A": CGPoint(x: 50, y: 50),
            "B": CGPoint(x: 250, y: 150),
        ]

        let result = GraphLayout.compute(
            nodes: nodes, edges: edges, size: canvasSize, previousPositions: prev
        )

        // Just verify it produces valid output with previousPositions
        XCTAssertEqual(result.positions.count, 2)
    }
}
