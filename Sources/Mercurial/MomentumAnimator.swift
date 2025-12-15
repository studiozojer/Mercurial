//
//  MomentumAnimator.swift
//  Mercurial
//
//  Encapsulates momentum animation with frame-rate independent physics.
//

import Foundation
import CoreGraphics
import QuartzCore

// MARK: - Momentum State

/// Current state of a momentum animation.
public enum MomentumState: Sendable {
    /// No animation in progress.
    case idle

    /// Momentum is active (decelerating via friction).
    case momentum

    /// Bouncing back from boundary (spring physics).
    case bouncing

    /// Animation is settling to final position.
    case settling
}

// MARK: - 1D Momentum Animator

/// Manages 1D momentum animation with friction and spring physics.
///
/// Use this for single-axis scrolling (like vertical scroll views).
///
/// ## Usage
/// ```swift
/// let animator = Momentum1DAnimator(configuration: .default)
/// animator.start(velocity: -500)
///
/// // In your frame loop (e.g., TimelineView onChange):
/// animator.update()
/// currentOffset = animator.position
/// ```
public final class Momentum1DAnimator: @unchecked Sendable {
    // MARK: - Properties

    /// Current position.
    public private(set) var position: CGFloat = 0

    /// Current velocity.
    public private(set) var velocity: CGFloat = 0

    /// Current animation state.
    public private(set) var state: MomentumState = .idle

    /// Whether animation is currently active.
    public var isActive: Bool { state != .idle }

    /// Physics configuration.
    public var configuration: PhysicsConfiguration

    /// Boundary constraints. Set to `.unbounded` for infinite scrolling.
    public var bounds: (min: CGFloat, max: CGFloat)?

    // MARK: - Private

    private var lastUpdateTime: CFTimeInterval = 0

    // MARK: - Initialization

    /// Creates a 1D momentum animator.
    /// - Parameters:
    ///   - configuration: Physics configuration.
    ///   - initialPosition: Starting position.
    public init(
        configuration: PhysicsConfiguration = .default,
        initialPosition: CGFloat = 0
    ) {
        self.configuration = configuration
        self.position = initialPosition
    }

    // MARK: - Control

    /// Start momentum animation with initial velocity.
    /// - Parameter velocity: Initial velocity in points per second.
    public func start(velocity: CGFloat) {
        guard abs(velocity) > configuration.momentum.minimumVelocity else {
            state = .idle
            return
        }

        self.velocity = velocity
        self.lastUpdateTime = CACurrentMediaTime()
        self.state = .momentum
    }

    /// Immediately stop animation (e.g., when user touches).
    public func stop() {
        velocity = 0
        state = .idle
    }

    /// Set position directly (e.g., during drag).
    public func setPosition(_ newPosition: CGFloat) {
        position = newPosition
    }

    /// Update physics for current frame.
    ///
    /// Call this every frame when `isActive` is true.
    /// Uses `CACurrentMediaTime()` internally for frame-rate independence.
    @discardableResult
    public func update() -> Bool {
        guard state != .idle else { return false }

        let currentTime = CACurrentMediaTime()
        let rawDelta = currentTime - lastUpdateTime
        let deltaTime = CGFloat(min(rawDelta, Double(configuration.momentum.maxDeltaTime)))
        lastUpdateTime = currentTime

        // Check boundary conditions
        let displacement = calculateDisplacement()
        let isPastBoundary = abs(displacement) > 0.001

        if isPastBoundary {
            // Apply spring physics to return to boundary
            state = .bouncing
            let force = Physics.springForce(
                displacement: displacement,
                velocity: velocity,
                stiffness: configuration.spring.stiffness,
                damping: configuration.spring.damping
            )
            velocity += force * deltaTime
            position = Physics.integrate(position: position, velocity: velocity, deltaTime: deltaTime)

            // Check if we've returned to boundary
            let newDisplacement = calculateDisplacement()
            if abs(newDisplacement) < 0.5 && abs(velocity) < 1 {
                // Snap to boundary and stop
                if let bounds = bounds {
                    if displacement < 0 { position = bounds.min }
                    else { position = bounds.max }
                }
                velocity = 0
                state = .idle
            }
        } else {
            // Normal friction-based momentum
            state = .momentum
            position = Physics.integrate(position: position, velocity: velocity, deltaTime: deltaTime)
            velocity = Physics.applyFriction(velocity: velocity, friction: configuration.momentum.friction)

            // Check if velocity is negligible
            if abs(velocity) < configuration.momentum.minimumVelocity {
                velocity = 0
                state = .idle
            }

            // Check if we've hit a boundary
            let newDisplacement = calculateDisplacement()
            if abs(newDisplacement) > 0 {
                state = .bouncing
            }
        }

        return state != .idle
    }

    // MARK: - Private Helpers

    private func calculateDisplacement() -> CGFloat {
        guard let bounds = bounds else { return 0 }

        if position < bounds.min {
            return position - bounds.min
        } else if position > bounds.max {
            return position - bounds.max
        }
        return 0
    }
}

// MARK: - 2D Momentum Animator

/// Manages 2D momentum animation with friction and spring physics.
///
/// Use this for pan gestures (like map or image panning).
///
/// ## Usage
/// ```swift
/// let animator = Momentum2DAnimator(configuration: .default)
/// animator.start(velocity: CGPoint(x: -200, y: -500))
///
/// // In your frame loop (e.g., TimelineView onChange):
/// animator.update()
/// currentOffset = animator.position
/// ```
public final class Momentum2DAnimator: @unchecked Sendable {
    // MARK: - Properties

    /// Current position.
    public private(set) var position: CGPoint = .zero

