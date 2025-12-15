//
//  Physics.swift
//  Mercurial
//
//  Pure physics functions for momentum, friction, spring, and rubber-band effects.
//  Provides both 1D (CGFloat) and 2D (CGPoint) variants.
//

import CoreGraphics

// MARK: - 1D Physics (CGFloat)

/// Pure physics functions for momentum-based animations.
///
/// All functions are stateless and side-effect free, making them easy to test
/// and compose into larger animation systems.
public enum Physics {

    // MARK: - Rubber Band

    /// Apply rubber-band resistance to an offset.
    ///
    /// Creates the "stretchy" feel when dragging past boundaries.
    /// Uses asymptotic formula: larger offsets approach but never exceed the limit.
    ///
    /// - Parameters:
    ///   - offset: The raw offset (can be positive or negative)
    ///   - limit: The maximum visual offset (asymptotic limit)
    ///   - coefficient: Resistance strength (0.0-1.0, higher = less resistance)
    /// - Returns: The visually dampened offset
    public static func rubberBand(offset: CGFloat, limit: CGFloat, coefficient: CGFloat) -> CGFloat {
        let absOffset = abs(offset)
        let sign: CGFloat = offset >= 0 ? 1 : -1
        let resisted = (1 - (1 / (absOffset * coefficient / limit + 1))) * limit
        return sign * resisted
    }

    // MARK: - Spring

    /// Calculate spring force for boundary bounce.
    ///
    /// Uses damped harmonic oscillator formula: F = -kx - cv
    /// - With high damping (overdamped): smooth return, no bounce
    /// - With low damping (underdamped): springy bounce
    ///
    /// - Parameters:
    ///   - displacement: Distance from rest position (positive = past boundary)
    ///   - velocity: Current velocity
    ///   - stiffness: Spring constant k (higher = stronger pull toward rest)
    ///   - damping: Damping coefficient c (higher = more resistance to motion)
    /// - Returns: The spring force to apply as acceleration
    public static func springForce(
        displacement: CGFloat,
        velocity: CGFloat,
        stiffness: CGFloat,
        damping: CGFloat
    ) -> CGFloat {
        return -stiffness * displacement - damping * velocity
    }

    // MARK: - Friction

    /// Apply friction to velocity for one frame.
    ///
    /// Models velocity decay during momentum scrolling.
    /// At friction=0.95, velocity decays to ~5% after 60 frames (~1 second at 60fps).
    ///
    /// - Parameters:
    ///   - velocity: Current velocity
    ///   - friction: Friction coefficient (0.0-1.0, e.g., 0.95 for smooth deceleration)
    /// - Returns: New velocity after friction applied
    public static func applyFriction(velocity: CGFloat, friction: CGFloat) -> CGFloat {
        return velocity * friction
    }

    // MARK: - Integration

    /// Calculate new position from velocity over a time step.
    ///
    /// Simple Euler integration: position += velocity * deltaTime
    ///
    /// - Parameters:
    ///   - position: Current position
    ///   - velocity: Current velocity in points per second
    ///   - deltaTime: Time step in seconds
    /// - Returns: New position
    public static func integrate(position: CGFloat, velocity: CGFloat, deltaTime: CGFloat) -> CGFloat {
        return position + velocity * deltaTime
    }

    // MARK: - Velocity Decay

    /// Calculate remaining velocity factor using quadratic decay.
    ///
    /// Used for smooth momentum deceleration where velocity
    /// decreases more rapidly toward the end of the animation.
    ///
    /// - Parameter progress: Animation progress (0.0 to 1.0)
    /// - Returns: Remaining velocity multiplier (1.0 to 0.0)
    public static func quadraticDecay(progress: CGFloat) -> CGFloat {
        return 1.0 - pow(progress, 2.0)
    }
}

// MARK: - 2D Physics (CGPoint)

extension Physics {

