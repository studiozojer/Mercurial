import CoreGraphics

// MARK: - Graph Node

public struct GraphNode: Identifiable, Sendable {
    public let id: String
    public var radius: CGFloat

    public init(id: String, radius: CGFloat = 12) {
        self.id = id
        self.radius = radius
    }
}

// MARK: - Graph Edge

public struct GraphEdge: Sendable {
    public let source: String
    public let target: String
    public var weight: CGFloat

    public init(source: String, target: String, weight: CGFloat = 0.5) {
        precondition(source != target, "Self-loops are not supported")
        self.source = source
        self.target = target
        self.weight = min(max(weight, 0.01), 1)
    }
}

// MARK: - Positioned Graph Node (Hit Testing)

public struct PositionedGraphNode: Hittable, Sendable {
    public let id: String
    public var position: CGPoint
    public var hitRadius: CGFloat

    public init(id: String, position: CGPoint, hitRadius: CGFloat = 22) {
        self.id = id
        self.position = position
        self.hitRadius = hitRadius
    }
}

// MARK: - Layout Configuration

public struct GraphLayoutConfiguration: Equatable, Sendable {
    public var spacing: CGFloat
    public var weightExponent: CGFloat
    public var padding: CGFloat
    public var maxIterations: Int
    public var convergenceThreshold: CGFloat
    public var animation: GraphAnimationConfiguration

    public init(
        spacing: CGFloat = 60,
        weightExponent: CGFloat = 1.5,
        padding: CGFloat = 20,
        maxIterations: Int = 50,
        convergenceThreshold: CGFloat = 0.001,
        animation: GraphAnimationConfiguration = .default
    ) {
        self.spacing = spacing
        self.weightExponent = weightExponent
        self.padding = padding
        self.maxIterations = maxIterations
        self.convergenceThreshold = convergenceThreshold
        self.animation = animation
    }

    public static let `default` = GraphLayoutConfiguration()

    public static let compact = GraphLayoutConfiguration(
        spacing: 40, weightExponent: 2.0, padding: 12
    )

    public static let spread = GraphLayoutConfiguration(
        spacing: 80, weightExponent: 1.0, padding: 24
    )
}

// MARK: - Animation Configuration

public struct GraphAnimationConfiguration: Equatable, Sendable {
    public var stiffness: CGFloat
    public var damping: CGFloat
    public var friction: CGFloat

    public init(
        stiffness: CGFloat = 120,
        damping: CGFloat = 18,
        friction: CGFloat = 0.85
    ) {
        self.stiffness = stiffness
        self.damping = damping
        self.friction = friction
    }

    public static let `default` = GraphAnimationConfiguration()

    public static let snappy = GraphAnimationConfiguration(
        stiffness: 200, damping: 25, friction: 0.80
    )

    public static let gentle = GraphAnimationConfiguration(
        stiffness: 60, damping: 12, friction: 0.90
    )
}