    /// Current velocity.
    public private(set) var velocity: CGPoint = .zero

    /// Current animation state.
    public private(set) var state: MomentumState = .idle

    /// Whether animation is currently active.
    public var isActive: Bool { state != .idle }

    /// Physics configuration.
    public var configuration: PhysicsConfiguration

    /// Boundary constraints. Set to `.unbounded` for infinite panning.
    public var bounds: PhysicsBounds?

    // MARK: - Private

    private var lastUpdateTime: CFTimeInterval = 0

    // MARK: - Initialization

    /// Creates a 2D momentum animator.
    /// - Parameters:
    ///   - configuration: Physics configuration.
    ///   - initialPosition: Starting position.
    public init(
        configuration: PhysicsConfiguration = .default,
        initialPosition: CGPoint = .zero
    ) {
        self.configuration = configuration
        self.position = initialPosition
    }

    // MARK: - Control

    /// Start momentum animation with initial velocity.
    /// - Parameter velocity: Initial velocity in points per second.
    public func start(velocity: CGPoint) {
        let speed = Physics.speed(velocity)
        guard speed > configuration.momentum.minimumVelocity else {
            state = .idle
            return
        }

        self.velocity = velocity
        self.lastUpdateTime = CACurrentMediaTime()
        self.state = .momentum
    }

    /// Immediately stop animation (e.g., when user touches).
    public func stop() {
        velocity = .zero
        state = .idle
    }

    /// Set position directly (e.g., during drag).
    public func setPosition(_ newPosition: CGPoint) {
        position = newPosition
    }

    /// Update physics for current frame.
    ///
    /// Call this every frame when `isActive` is true.
    /// Uses `CACurrentMediaTime()` internally for frame-rate independence.
    @discardableResult
    public func update() -> Bool {
        guard state != .idle else { return false }

        let currentTime = CACurrentMediaTime()
        let rawDelta = currentTime - lastUpdateTime
        let deltaTime = CGFloat(min(rawDelta, Double(configuration.momentum.maxDeltaTime)))
        lastUpdateTime = currentTime

        // Check boundary conditions
        let displacement = calculateDisplacement()
        let isPastBoundary = Physics.speed(displacement) > 0.001

        if isPastBoundary {
            // Apply spring physics to return to boundary
            state = .bouncing
            let force = Physics.springForce(
                displacement: displacement,
                velocity: velocity,
                stiffness: configuration.spring.stiffness,
                damping: configuration.spring.damping
            )
            velocity = velocity + force * deltaTime
            position = Physics.integrate(position: position, velocity: velocity, deltaTime: deltaTime)

            // Check if we've returned to boundary
            let newDisplacement = calculateDisplacement()
            if Physics.speed(newDisplacement) < 0.5 && Physics.speed(velocity) < 1 {
                // Snap to boundary and stop
                if let bounds = bounds {
                    position = bounds.clamp(position)
                }
                velocity = .zero
                state = .idle
            }
        } else {
            // Normal friction-based momentum
            state = .momentum
            position = Physics.integrate(position: position, velocity: velocity, deltaTime: deltaTime)
            velocity = Physics.applyFriction(velocity: velocity, friction: configuration.momentum.friction)

            // Check if velocity is negligible
            if Physics.speed(velocity) < configuration.momentum.minimumVelocity {
                velocity = .zero
                state = .idle
            }

            // Check if we've hit a boundary
            let newDisplacement = calculateDisplacement()
            if Physics.speed(newDisplacement) > 0 {
                state = .bouncing
            }
        }

        return state != .idle
    }

    // MARK: - Private Helpers

    private func calculateDisplacement() -> CGPoint {
        guard let bounds = bounds else { return .zero }
        return bounds.displacement(from: position)
    }
}

// MARK: - Rubber Band Helpers

extension Momentum2DAnimator {
    /// Apply rubber band resistance during drag.
    ///
    /// Call this to transform raw drag offset into visual offset
    /// when position is past bounds.
    ///
    /// - Parameter rawOffset: Raw drag offset from gesture
    /// - Returns: Visual offset with rubber-band resistance applied
    public func rubberBandOffset(_ rawOffset: CGPoint) -> CGPoint {
        guard let bounds = bounds else { return rawOffset }

        // Only apply rubber band to the portion past bounds
        return CGPoint(
            x: applyAxisRubberBand(
                rawOffset: rawOffset.x,
                currentPosition: position.x,
                minBound: bounds.min.x,
                maxBound: bounds.max.x
            ),
            y: applyAxisRubberBand(
                rawOffset: rawOffset.y,
                currentPosition: position.y,
                minBound: bounds.min.y,
                maxBound: bounds.max.y
            )
        )
    }

    private func applyAxisRubberBand(
        rawOffset: CGFloat,
        currentPosition: CGFloat,
        minBound: CGFloat,
        maxBound: CGFloat
    ) -> CGFloat {
        let newPosition = currentPosition + rawOffset

        if newPosition < minBound {
            let inBoundsOffset = minBound - currentPosition
            let pastBoundsOffset = newPosition - minBound
            return inBoundsOffset + Physics.rubberBand(
                offset: pastBoundsOffset,
                limit: configuration.rubberBand.limit,
                coefficient: configuration.rubberBand.coefficient
            )
        } else if newPosition > maxBound {
            let inBoundsOffset = maxBound - currentPosition
            let pastBoundsOffset = newPosition - maxBound
            return inBoundsOffset + Physics.rubberBand(
                offset: pastBoundsOffset,
                limit: configuration.rubberBand.limit,
                coefficient: configuration.rubberBand.coefficient
            )
        }

        return rawOffset
    }
}
