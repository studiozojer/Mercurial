import XCTest
@testable import Mercurial

final class FocalLayoutTests: XCTestCase {

    let size = CGSize(width: 400, height: 300)

    // MARK: - Edge Cases

    func testEmptyGraph() {
        let result = FocalLayout.compute(nodes: [], edges: [], size: size)
        XCTAssertTrue(result.positions.isEmpty)
    }

    func testSingleNode() {
        let nodes = [GraphNode(id: "A")]
        let result = FocalLayout.compute(nodes: nodes, edges: [], size: size)
        let pos = result.positions["A"]!
        XCTAssertEqual(pos.x, 200, accuracy: 1)
        XCTAssertEqual(pos.y, 150, accuracy: 1)
    }

    // MARK: - Focal Point Identification

    func testHighestWeightNodeIsFocal() {
        // Node B has the most edge weight — it should be near center
        let nodes = [
            GraphNode(id: "A"), GraphNode(id: "B"), GraphNode(id: "C"),
        ]
        let edges = [
            GraphEdge(source: "B", target: "A", weight: 0.9),
            GraphEdge(source: "B", target: "C", weight: 0.8),
        ]
        let result = FocalLayout.compute(nodes: nodes, edges: edges, size: size)

        let posB = result.positions["B"]!
        let center = CGPoint(x: 200, y: 150)
        let distFromCenter = sqrt(pow(posB.x - center.x, 2) + pow(posB.y - center.y, 2))
        // Focal node should be near center
        XCTAssertLessThan(distFromCenter, 100)
    }

    // MARK: - Weight Affects Distance

    func testTightWeightCloserThanLoose() {
        let nodes = [
            GraphNode(id: "focal"),
            GraphNode(id: "tight"),
            GraphNode(id: "loose"),
        ]
        let edges = [
            GraphEdge(source: "focal", target: "tight", weight: 0.9),
            GraphEdge(source: "focal", target: "loose", weight: 0.2),
        ]
        let result = FocalLayout.compute(nodes: nodes, edges: edges, size: size)

        let focalPos = result.positions["focal"]!
        let tightPos = result.positions["tight"]!
        let loosePos = result.positions["loose"]!

        let tightDist = sqrt(pow(tightPos.x - focalPos.x, 2) + pow(tightPos.y - focalPos.y, 2))
        let looseDist = sqrt(pow(loosePos.x - focalPos.x, 2) + pow(loosePos.y - focalPos.y, 2))

        XCTAssertLessThan(tightDist, looseDist, "Tight connection should be closer to focal than loose")
    }

    // MARK: - Positions Within Bounds

    func testAllNodesWithinBounds() {
        let nodes = (0..<15).map { GraphNode(id: "n\($0)", radius: 8) }
        var edges: [GraphEdge] = []
        // Connect each to the first node
        for i in 1..<15 {
            edges.append(GraphEdge(source: "n0", target: "n\(i)", weight: CGFloat.random(in: 0.1...0.9)))
        }

        let result = FocalLayout.compute(nodes: nodes, edges: edges, size: size)

        for node in nodes {
            let pos = result.positions[node.id]!
            XCTAssertGreaterThanOrEqual(pos.x, node.radius)
            XCTAssertLessThanOrEqual(pos.x, size.width - node.radius)
            XCTAssertGreaterThanOrEqual(pos.y, node.radius)
            XCTAssertLessThanOrEqual(pos.y, size.height - node.radius)
        }
    }

    // MARK: - No Overlaps

