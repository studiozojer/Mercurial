// Sources/Mercurial/FocalLayout.swift

import CoreGraphics
import Foundation

/// Computes graph positions by identifying focal points (high-connectivity nodes)
/// and arranging other nodes relative to them.
///
/// Deterministic: same input produces the same layout. No simulation, no instability.
///
/// ## Algorithm
/// 1. Score each node by total edge weight (sum of weights of all connected edges)
/// 2. Top-scoring nodes become focal points, placed spread across the canvas
/// 3. Non-focal nodes positioned relative to their strongest focal connection,
///    at distance inversely proportional to edge weight
/// 4. Light overlap resolution pass pushes overlapping nodes apart
public enum FocalLayout {

    public struct Result: Sendable {
        /// Computed position for each node ID.
        public let positions: [String: CGPoint]
    }

    /// Compute layout positions using focal point placement.
    public static func compute(
        nodes: [GraphNode],
        edges: [GraphEdge],
        size: CGSize,
        configuration: FocalLayoutConfiguration = .default
    ) -> Result {
        let n = nodes.count
        if n == 0 { return Result(positions: [:]) }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        if n == 1 {
            return Result(positions: [nodes[0].id: center])
        }

        // Build adjacency: node ID → [(neighbor ID, weight)]
        var adjacency: [String: [(id: String, weight: CGFloat)]] = [:]
        for node in nodes { adjacency[node.id] = [] }
        for edge in edges {
            adjacency[edge.source]?.append((id: edge.target, weight: edge.weight))
            adjacency[edge.target]?.append((id: edge.source, weight: edge.weight))
        }

        // Score each node by total edge weight
        var scores: [String: CGFloat] = [:]
        for node in nodes {
            let totalWeight = (adjacency[node.id] ?? []).reduce(0) { $0 + $1.weight }
            scores[node.id] = totalWeight
        }

        // Identify focal points — top N by score
        let sortedByScore = nodes.sorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
        let focalCount = determineFocalCount(nodes: nodes, edges: edges, config: configuration)
        let focalNodes = Array(sortedByScore.prefix(focalCount))
        let focalIds = Set(focalNodes.map(\.id))

        // Place focal points spread across the canvas
        var positions: [String: CGPoint] = [:]
        let usableWidth = size.width - configuration.padding * 2
        let usableHeight = size.height - configuration.padding * 2

        if focalCount == 1 {
            positions[focalNodes[0].id] = center
        } else if focalCount == 2 {
            // Horizontal spread
            let spacing = usableWidth * 0.5
            positions[focalNodes[0].id] = CGPoint(x: center.x - spacing / 2, y: center.y)
            positions[focalNodes[1].id] = CGPoint(x: center.x + spacing / 2, y: center.y)
        } else {
            // Arrange in a circle around center
            let radius = min(usableWidth, usableHeight) * 0.25
            for (i, focal) in focalNodes.enumerated() {
                let angle = (CGFloat(i) / CGFloat(focalCount)) * 2 * .pi - .pi / 2
                positions[focal.id] = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
            }
        }

        // For each non-focal node, find its strongest connection to a focal point
        // and position relative to that focal point
        let nonFocalNodes = nodes.filter { !focalIds.contains($0.id) }

        // Track how many nodes are placed around each focal point for angle distribution
        var focalChildCount: [String: Int] = [:]
        for id in focalIds { focalChildCount[id] = 0 }

        // First pass: find each node's primary focal point
        struct FocalAssignment {
            let nodeId: String
            let focalId: String
            let weight: CGFloat
            let secondaryFocalId: String?
            let secondaryWeight: CGFloat?
        }

        var assignments: [FocalAssignment] = []

        for node in nonFocalNodes {
            let neighbors = adjacency[node.id] ?? []

            // Direct connections to focal points
            var focalConnections: [(focalId: String, weight: CGFloat)] = []
            for neighbor in neighbors {
                if focalIds.contains(neighbor.id) {
                    focalConnections.append((focalId: neighbor.id, weight: neighbor.weight))
                }
            }

            if let strongest = focalConnections.max(by: { $0.weight < $1.weight }) {
                let secondary = focalConnections
                    .filter { $0.focalId != strongest.focalId }
                    .max(by: { $0.weight < $1.weight })

                assignments.append(FocalAssignment(
                    nodeId: node.id,
                    focalId: strongest.focalId,
                    weight: strongest.weight,
                    secondaryFocalId: secondary?.focalId,
                    secondaryWeight: secondary?.weight
                ))
            } else {
                // Not directly connected to any focal point — find nearest focal via path
                // For simplicity, connect to the focal point that shares the most neighbors
                var bestFocal = focalNodes[0].id
                var bestOverlap: CGFloat = 0
                let nodeNeighborIds = Set(neighbors.map(\.id))

                for focal in focalNodes {
                    let focalNeighborIds = Set((adjacency[focal.id] ?? []).map(\.id))
                    let overlap = CGFloat(nodeNeighborIds.intersection(focalNeighborIds).count)
                    if overlap > bestOverlap {
                        bestOverlap = overlap
                        bestFocal = focal.id
                    }
                }

                assignments.append(FocalAssignment(
                    nodeId: node.id,
                    focalId: bestFocal,
                    weight: 0.1, // Weak connection — place further out
                    secondaryFocalId: nil,
                    secondaryWeight: nil
                ))
            }
        }

        // Sort assignments by weight (tightest first) so tight connections get prime angles
        let sortedAssignments = assignments.sorted { $0.weight > $1.weight }

        // Second pass: place nodes around their focal points
        for assignment in sortedAssignments {
            guard let focalPos = positions[assignment.focalId] else { continue }

            let childIndex = focalChildCount[assignment.focalId] ?? 0
            focalChildCount[assignment.focalId] = childIndex + 1

            // Distance: tight weight = close, loose = far
            let maxDistance = configuration.orbitRadius
            let minDistance = configuration.minOrbitRadius
            let distance = minDistance + (maxDistance - minDistance) * (1.0 - CGFloat(assignment.weight))

            // Angle: distribute children around the focal point
            // Use golden angle for natural-looking distribution
            let goldenAngle: CGFloat = .pi * (3.0 - sqrt(5.0)) // ~137.5°
            let baseAngle: CGFloat
            if let secondaryId = assignment.secondaryFocalId,
               let secondaryPos = positions[secondaryId] {
                // Point toward the secondary focal — this node bridges two clusters
                baseAngle = atan2(secondaryPos.y - focalPos.y, secondaryPos.x - focalPos.x)
            } else {
                baseAngle = goldenAngle * CGFloat(childIndex)
            }

            let angle = baseAngle + goldenAngle * CGFloat(childIndex) * 0.3

            positions[assignment.nodeId] = CGPoint(
                x: focalPos.x + cos(angle) * distance,
                y: focalPos.y + sin(angle) * distance
            )
        }

        // Overlap resolution — gentle push-apart passes
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        resolveOverlaps(positions: &positions, nodes: nodes, nodeMap: nodeMap, config: configuration)

        // Clamp to bounds
        for node in nodes {
            guard var pos = positions[node.id] else { continue }
            let r = node.radius
            let pad = configuration.padding
            pos.x = max(r + pad, min(size.width - r - pad, pos.x))
            pos.y = max(r + pad, min(size.height - r - pad, pos.y))
            positions[node.id] = pos
        }

        return Result(positions: positions)
    }

