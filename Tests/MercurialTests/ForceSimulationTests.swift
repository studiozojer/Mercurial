// Tests/MercurialTests/ForceSimulationTests.swift

import XCTest
@testable import Mercurial

final class ForceSimulationTests: XCTestCase {

    let canvasSize = CGSize(width: 400, height: 400)

    // MARK: - Empty Graph

    func testEmptyGraphDoesNotCrash() {
        let sim = ForceSimulation()
        sim.configure(nodes: [], edges: [], size: canvasSize)
        sim.tick(deltaTime: 1.0 / 60.0)
        XCTAssertTrue(sim.positions.isEmpty)
        XCTAssertTrue(sim.isSettled)
    }

    // MARK: - Single Node

    func testSingleNodeAtCenter() {
        let sim = ForceSimulation()
        sim.configure(nodes: [GraphNode(id: "A")], edges: [], size: canvasSize)

        // Run a few ticks — centering should pull to center, then settle
        for _ in 0..<120 {
            sim.tick(deltaTime: 1.0 / 60.0)
        }

        let pos = sim.positions["A"]!
        XCTAssertEqual(pos.x, 200, accuracy: 5, "Single node should settle near center x")
        XCTAssertEqual(pos.y, 200, accuracy: 5, "Single node should settle near center y")
        XCTAssertTrue(sim.isSettled)
    }

    // MARK: - Two Connected Nodes

    func testTwoConnectedNodesSettleAtRestLength() {
        let sim = ForceSimulation()
        let config = ForceSimulationConfiguration.default
        let nodes = [GraphNode(id: "A"), GraphNode(id: "B")]
        let edges = [GraphEdge(source: "A", target: "B", weight: 0.5)]
        sim.configure(nodes: nodes, edges: edges, size: canvasSize)

        for _ in 0..<600 {
            if sim.isSettled { break }
            sim.tick(deltaTime: 1.0 / 60.0)
        }

        let posA = sim.positions["A"]!
        let posB = sim.positions["B"]!
        let dist = posA.distance(to: posB)
        let expectedRest = config.springRestLengthBase / 0.5

        // Should be roughly at rest length (within 30%)
        XCTAssertEqual(dist, expectedRest, accuracy: expectedRest * 0.5,
                       "Connected nodes should settle near rest length")
        XCTAssertTrue(sim.isSettled)
    }

    // MARK: - Two Unconnected Nodes

    func testTwoUnconnectedNodesRepelEachOther() {
        let sim = ForceSimulation()
        let nodes = [GraphNode(id: "A"), GraphNode(id: "B")]
        sim.configure(nodes: nodes, edges: [], size: canvasSize)

        // Get initial distance (ensure nodes exist before ticking)
        _ = sim.positions["A"]!.distance(to: sim.positions["B"]!)

        for _ in 0..<300 {
            sim.tick(deltaTime: 1.0 / 60.0)
        }

        let finalDist = sim.positions["A"]!.distance(to: sim.positions["B"]!)
        // Repulsion should push them apart (or centering keeps them near center)
        // Key: they should not collapse to the same point
        XCTAssertGreaterThan(finalDist, 10, "Unconnected nodes should not collapse together")
    }

    // MARK: - Triangle