    func testNoNodeOverlaps() {
        let nodes = (0..<10).map { GraphNode(id: "n\($0)", radius: 10) }
        var edges: [GraphEdge] = []
        for i in 1..<10 {
            edges.append(GraphEdge(source: "n0", target: "n\(i)", weight: 0.5))
        }

        let result = FocalLayout.compute(nodes: nodes, edges: edges, size: size)

        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let posI = result.positions[nodes[i].id]!
                let posJ = result.positions[nodes[j].id]!
                let dx = posJ.x - posI.x
                let dy = posJ.y - posI.y
                let dist = sqrt(dx * dx + dy * dy)
                let minDist = nodes[i].radius + nodes[j].radius
                XCTAssertGreaterThan(dist, minDist - 1, "Nodes \(nodes[i].id) and \(nodes[j].id) overlap")
            }
        }
    }

    // MARK: - Deterministic

    func testDeterministicOutput() {
        let nodes = [
            GraphNode(id: "A"), GraphNode(id: "B"),
            GraphNode(id: "C"), GraphNode(id: "D"),
        ]
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 0.8),
            GraphEdge(source: "B", target: "C", weight: 0.5),
            GraphEdge(source: "C", target: "D", weight: 0.3),
        ]

        let result1 = FocalLayout.compute(nodes: nodes, edges: edges, size: size)
        let result2 = FocalLayout.compute(nodes: nodes, edges: edges, size: size)

        for node in nodes {
            XCTAssertEqual(result1.positions[node.id]!.x, result2.positions[node.id]!.x, accuracy: 0.01)
            XCTAssertEqual(result1.positions[node.id]!.y, result2.positions[node.id]!.y, accuracy: 0.01)
        }
    }

    // MARK: - Disconnected Nodes

    func testDisconnectedNodesStillPlaced() {
        let nodes = [
            GraphNode(id: "A"), GraphNode(id: "B"),
            GraphNode(id: "lonely"),
        ]
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 0.5),
        ]
        let result = FocalLayout.compute(nodes: nodes, edges: edges, size: size)

        XCTAssertNotNil(result.positions["lonely"])
        // Should be within bounds
        let pos = result.positions["lonely"]!
        XCTAssertGreaterThan(pos.x, 0)
        XCTAssertLessThan(pos.x, size.width)
    }

    // MARK: - Activation-Like Graph

    func testActivationGraphLayout() {
        // Simulate a real activation pattern: transit nodes connected to natal nodes
        let nodes = [
            GraphNode(id: "t_Jupiter", radius: 6),
            GraphNode(id: "t_Mars", radius: 6),
            GraphNode(id: "t_Venus", radius: 6),
            GraphNode(id: "n_Mercury", radius: 9),
            GraphNode(id: "n_Moon", radius: 9),
            GraphNode(id: "n_Sun", radius: 9),
            GraphNode(id: "n_Venus", radius: 9),
        ]
        let edges = [
            GraphEdge(source: "t_Jupiter", target: "n_Mercury", weight: 0.9),
            GraphEdge(source: "t_Jupiter", target: "n_Moon", weight: 0.85),
            GraphEdge(source: "t_Mars", target: "n_Venus", weight: 0.7),
            GraphEdge(source: "t_Mars", target: "n_Sun", weight: 0.6),
            GraphEdge(source: "t_Venus", target: "n_Sun", weight: 0.5),
        ]

        let result = FocalLayout.compute(nodes: nodes, edges: edges, size: CGSize(width: 350, height: 280))

        // All positions should exist
        for node in nodes {
            XCTAssertNotNil(result.positions[node.id], "Missing position for \(node.id)")
        }

        // Jupiter's targets (Mercury, Moon) should be closer to Jupiter than to Mars
        let jupPos = result.positions["t_Jupiter"]!
        let marsPos = result.positions["t_Mars"]!
        let mercPos = result.positions["n_Mercury"]!

        let mercToJup = sqrt(pow(mercPos.x - jupPos.x, 2) + pow(mercPos.y - jupPos.y, 2))
        let mercToMars = sqrt(pow(mercPos.x - marsPos.x, 2) + pow(mercPos.y - marsPos.y, 2))

        XCTAssertLessThan(mercToJup, mercToMars, "Mercury should be closer to Jupiter (its activator)")
    }
}