    // MARK: - Focal Count

    private static func determineFocalCount(
        nodes: [GraphNode],
        edges: [GraphEdge],
        config: FocalLayoutConfiguration
    ) -> Int {
        // Heuristic: 1 focal for ≤6 nodes, 2 for ≤12, 3 for more
        // But at least 1, at most the configured max
        let n = nodes.count
        let natural: Int
        if n <= 6 { natural = 1 }
        else if n <= 12 { natural = 2 }
        else { natural = 3 }
        return min(natural, min(config.maxFocalPoints, n))
    }

    // MARK: - Overlap Resolution

    private static func resolveOverlaps(
        positions: inout [String: CGPoint],
        nodes: [GraphNode],
        nodeMap: [String: GraphNode],
        config: FocalLayoutConfiguration
    ) {
        let gap: CGFloat = config.overlapGap

        for _ in 0..<config.overlapPasses {
            var hadOverlap = false

            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let idA = nodes[i].id
                    let idB = nodes[j].id
                    guard var posA = positions[idA], var posB = positions[idB] else { continue }

                    let rA = nodes[i].radius
                    let rB = nodes[j].radius
                    let minDist = rA + rB + gap

                    let dx = posB.x - posA.x
                    let dy = posB.y - posA.y
                    let dist = max(sqrt(dx * dx + dy * dy), 0.001)

                    if dist < minDist {
                        hadOverlap = true
                        let overlap = (minDist - dist) / 2
                        let nx = dx / dist
                        let ny = dy / dist
                        posA.x -= nx * overlap
                        posA.y -= ny * overlap
                        posB.x += nx * overlap
                        posB.y += ny * overlap
                        positions[idA] = posA
                        positions[idB] = posB
                    }
                }
            }

            if !hadOverlap { break }
        }
    }
}