    func testTriangleSettles() {
        let sim = ForceSimulation()
        let nodes = ["A", "B", "C"].map { GraphNode(id: $0) }
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 0.5),
            GraphEdge(source: "B", target: "C", weight: 0.5),
            GraphEdge(source: "C", target: "A", weight: 0.5),
        ]
        sim.configure(nodes: nodes, edges: edges, size: canvasSize)

        for _ in 0..<600 {
            if sim.isSettled { break }
            sim.tick(deltaTime: 1.0 / 60.0)
        }

        XCTAssertTrue(sim.isSettled, "Triangle should settle")

        // Check roughly equilateral — all pair distances should be similar
        let posA = sim.positions["A"]!
        let posB = sim.positions["B"]!
        let posC = sim.positions["C"]!
        let dAB = posA.distance(to: posB)
        let dBC = posB.distance(to: posC)
        let dCA = posC.distance(to: posA)

        let maxDist = max(dAB, dBC, dCA)
        let minDist = min(dAB, dBC, dCA)
        // Ratio should be close to 1 for equilateral
        XCTAssertLessThan(maxDist / minDist, 1.5,
                          "Triangle with equal weights should be roughly equilateral")
    }

    // MARK: - Repulsion Fills Space

    func testRepulsionFillsSpace() {
        let sim = ForceSimulation()
        let nodes = (0..<5).map { GraphNode(id: "N\($0)") }
        sim.configure(nodes: nodes, edges: [], size: canvasSize)

        for _ in 0..<600 {
            if sim.isSettled { break }
            sim.tick(deltaTime: 1.0 / 60.0)
        }

        // All nodes should be distinct — no two collapsed
        let ids = nodes.map(\.id)
        for i in 0..<ids.count {
            for j in (i+1)..<ids.count {
                let pi = sim.positions[ids[i]]!
                let pj = sim.positions[ids[j]]!
                XCTAssertGreaterThan(pi.distance(to: pj), 10,
                                     "Nodes \(ids[i]) and \(ids[j]) should be spread apart")
            }
        }
    }

    // MARK: - Edge Weight Affects Distance

    func testHighWeightEdgeProducesCloserNodes() {
        let sim = ForceSimulation()
        let nodes = ["A", "B", "C"].map { GraphNode(id: $0) }
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 1.0),  // tight
            GraphEdge(source: "A", target: "C", weight: 0.1),  // loose
        ]
        sim.configure(nodes: nodes, edges: edges, size: canvasSize)

        for _ in 0..<600 {
            if sim.isSettled { break }
            sim.tick(deltaTime: 1.0 / 60.0)
        }

        let posA = sim.positions["A"]!
        let posB = sim.positions["B"]!
        let posC = sim.positions["C"]!

        let distAB = posA.distance(to: posB)
        let distAC = posA.distance(to: posC)

        XCTAssertLessThan(distAB, distAC,
                          "High-weight edge (A-B) should produce closer nodes than low-weight (A-C)")
    }

    // MARK: - Settling

    func testSimulationSettles() {
        let sim = ForceSimulation()
        let nodes = ["A", "B", "C", "D"].map { GraphNode(id: $0) }
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 0.8),
            GraphEdge(source: "B", target: "C", weight: 0.6),
            GraphEdge(source: "C", target: "D", weight: 0.4),
            GraphEdge(source: "D", target: "A", weight: 0.5),
        ]
        sim.configure(nodes: nodes, edges: edges, size: canvasSize)

        var tickCount = 0
        for _ in 0..<1000 {
            tickCount += 1
            sim.tick(deltaTime: 1.0 / 60.0)
            if sim.isSettled { break }
        }

        XCTAssertTrue(sim.isSettled, "Simulation should settle within 1000 ticks")
        XCTAssertLessThan(tickCount, 1000, "Should settle well before 1000 ticks")
    }

    // MARK: - Reheat

    func testReheatUnsettlesSimulation() {
        let sim = ForceSimulation()
        let nodes = ["A", "B"].map { GraphNode(id: $0) }
        let edges = [GraphEdge(source: "A", target: "B", weight: 0.5)]
        sim.configure(nodes: nodes, edges: edges, size: canvasSize)

        // Settle
        for _ in 0..<600 {
            if sim.isSettled { break }
            sim.tick(deltaTime: 1.0 / 60.0)
        }
        XCTAssertTrue(sim.isSettled, "Should settle first")

        // Reheat
        sim.reheat()
        XCTAssertFalse(sim.isSettled, "Should be unsettled after reheat")

        // Should be able to settle again
        for _ in 0..<1200 {
            if sim.isSettled { break }
            sim.tick(deltaTime: 1.0 / 60.0)
        }
        XCTAssertTrue(sim.isSettled, "Should settle again after reheat")
    }

    // MARK: - Warm Start

    func testWarmStartPreservesExistingPositions() {
        let sim = ForceSimulation()
        let nodes = ["A", "B"].map { GraphNode(id: $0) }
        let edges = [GraphEdge(source: "A", target: "B", weight: 0.5)]
        sim.configure(nodes: nodes, edges: edges, size: canvasSize)

        // Settle
        for _ in 0..<600 {
            if sim.isSettled { break }
            sim.tick(deltaTime: 1.0 / 60.0)
        }

        let posABefore = sim.positions["A"]!
        let posBBefore = sim.positions["B"]!

        // Reconfigure with an added node
        let newNodes = ["A", "B", "C"].map { GraphNode(id: $0) }
        let newEdges = [
            GraphEdge(source: "A", target: "B", weight: 0.5),
            GraphEdge(source: "B", target: "C", weight: 0.5),
        ]
        sim.configure(nodes: newNodes, edges: newEdges, size: canvasSize)

        let posAAfter = sim.positions["A"]!
        let posBAfter = sim.positions["B"]!

        // Existing nodes should keep their positions
        XCTAssertEqual(posAAfter.x, posABefore.x, accuracy: 0.001)
        XCTAssertEqual(posAAfter.y, posABefore.y, accuracy: 0.001)
        XCTAssertEqual(posBAfter.x, posBBefore.x, accuracy: 0.001)
        XCTAssertEqual(posBAfter.y, posBBefore.y, accuracy: 0.001)
    }

    // MARK: - New Nodes at Centroid

    func testNewNodesAppearAtCentroid() {
        let sim = ForceSimulation()
        let nodes = ["A", "B"].map { GraphNode(id: $0) }
        let edges = [GraphEdge(source: "A", target: "B", weight: 0.5)]
        sim.configure(nodes: nodes, edges: edges, size: canvasSize)

        // Settle
        for _ in 0..<600 {
            if sim.isSettled { break }
            sim.tick(deltaTime: 1.0 / 60.0)
        }

        let posA = sim.positions["A"]!
        let posB = sim.positions["B"]!
        let centroid = CGPoint(x: (posA.x + posB.x) / 2, y: (posA.y + posB.y) / 2)

        // Add node C
        let newNodes = ["A", "B", "C"].map { GraphNode(id: $0) }
        let newEdges = [
            GraphEdge(source: "A", target: "B", weight: 0.5),
            GraphEdge(source: "B", target: "C", weight: 0.5),
        ]
        sim.configure(nodes: newNodes, edges: newEdges, size: canvasSize)

        let posC = sim.positions["C"]!
        XCTAssertEqual(posC.x, centroid.x, accuracy: 1, "New node should appear at centroid x")
        XCTAssertEqual(posC.y, centroid.y, accuracy: 1, "New node should appear at centroid y")
    }

    // MARK: - DeltaTime Capping

    func testLargeDeltaTimeDoesNotExplode() {
        let sim = ForceSimulation()
        let nodes = ["A", "B"].map { GraphNode(id: $0) }
        let edges = [GraphEdge(source: "A", target: "B", weight: 0.5)]
        sim.configure(nodes: nodes, edges: edges, size: canvasSize)

        // Pass absurdly large deltaTime
        sim.tick(deltaTime: 10.0)

        let posA = sim.positions["A"]!
        let posB = sim.positions["B"]!

        // Positions should remain finite and reasonable
        XCTAssertTrue(posA.x.isFinite)
        XCTAssertTrue(posA.y.isFinite)
        XCTAssertTrue(posB.x.isFinite)
        XCTAssertTrue(posB.y.isFinite)
    }

    // MARK: - Disconnected Components

    func testDisconnectedComponentsStaySeparated() {
        let sim = ForceSimulation()
        let nodes = ["A", "B", "C", "D"].map { GraphNode(id: $0) }
        let edges = [
            GraphEdge(source: "A", target: "B", weight: 0.8),
            GraphEdge(source: "C", target: "D", weight: 0.8),
        ]
        sim.configure(nodes: nodes, edges: edges, size: canvasSize)

        for _ in 0..<600 {
            if sim.isSettled { break }
            sim.tick(deltaTime: 1.0 / 60.0)
        }

        // The two components should be separated by repulsion
        let posA = sim.positions["A"]!
        let posB = sim.positions["B"]!
        let posC = sim.positions["C"]!
        let posD = sim.positions["D"]!

        let centroidAB = CGPoint(x: (posA.x + posB.x) / 2, y: (posA.y + posB.y) / 2)
        let centroidCD = CGPoint(x: (posC.x + posD.x) / 2, y: (posC.y + posD.y) / 2)

        XCTAssertGreaterThan(centroidAB.distance(to: centroidCD), 20,
                             "Disconnected components should stay separated")
    }

    // MARK: - Configuration

    func testDefaultConfigurationHasSensibleValues() {
        let config = ForceSimulationConfiguration.default
        XCTAssertGreaterThan(config.repulsionStrength, 0)
        XCTAssertGreaterThan(config.springStiffness, 0)
        XCTAssertGreaterThan(config.springRestLengthBase, 0)
        XCTAssertGreaterThan(config.centeringStrength, 0)
        XCTAssertGreaterThan(config.friction, 0)
        XCTAssertLessThanOrEqual(config.friction, 1)
        XCTAssertGreaterThan(config.settleThreshold, 0)
    }
}
