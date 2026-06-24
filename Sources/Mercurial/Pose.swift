//
//  Pose.swift
//  Mercurial
//
//  A free body's transform: where it sits and how it is turned. The rotational
//  sibling of `Transform` — but a body's pose (position + orientation), not a
//  viewport's scale + offset. Value type so it serializes trivially: persisting a
//  spread is persisting its cards' poses (see FreeBodyAnimator.init revival note).
//

import CoreGraphics

/// A 2D pose: position (center) + rotation (radians, unbounded).
public struct Pose: Equatable, Hashable, Codable, Sendable {
    /// Center, in the host's coordinate space.
    public var position: CGPoint
    /// Rotation in radians. Unbounded — accumulates across full turns.
    public var rotation: CGFloat

    public init(position: CGPoint, rotation: CGFloat = 0) {
        self.position = position
        self.rotation = rotation
    }

    /// The pose at rest: origin, no rotation.
    public static let identity = Pose(position: .zero, rotation: 0)

    /// Returns a copy moved to a new position.
    public func moved(to p: CGPoint) -> Pose { Pose(position: p, rotation: rotation) }

    /// Returns a copy rotated to a new angle (radians).
    public func rotated(to r: CGFloat) -> Pose { Pose(position: position, rotation: r) }
}
