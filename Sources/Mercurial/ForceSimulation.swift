// Sources/Mercurial/ForceSimulation.swift

import CoreGraphics
import Foundation
import Observation

/// A force-directed graph layout simulation.
///
/// Produces natural, organic graph layouts by running physics forces each frame:
/// repulsion between all node pairs, spring attraction along edges, centering,
/// and friction. Call `tick(deltaTime:)` from a `TimelineView` to advance the
/// simulation — positions update in place and the simulation IS the animation.
///
/// ## Usage
/// ```swift
/// @State private var simulation = ForceSimulation()
///
/// // When data arrives:
/// simulation.configure(nodes: nodes, edges: edges, size: canvasSize)
///
/// // In TimelineView:
/// TimelineView(.animation(paused: simulation.isSettled)) { timeline in
///     Canvas { context, size in
///         // Read simulation.positions, draw nodes and edges
///     }
///     .onChange(of: timeline.date) { _, _ in
///         simulation.tick(deltaTime: 1.0 / 60.0)
///     }
/// }
/// ```
@Observable
public final class ForceSimulation {

    // MARK: - Public State

    /// Current positions for each node — read by the rendering Canvas.
    public private(set) var positions: [String: CGPoint] = [:]

    /// Whether the simulation has settled (kinetic energy below threshold).
    public private(set) var isSettled: Bool = true

    /// Configuration controlling force strengths and behavior.
    public var configuration: ForceSimulationConfiguration

    // MARK: - Private State

    /// Per-node velocity vectors, keyed by node ID.
    private var velocities: [String: CGPoint] = [:]

    /// Per-node radius, keyed by node ID.
    private var radii: [String: CGFloat] = [:]

    /// Ordered node IDs for iteration.
    private var nodeIds: [String] = []

    /// Edge list for spring forces.
    private var edges: [GraphEdge] = []

    /// Canvas center point.
    private var center: CGPoint = .zero

    // MARK: - Initialization

    /// Creates a force simulation with the given configuration.
    public init(configuration: ForceSimulationConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Setup

    /// Set up the simulation with nodes, edges, and canvas size.
    ///
    /// Existing nodes keep their current positions (warm start).
    /// New nodes appear at the centroid of existing nodes.
    /// Removed nodes are dropped.
    public func configure(nodes: [GraphNode], edges: [GraphEdge], size: CGSize) {
        self.edges = edges
        self.center = CGPoint(x: size.width / 2, y: size.height / 2)

        let newIds = Set(nodes.map(\.id))
        let existingIds = Set(positions.keys)

        // Remove nodes not in new set
        for id in existingIds.subtracting(newIds) {
            positions.removeValue(forKey: id)
            velocities.removeValue(forKey: id)
            radii.removeValue(forKey: id)
        }

        // Compute centroid of existing positions for placing new nodes
        let centroid = computeCentroid()

        // Initialize new nodes
        if existingIds.isEmpty {
            let newNodes = nodes.filter { !existingIds.contains($0.id) }
            if newNodes.count == 1 {
                // Single node goes directly at center
                positions[newNodes[0].id] = center
                velocities[newNodes[0].id] = .zero
            } else {
                // Circular arrangement
                let radius = min(size.width, size.height) * 0.2
                for (i, node) in newNodes.enumerated() {
                    let angle = CGFloat(i) / CGFloat(max(newNodes.count, 1)) * 2 * .pi
                    positions[node.id] = CGPoint(
                        x: center.x + radius * cos(angle),
                        y: center.y + radius * sin(angle)
                    )
                    velocities[node.id] = .zero
                }
            }
        } else {
            // Place new nodes at centroid
            for node in nodes where !existingIds.contains(node.id) {
                positions[node.id] = centroid
                velocities[node.id] = .zero
            }
        }

        // Update radii
        radii = [:]
        for node in nodes {
            radii[node.id] = node.radius
        }

        // Update ordered ID list
        nodeIds = nodes.map(\.id)

        // Mark unsettled if we have nodes
        isSettled = nodeIds.isEmpty
    }

    // MARK: - Simulation Step

    /// Advance the simulation by one time step.
    ///
    /// Call from a `TimelineView`'s `onChange(of: timeline.date)`.
    /// DeltaTime is capped at 1/30 to prevent explosion from large time steps.
    public func tick(deltaTime: CGFloat) {
        guard !nodeIds.isEmpty else { return }

        let dt = min(deltaTime, 1.0 / 30.0)
        let n = nodeIds.count

        // Single node — just apply centering and settle
        if n == 1 {
            let id = nodeIds[0]
            tickSingleNode(id: id, dt: dt)
            return
        }

        // Accumulate forces per node
        var forces: [String: CGPoint] = [:]
        for id in nodeIds {
            forces[id] = .zero
        }

        // 1. Repulsion between all node pairs (inverse-square)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let idI = nodeIds[i]
                let idJ = nodeIds[j]
                guard let posI = positions[idI], let posJ = positions[idJ] else { continue }

                var dx = posJ.x - posI.x
                var dy = posJ.y - posI.y
                var distSq = dx * dx + dy * dy

                // Prevent division by zero — jitter if coincident
                if distSq < 1 {
                    dx = CGFloat.random(in: -1...1)
                    dy = CGFloat.random(in: -1...1)
                    distSq = dx * dx + dy * dy
                }

                let dist = sqrt(distSq)
                let force = configuration.repulsionStrength / distSq
                let fx = (dx / dist) * force
                let fy = (dy / dist) * force

                forces[idI]! -= CGPoint(x: fx, y: fy)
                forces[idJ]! += CGPoint(x: fx, y: fy)
            }
        }

