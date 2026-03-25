// Sources/Mercurial/GraphAnimator.swift

import Foundation
import CoreGraphics
import Observation

/// Animates graph nodes from current positions toward target positions using spring physics.
///
/// Uses Mercurial's existing `Physics.springForce`, `Physics.applyFriction`, and `Physics.integrate`
/// for natural-feeling transitions. Does not run inter-node forces — positions are computed by
/// `GraphLayout` and the animator just makes the transition look alive.
///
/// ## Usage
/// ```swift
/// let animator = GraphAnimator()
/// animator.setTargets(layoutResult.positions)
///
/// // In TimelineView:
/// if animator.isAnimating {
///     animator.update(deltaTime: dt)
/// }
/// // Render using animator.positions
/// ```
@Observable
public final class GraphAnimator {

    // MARK: - Public State

    /// Current animated positions for each node.
    public private(set) var positions: [String: CGPoint] = [:]

    /// Whether any node is still moving toward its target.
    public private(set) var isAnimating: Bool = false

    // MARK: - Private State

    private var velocities: [String: CGPoint] = [:]
    private var targets: [String: CGPoint] = [:]
    private let configuration: GraphAnimationConfiguration

    // MARK: - Initialization

    /// Creates a graph animator.
    /// - Parameter configuration: Spring animation configuration.
    public init(configuration: GraphAnimationConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Control

    /// Set new target positions. Nodes spring toward targets over subsequent `update` calls.
    ///
    /// New node IDs (not in current positions) are initialized at the centroid of
    /// existing nodes. Removed node IDs are dropped immediately.
    public func setTargets(_ newTargets: [String: CGPoint]) {
        targets = newTargets

        // Remove nodes not in new targets
        let removedIds = Set(positions.keys).subtracting(newTargets.keys)
        for id in removedIds {
            positions.removeValue(forKey: id)
            velocities.removeValue(forKey: id)
        }

        // Add new nodes at centroid of existing positions
        let centroid = computeCentroid()
        let newIds = Set(newTargets.keys).subtracting(positions.keys)
        for id in newIds {
            positions[id] = centroid
            velocities[id] = .zero
        }

        // Check if animation is needed
        updateAnimatingState()
    }

    /// Snap all nodes to their targets immediately (no animation).
    public func snapToTargets(_ newTargets: [String: CGPoint]) {
        targets = newTargets
        positions = newTargets
        velocities = [:]
        for id in newTargets.keys {
            velocities[id] = .zero
        }
        isAnimating = false
    }

    /// Update animation for one frame.
    /// - Parameter deltaTime: Time step in seconds (e.g., 1/60 for 60fps).
    /// - Returns: `true` if animation is still active.
    @discardableResult
    public func update(deltaTime: CGFloat) -> Bool {
        guard isAnimating else { return false }

        let dt = min(deltaTime, 1.0 / 30.0) // cap to prevent large jumps

        for id in positions.keys {
            guard let target = targets[id] else { continue }
            var pos = positions[id] ?? target
            var vel = velocities[id] ?? .zero

            // Displacement FROM rest position (standard spring convention)
            let displacement = CGPoint(x: pos.x - target.x, y: pos.y - target.y)

            // Spring force: -kx pulls toward target, -cv damps velocity
            let force = Physics.springForce(
                displacement: displacement,
                velocity: vel,
                stiffness: configuration.stiffness,
                damping: configuration.damping
            )

            vel = CGPoint(x: vel.x + force.x * dt, y: vel.y + force.y * dt)

            // Friction
            vel = Physics.applyFriction(velocity: vel, friction: configuration.friction)

            // Integrate
            pos = Physics.integrate(position: pos, velocity: vel, deltaTime: dt)

            // Settle check
            let dispMag = sqrt(displacement.x * displacement.x + displacement.y * displacement.y)
            let velMag = Physics.speed(vel)

            if dispMag < 0.5 && velMag < 1 {
                pos = target
                vel = .zero
            }

            positions[id] = pos
            velocities[id] = vel
        }

        updateAnimatingState()
        return isAnimating
    }

    // MARK: - Private

    private func computeCentroid() -> CGPoint {
        guard !positions.isEmpty else { return .zero }
        var x: CGFloat = 0
        var y: CGFloat = 0
        for pos in positions.values {
            x += pos.x
            y += pos.y
        }
        let count = CGFloat(positions.count)
        return CGPoint(x: x / count, y: y / count)
    }

    private func updateAnimatingState() {
        isAnimating = positions.keys.contains { id in
            guard let pos = positions[id], let target = targets[id] else { return false }
            let dx = target.x - pos.x
            let dy = target.y - pos.y
            return sqrt(dx * dx + dy * dy) > 0.5
        }
    }
}