    /// Apply rubber-band resistance to a 2D offset.
    ///
    /// Applies independent rubber-band resistance to each axis.
    ///
    /// - Parameters:
    ///   - offset: The raw offset vector
    ///   - limit: The maximum visual offset (applied to both axes)
    ///   - coefficient: Resistance strength (0.0-1.0)
    /// - Returns: The visually dampened offset
    public static func rubberBand(offset: CGPoint, limit: CGFloat, coefficient: CGFloat) -> CGPoint {
        CGPoint(
            x: rubberBand(offset: offset.x, limit: limit, coefficient: coefficient),
            y: rubberBand(offset: offset.y, limit: limit, coefficient: coefficient)
        )
    }

    /// Apply rubber-band resistance with per-axis limits.
    ///
    /// Useful when horizontal and vertical bounds differ (e.g., aspect ratio constraints).
    ///
    /// - Parameters:
    ///   - offset: The raw offset vector
    ///   - limits: Per-axis limits (x for horizontal, y for vertical)
    ///   - coefficient: Resistance strength (0.0-1.0)
    /// - Returns: The visually dampened offset
    public static func rubberBand(offset: CGPoint, limits: CGPoint, coefficient: CGFloat) -> CGPoint {
        CGPoint(
            x: rubberBand(offset: offset.x, limit: limits.x, coefficient: coefficient),
            y: rubberBand(offset: offset.y, limit: limits.y, coefficient: coefficient)
        )
    }

    /// Calculate spring force for 2D boundary bounce.
    ///
    /// Applies independent spring forces to each axis.
    ///
    /// - Parameters:
    ///   - displacement: Distance from rest position
    ///   - velocity: Current velocity
    ///   - stiffness: Spring constant k
    ///   - damping: Damping coefficient c
    /// - Returns: The spring force vector
    public static func springForce(
        displacement: CGPoint,
        velocity: CGPoint,
        stiffness: CGFloat,
        damping: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: springForce(displacement: displacement.x, velocity: velocity.x, stiffness: stiffness, damping: damping),
            y: springForce(displacement: displacement.y, velocity: velocity.y, stiffness: stiffness, damping: damping)
        )
    }

    /// Apply friction to 2D velocity for one frame.
    ///
    /// - Parameters:
    ///   - velocity: Current velocity vector
    ///   - friction: Friction coefficient (0.0-1.0)
    /// - Returns: New velocity after friction applied
    public static func applyFriction(velocity: CGPoint, friction: CGFloat) -> CGPoint {
        CGPoint(
            x: applyFriction(velocity: velocity.x, friction: friction),
            y: applyFriction(velocity: velocity.y, friction: friction)
        )
    }

    /// Calculate new position from velocity over a time step.
    ///
    /// - Parameters:
    ///   - position: Current position
    ///   - velocity: Current velocity in points per second
    ///   - deltaTime: Time step in seconds
    /// - Returns: New position
    public static func integrate(position: CGPoint, velocity: CGPoint, deltaTime: CGFloat) -> CGPoint {
        CGPoint(
            x: integrate(position: position.x, velocity: velocity.x, deltaTime: deltaTime),
            y: integrate(position: position.y, velocity: velocity.y, deltaTime: deltaTime)
        )
    }

    /// Calculate the magnitude (speed) of a velocity vector.
    ///
    /// - Parameter velocity: Velocity vector
    /// - Returns: Scalar speed (always positive)
    public static func speed(_ velocity: CGPoint) -> CGFloat {
        hypot(velocity.x, velocity.y)
    }
}

// MARK: - CGPoint Arithmetic Helpers

extension CGPoint {
    /// Add two points.
    public static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    /// Subtract two points.
    public static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    /// Multiply point by scalar.
    public static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    /// Add-assign two points.
    public static func += (lhs: inout CGPoint, rhs: CGPoint) {
        lhs = lhs + rhs
    }

    /// Subtract-assign two points.
    public static func -= (lhs: inout CGPoint, rhs: CGPoint) {
        lhs = lhs - rhs
    }
}
