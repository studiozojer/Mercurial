// Sources/Mercurial/GraphLayout.swift

import CoreGraphics
import Foundation

/// Computes aesthetically balanced node positions from a weighted graph.
///
/// Uses stress majorization to minimize the difference between actual node distances
/// and target distances derived from edge weights. Higher-weight edges pull nodes
/// closer together; unconnected nodes spread apart.
public enum GraphLayout {

    /// Layout computation result.
    public struct Result: Sendable {
        /// Computed position for each node ID.
        public let positions: [String: CGPoint]

        /// Final stress value (lower = better fit).
        public let stress: CGFloat

        /// Number of iterations the solver ran.
        public let iterations: Int
    }

    /// Compute layout positions for the given graph.
    public static func compute(
        nodes: [GraphNode],
        edges: [GraphEdge],
        size: CGSize,
        configuration: GraphLayoutConfiguration = .default,
        previousPositions: [String: CGPoint]? = nil
    ) -> Result {
        let n = nodes.count

        // Edge cases
        if n == 0 {
            return Result(positions: [:], stress: 0, iterations: 0)
        }
        if n == 1 {
            return Result(
                positions: [nodes[0].id: CGPoint(x: size.width / 2, y: size.height / 2)],
                stress: 0,
                iterations: 0
            )
        }

        let ids = nodes.map(\.id)
        let idIndex = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let radii = nodes.map(\.radius)

        // Build adjacency with max-weight deduplication
        var directWeight = Array(repeating: Array(repeating: CGFloat(0), count: n), count: n)
        for edge in edges {
            guard let i = idIndex[edge.source], let j = idIndex[edge.target] else { continue }
            directWeight[i][j] = max(directWeight[i][j], edge.weight)
            directWeight[j][i] = max(directWeight[j][i], edge.weight)
        }

        // Target distance matrix
        let maxDist = configuration.spacing * 10
        let targetDist = buildTargetDistanceMatrix(
            n: n, directWeight: directWeight, configuration: configuration, maxDist: maxDist
        )

        // Importance weights: w_ij = 1 / d_ij^2
        var importance = Array(repeating: Array(repeating: CGFloat(0), count: n), count: n)
        for i in 0..<n {
            for j in (i+1)..<n {
                let w = 1.0 / (targetDist[i][j] * targetDist[i][j])
                importance[i][j] = w
                importance[j][i] = w
            }
        }

        // Initialize positions
        var positions = initializePositions(
            n: n, ids: ids, size: size, previousPositions: previousPositions
        )

        // Iterate stress majorization
        var previousStress = computeStress(positions: positions, targetDist: targetDist, importance: importance, n: n)
        var iterationCount = 0

        for iteration in 0..<configuration.maxIterations {
            iterationCount = iteration + 1

            // Weighted centroid update (stress majorization step)
            var newPositions = positions
            for i in 0..<n {
                var wx: CGFloat = 0
                var wy: CGFloat = 0
                var wSum: CGFloat = 0

                for j in 0..<n where j != i {
                    let dx = positions[i].x - positions[j].x
                    let dy = positions[i].y - positions[j].y
                    let dist = max(sqrt(dx * dx + dy * dy), 0.001)
                    let w = importance[i][j]

                    // Target position for i relative to j
                    let tx = positions[j].x + (dx / dist) * targetDist[i][j]
                    let ty = positions[j].y + (dy / dist) * targetDist[i][j]

                    wx += w * tx
                    wy += w * ty
                    wSum += w
                }

                if wSum > 0 {
                    newPositions[i] = CGPoint(x: wx / wSum, y: wy / wSum)
                }
            }
            positions = newPositions

            // Collision resolution
            resolveCollisions(positions: &positions, radii: radii, n: n)

            // Check convergence
            let currentStress = computeStress(positions: positions, targetDist: targetDist, importance: importance, n: n)
            let reduction = previousStress > 0 ? (previousStress - currentStress) / previousStress : 0
            previousStress = currentStress

            if iteration > 0 && reduction < configuration.convergenceThreshold {
                break
            }
        }

        // Scale and center to fit bounds
        let finalPositions = scaleToBounds(
            positions: positions, ids: ids, radii: radii, size: size, padding: configuration.padding
        )

        return Result(
            positions: finalPositions,
            stress: previousStress,
            iterations: iterationCount
        )
    }

    // MARK: - Private Helpers

