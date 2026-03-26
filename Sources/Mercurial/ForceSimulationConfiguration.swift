// Sources/Mercurial/ForceSimulationConfiguration.swift

import CoreGraphics

/// Configuration for force-directed graph simulation.
///
/// Controls the balance between repulsion, attraction, centering, and damping
/// that determines how the graph settles into its final layout.
public struct ForceSimulationConfiguration: Equatable, Sendable {

    /// How strongly nodes push each other apart (inverse-square repulsion).
    public var repulsionStrength: CGFloat

    /// Edge spring stiffness (higher = stronger pull along edges).
    public var springStiffness: CGFloat

    /// Base rest length for edge springs. Scaled by edge weight:
    /// `restLength = springRestLengthBase / weight`.
    /// High weight (tight orb) = shorter rest length = closer together.
    public var springRestLengthBase: CGFloat

    /// Spring damping coefficient (resists velocity along edges).
    public var springDamping: CGFloat

    /// How strongly nodes pull toward the canvas center.
    public var centeringStrength: CGFloat

    /// Velocity retention per tick (0.0 = full stop, 1.0 = no friction).
    public var friction: CGFloat

    /// Kinetic energy below which `isSettled` becomes true.
    public var settleThreshold: CGFloat

    /// Minimum distance for collision avoidance between node radii.
    /// Set to 0 to disable collision avoidance.
    public var collisionPadding: CGFloat

    public init(
        repulsionStrength: CGFloat = 8000,
        springStiffness: CGFloat = 0.3,
        springRestLengthBase: CGFloat = 60,
        springDamping: CGFloat = 0.5,
        centeringStrength: CGFloat = 0.01,
        friction: CGFloat = 0.85,
        settleThreshold: CGFloat = 0.5,
        collisionPadding: CGFloat = 4
    ) {
        self.repulsionStrength = repulsionStrength
        self.springStiffness = springStiffness
        self.springRestLengthBase = springRestLengthBase
        self.springDamping = springDamping
        self.centeringStrength = centeringStrength
        self.friction = friction
        self.settleThreshold = settleThreshold
        self.collisionPadding = collisionPadding
    }

    public static let `default` = ForceSimulationConfiguration()
}
