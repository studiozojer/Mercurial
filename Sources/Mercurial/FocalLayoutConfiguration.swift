// Sources/Mercurial/FocalLayoutConfiguration.swift

import CoreGraphics

/// Configuration for focal point graph layout.
public struct FocalLayoutConfiguration: Equatable, Sendable {

    /// Maximum number of focal points to identify.
    public var maxFocalPoints: Int

    /// Distance from focal point for loosely connected nodes.
    public var orbitRadius: CGFloat

    /// Minimum distance from focal point for tightly connected nodes.
    public var minOrbitRadius: CGFloat

    /// Padding from canvas edges.
    public var padding: CGFloat

    /// Gap between nodes for overlap resolution.
    public var overlapGap: CGFloat

    /// Number of overlap resolution passes.
    public var overlapPasses: Int

    public init(
        maxFocalPoints: Int = 3,
        orbitRadius: CGFloat = 100,
        minOrbitRadius: CGFloat = 35,
        padding: CGFloat = 20,
        overlapGap: CGFloat = 8,
        overlapPasses: Int = 30
    ) {
        self.maxFocalPoints = maxFocalPoints
        self.orbitRadius = orbitRadius
        self.minOrbitRadius = minOrbitRadius
        self.padding = padding
        self.overlapGap = overlapGap
        self.overlapPasses = overlapPasses
    }

    public static let `default` = FocalLayoutConfiguration()
}