    private static func buildTargetDistanceMatrix(
        n: Int, directWeight: [[CGFloat]], configuration: GraphLayoutConfiguration, maxDist: CGFloat
    ) -> [[CGFloat]] {
        // Floyd-Warshall shortest-path distances (in hop-weighted space)
        var dist = Array(repeating: Array(repeating: CGFloat.infinity, count: n), count: n)

        for i in 0..<n {
            dist[i][i] = 0
            for j in 0..<n where directWeight[i][j] > 0 {
                let d = min(configuration.spacing / pow(directWeight[i][j], configuration.weightExponent), maxDist)
                dist[i][j] = d
            }
        }

        for k in 0..<n {
            for i in 0..<n {
                for j in 0..<n {
                    let through_k = dist[i][k] + dist[k][j]
                    if through_k < dist[i][j] {
                        dist[i][j] = through_k
                    }
                }
            }
        }

        // Find diameter (largest finite distance)
        var diameter: CGFloat = configuration.spacing
        for i in 0..<n {
            for j in (i+1)..<n {
                if dist[i][j].isFinite && dist[i][j] > diameter {
                    diameter = dist[i][j]
                }
            }
        }

        // Determine if any edges exist (any finite off-diagonal distance)
        var hasEdges = false
        outer: for i in 0..<n {
            for j in (i+1)..<n {
                if dist[i][j].isFinite { hasEdges = true; break outer }
            }
        }

        // Replace infinity with disconnected-component distance
        let disconnectedDist = hasEdges ? diameter * 2 : configuration.spacing * CGFloat(n)
        for i in 0..<n {
            for j in 0..<n {
                if !dist[i][j].isFinite {
                    dist[i][j] = disconnectedDist
                }
            }
        }

        return dist
    }

    private static func initializePositions(
        n: Int, ids: [String], size: CGSize, previousPositions: [String: CGPoint]?
    ) -> [CGPoint] {
        if let prev = previousPositions {
            return ids.map { id in
                prev[id] ?? CGPoint(x: size.width / 2, y: size.height / 2)
            }
        }

        // Circular initial placement
        let cx = size.width / 2
        let cy = size.height / 2
        let radius = min(size.width, size.height) * 0.3
        return (0..<n).map { i in
            let angle = CGFloat(i) / CGFloat(n) * 2 * .pi
            return CGPoint(
                x: cx + radius * cos(angle),
                y: cy + radius * sin(angle)
            )
        }
    }

    private static func computeStress(
        positions: [CGPoint], targetDist: [[CGFloat]], importance: [[CGFloat]], n: Int
    ) -> CGFloat {
        var stress: CGFloat = 0
        for i in 0..<n {
            for j in (i+1)..<n {
                let dx = positions[i].x - positions[j].x
                let dy = positions[i].y - positions[j].y
                let dist = sqrt(dx * dx + dy * dy)
                let diff = dist - targetDist[i][j]
                stress += importance[i][j] * diff * diff
            }
        }
        return stress
    }

    private static func resolveCollisions(positions: inout [CGPoint], radii: [CGFloat], n: Int) {
        let gap: CGFloat = 4
        for i in 0..<n {
            for j in (i+1)..<n {
                let dx = positions[j].x - positions[i].x
                let dy = positions[j].y - positions[i].y
                let dist = max(sqrt(dx * dx + dy * dy), 0.001)
                let minDist = radii[i] + radii[j] + gap

                if dist < minDist {
                    let overlap = (minDist - dist) / 2
                    let nx = dx / dist
                    let ny = dy / dist
                    positions[i].x -= nx * overlap
                    positions[i].y -= ny * overlap
                    positions[j].x += nx * overlap
                    positions[j].y += ny * overlap
                }
            }
        }
    }

    private static func scaleToBounds(
        positions: [CGPoint], ids: [String], radii: [CGFloat], size: CGSize, padding: CGFloat
    ) -> [String: CGPoint] {
        guard !positions.isEmpty else { return [:] }

        // Find bounding box
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for (i, pos) in positions.enumerated() {
            let r = radii[i]
            minX = min(minX, pos.x - r)
            maxX = max(maxX, pos.x + r)
            minY = min(minY, pos.y - r)
            maxY = max(maxY, pos.y + r)
        }

        let contentWidth = maxX - minX
        let contentHeight = maxY - minY
        guard contentWidth > 0.001 && contentHeight > 0.001 else {
            // Degenerate — all at same point. Place at center.
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, center) })
        }

        let availableWidth = size.width - padding * 2
        let availableHeight = size.height - padding * 2
        let scale = min(availableWidth / contentWidth, availableHeight / contentHeight)

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        var result: [String: CGPoint] = [:]
        for (i, pos) in positions.enumerated() {
            result[ids[i]] = CGPoint(
                x: (pos.x - centerX) * scale + size.width / 2,
                y: (pos.y - centerY) * scale + size.height / 2
            )
        }
        return result
    }
}