        // 2. Spring attraction along edges
        for edge in edges {
            guard let posS = positions[edge.source],
                  let posT = positions[edge.target],
                  let velS = velocities[edge.source],
                  let velT = velocities[edge.target] else { continue }

            let dx = posT.x - posS.x
            let dy = posT.y - posS.y
            let dist = max(sqrt(dx * dx + dy * dy), 0.001)
            let restLength = configuration.springRestLengthBase / edge.weight

            let displacement = dist - restLength
            let nx = dx / dist
            let ny = dy / dist

            // Spring force: F = k * displacement (toward rest length)
            // Plus damping along the spring axis
            let relVelX = velT.x - velS.x
            let relVelY = velT.y - velS.y
            let relVelAlongSpring = relVelX * nx + relVelY * ny

            let springF = configuration.springStiffness * displacement
                        + configuration.springDamping * relVelAlongSpring
            let fx = nx * springF
            let fy = ny * springF

            forces[edge.source]! += CGPoint(x: fx, y: fy)
            forces[edge.target]! -= CGPoint(x: fx, y: fy)
        }

        // 3. Centering force
        for id in nodeIds {
            guard let pos = positions[id] else { continue }
            let dx = center.x - pos.x
            let dy = center.y - pos.y
            forces[id]! += CGPoint(x: dx * configuration.centeringStrength,
                                   y: dy * configuration.centeringStrength)
        }

        // 4. Collision avoidance (soft repulsion based on radii)
        if configuration.collisionPadding > 0 {
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let idI = nodeIds[i]
                    let idJ = nodeIds[j]
                    guard let posI = positions[idI], let posJ = positions[idJ] else { continue }
                    let rI = radii[idI] ?? 12
                    let rJ = radii[idJ] ?? 12
                    let minDist = rI + rJ + configuration.collisionPadding

                    let dx = posJ.x - posI.x
                    let dy = posJ.y - posI.y
                    let dist = max(sqrt(dx * dx + dy * dy), 0.001)

                    if dist < minDist {
                        let overlap = minDist - dist
                        let nx = dx / dist
                        let ny = dy / dist
                        let pushForce = overlap * 2.0 // Soft push proportional to overlap
                        forces[idI]! -= CGPoint(x: nx * pushForce, y: ny * pushForce)
                        forces[idJ]! += CGPoint(x: nx * pushForce, y: ny * pushForce)
                    }
                }
            }
        }

        // 5. Integrate: apply forces to velocities, apply friction, update positions
        var totalKE: CGFloat = 0

        for id in nodeIds {
            guard var vel = velocities[id], var pos = positions[id] else { continue }
            let force = forces[id] ?? .zero

            // Integrate velocity
            vel.x += force.x * dt
            vel.y += force.y * dt

            // Apply friction
            vel = Physics.applyFriction(velocity: vel, friction: configuration.friction)

            // Integrate position
            pos = Physics.integrate(position: pos, velocity: vel, deltaTime: dt)

            velocities[id] = vel
            positions[id] = pos

            totalKE += vel.x * vel.x + vel.y * vel.y
        }

        // 6. Check settled
        isSettled = totalKE < configuration.settleThreshold
    }

    // MARK: - Reheat

    /// Add energy back into the simulation to escape local minima.
    ///
    /// Applies random velocity perturbations to all nodes and marks
    /// the simulation as unsettled.
    public func reheat() {
        guard !nodeIds.isEmpty else { return }

        let perturbation: CGFloat = 50
        for id in nodeIds {
            velocities[id] = CGPoint(
                x: CGFloat.random(in: -perturbation...perturbation),
                y: CGFloat.random(in: -perturbation...perturbation)
            )
        }
        isSettled = false
    }

    // MARK: - Private

    private func computeCentroid() -> CGPoint {
        guard !positions.isEmpty else { return center }
        var x: CGFloat = 0
        var y: CGFloat = 0
        for pos in positions.values {
            x += pos.x
            y += pos.y
        }
        let count = CGFloat(positions.count)
        return CGPoint(x: x / count, y: y / count)
    }

    private func tickSingleNode(id: String, dt: CGFloat) {
        guard var vel = velocities[id], var pos = positions[id] else { return }

        // Only centering force — use stronger pull for single node
        let dx = center.x - pos.x
        let dy = center.y - pos.y
        vel.x += dx * configuration.centeringStrength
        vel.y += dy * configuration.centeringStrength
        vel = Physics.applyFriction(velocity: vel, friction: configuration.friction)
        pos = Physics.integrate(position: pos, velocity: vel, deltaTime: dt)

        velocities[id] = vel
        positions[id] = pos

        let ke = vel.x * vel.x + vel.y * vel.y
        isSettled = ke < configuration.settleThreshold
    }
}
