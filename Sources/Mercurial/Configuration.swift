//
//  Configuration.swift
//  Mercurial
//
//  Configuration types for tuning physics behavior.
//

import CoreGraphics

// MARK: - Momentum Configuration

/// Configuration for momentum-based scrolling/panning.
public struct MomentumConfiguration: Equatable, Sendable {
    /// Friction coefficient (0.0-1.0).
    /// At 0.95, velocity decays to ~5% after 60 frames (~1 second at 60fps).
    public var friction: CGFloat

    /// Minimum velocity to continue momentum animation (points per second).
    /// Below this threshold, momentum stops immediately.
    public var minimumVelocity: CGFloat

    /// Maximum delta time for a single frame (seconds).
    /// Clamps frame time to prevent large jumps when frames are dropped.
    public var maxDeltaTime: CGFloat

    /// Creates a momentum configuration.
    public init(
        friction: CGFloat = 0.95,
        minimumVelocity: CGFloat = 50,
        maxDeltaTime: CGFloat = 1.0 / 30.0
    ) {
        self.friction = friction
        self.minimumVelocity = minimumVelocity
        self.maxDeltaTime = maxDeltaTime
    }

    /// Default configuration tuned for iOS-like feel.
    public static let `default` = MomentumConfiguration()

    /// Snappier momentum with faster deceleration.
    public static let snappy = MomentumConfiguration(friction: 0.90)

    /// Smoother momentum with slower deceleration.
    public static let smooth = MomentumConfiguration(friction: 0.97)
}

// MARK: - Spring Configuration

/// Configuration for spring-based boundary bounce.
public struct SpringConfiguration: Equatable, Sendable {
    /// Spring constant k (higher = stronger pull toward rest).
    public var stiffness: CGFloat

    /// Damping coefficient c (higher = less bounce).
    /// - Values > 2*sqrt(stiffness): overdamped (no bounce)
    /// - Values < 2*sqrt(stiffness): underdamped (bouncy)
    public var damping: CGFloat

    /// Creates a spring configuration.
    public init(
        stiffness: CGFloat = 200,
        damping: CGFloat = 30
    ) {
        self.stiffness = stiffness
        self.damping = damping
    }

    /// Default configuration: firm spring, overdamped (no oscillation).
    public static let `default` = SpringConfiguration()

    /// Bouncy spring for playful feel.
    public static let bouncy = SpringConfiguration(stiffness: 300, damping: 15)

    /// Soft spring for gentle return.
    public static let soft = SpringConfiguration(stiffness: 100, damping: 20)
}

// MARK: - Rubber Band Configuration

/// Configuration for rubber-band resistance at boundaries.
public struct RubberBandConfiguration: Equatable, Sendable {
    /// Resistance coefficient (0.0-1.0).
    /// Higher values = less resistance = offset approaches limit faster.
    public var coefficient: CGFloat

    /// Maximum visual offset (asymptotic limit).
    public var limit: CGFloat

    /// Creates a rubber band configuration.
    public init(
        coefficient: CGFloat = 0.55,
        limit: CGFloat = 240
    ) {
        self.coefficient = coefficient
        self.limit = limit
    }

    /// Default configuration matching iOS scroll behavior.
    public static let `default` = RubberBandConfiguration()

    /// Tighter rubber band with more resistance.
    public static let tight = RubberBandConfiguration(coefficient: 0.3, limit: 150)

    /// Looser rubber band with less resistance.
    public static let loose = RubberBandConfiguration(coefficient: 0.7, limit: 300)
}

// MARK: - Velocity Tracker Configuration

/// Configuration for velocity tracking with exponential smoothing.
public struct VelocityTrackerConfiguration: Equatable, Sendable {
    /// Smoothing factor for exponential moving average (0.0-1.0).
    /// Lower values = smoother but more laggy.
    /// Higher values = more responsive but noisier.
    public var smoothingFactor: CGFloat

    /// Maximum time between samples to consider valid (seconds).
    /// Samples older than this are ignored to prevent stale data.
    public var maxSampleAge: CGFloat

    /// Maximum time since last sample to use velocity on release (seconds).
    /// If the last sample is older than this, velocity is treated as zero.
    public var maxReleaseAge: CGFloat

    /// Creates a velocity tracker configuration.
    public init(
        smoothingFactor: CGFloat = 0.3,
        maxSampleAge: CGFloat = 0.5,
        maxReleaseAge: CGFloat = 0.1
    ) {
        self.smoothingFactor = smoothingFactor
        self.maxSampleAge = maxSampleAge
        self.maxReleaseAge = maxReleaseAge
    }

    /// Default configuration tuned for responsive gesture tracking.
    public static let `default` = VelocityTrackerConfiguration()

    /// More responsive tracking (less smoothing).
    public static let responsive = VelocityTrackerConfiguration(smoothingFactor: 0.5)

    /// Smoother tracking (more averaging).
    public static let smooth = VelocityTrackerConfiguration(smoothingFactor: 0.2)
}

// MARK: - Combined Configuration

/// Complete physics configuration combining all physics behaviors.
public struct PhysicsConfiguration: Equatable, Sendable {
    public var momentum: MomentumConfiguration
    public var spring: SpringConfiguration
    public var rubberBand: RubberBandConfiguration
    public var velocityTracker: VelocityTrackerConfiguration

    /// Creates a complete physics configuration.
    public init(
        momentum: MomentumConfiguration = .default,
        spring: SpringConfiguration = .default,
        rubberBand: RubberBandConfiguration = .default,
        velocityTracker: VelocityTrackerConfiguration = .default
    ) {
        self.momentum = momentum
        self.spring = spring
        self.rubberBand = rubberBand
        self.velocityTracker = velocityTracker
    }

    /// Default configuration with iOS-like physics.
    public static let `default` = PhysicsConfiguration()
}

// MARK: - Bounds

/// Defines scrollable/pannable bounds with optional per-axis constraints.
public struct PhysicsBounds: Equatable, Sendable {
    /// Minimum allowed position.
    public var min: CGPoint

    /// Maximum allowed position.
    public var max: CGPoint

    /// Creates physics bounds.
    public init(min: CGPoint, max: CGPoint) {
        self.min = min
        self.max = max
    }

    /// Creates physics bounds from a rect.
    public init(rect: CGRect) {
        self.min = CGPoint(x: rect.minX, y: rect.minY)
        self.max = CGPoint(x: rect.maxX, y: rect.maxY)
    }

    /// Unbounded (infinite in all directions).
    public static let unbounded = PhysicsBounds(
        min: CGPoint(x: -CGFloat.infinity, y: -CGFloat.infinity),
        max: CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
    )

    /// Check if a position is within bounds.
    public func contains(_ point: CGPoint) -> Bool {
        point.x >= min.x && point.x <= max.x &&
        point.y >= min.y && point.y <= max.y
    }

    /// Clamp a position to bounds.
    public func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: Swift.min(Swift.max(point.x, min.x), max.x),
            y: Swift.min(Swift.max(point.y, min.y), max.y)
        )
    }

    /// Calculate displacement from nearest boundary edge.
    /// Returns zero if point is within bounds.
    public func displacement(from point: CGPoint) -> CGPoint {
        var dx: CGFloat = 0
        var dy: CGFloat = 0

        if point.x < min.x {
            dx = point.x - min.x
        } else if point.x > max.x {
            dx = point.x - max.x
        }

        if point.y < min.y {
            dy = point.y - min.y
        } else if point.y > max.y {
            dy = point.y - max.y
        }

        return CGPoint(x: dx, y: dy)
    }
}
