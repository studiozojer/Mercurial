//
//  Transform.swift
//  Mercurial
//
//  Immutable value type for 2D pan/zoom transformations.
//  Provides coordinate space conversions between canvas and viewport.
//

import Foundation
import CoreGraphics

// MARK: - Transform Configuration

/// Configuration for transform scale limits and element scaling behavior.
public struct TransformConfiguration: Equatable, Sendable {
    /// Minimum allowed zoom scale.
    public var minScale: CGFloat

    /// Maximum allowed zoom scale.
    public var maxScale: CGFloat

    /// Scaling multiplier for hit areas (scales slower than content).
    /// At 3x zoom with 0.3 multiplier: hit area scales to 1.6x.
    public var hitAreaMultiplier: CGFloat

    /// Scaling multiplier for text (scales slower than content).
    /// At 3x zoom with 0.4 multiplier: text scales to 1.8x.
    public var textMultiplier: CGFloat

    /// Scaling multiplier for icons/glyphs (scales slower than content).
    /// At 3x zoom with 0.5 multiplier: glyph scales to 2.0x.
    public var glyphMultiplier: CGFloat

    /// Creates a transform configuration.
    public init(
        minScale: CGFloat = 1.0,
        maxScale: CGFloat = 3.0,
        hitAreaMultiplier: CGFloat = 0.3,
        textMultiplier: CGFloat = 0.4,
        glyphMultiplier: CGFloat = 0.5
    ) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.hitAreaMultiplier = hitAreaMultiplier
        self.textMultiplier = textMultiplier
        self.glyphMultiplier = glyphMultiplier
    }

    /// Default configuration with standard iOS-like behavior.
    public static let `default` = TransformConfiguration()

    /// Map-like configuration allowing zoom out below 1x.
    public static let map = TransformConfiguration(minScale: 0.5, maxScale: 5.0)

    /// Image viewer configuration with higher max zoom.
    public static let imageViewer = TransformConfiguration(minScale: 1.0, maxScale: 10.0)
}

// MARK: - Transform

/// Immutable value type representing zoom and pan transformations.
///
/// Manages coordinate space conversions between:
/// - **Canvas space**: Coordinates used for rendering and hit testing
/// - **Viewport space**: Screen coordinates with zoom and pan applied
///
/// The transform applies scale first (around center), then translation.
///
/// ## Usage
/// ```swift
/// let transform = Transform(scale: 2.0, offset: CGPoint(x: 100, y: 50))
///
/// // Convert tap location to canvas space for hit testing
/// let canvasPoint = transform.toCanvas(tapLocation, center: viewCenter)
///
/// // Convert canvas point to viewport space for rendering
/// let viewportPoint = transform.toViewport(nodePosition, center: viewCenter)
/// ```
public struct Transform: Equatable, Sendable {
    // MARK: - Properties

    /// Zoom scale factor (1.0 = no zoom).
    public let scale: CGFloat

    /// Pan offset in viewport space.
    public let offset: CGPoint

    /// Configuration for scale limits and element scaling.
    public let configuration: TransformConfiguration

    // MARK: - Identity Transform

    /// Identity transform (no zoom, no pan).
    public static let identity = Transform(scale: 1.0, offset: .zero)

    // MARK: - Initialization

    /// Creates a new transform with the specified scale and offset.
    ///
    /// - Parameters:
    ///   - scale: Zoom scale factor (clamped to configuration bounds)
    ///   - offset: Pan offset in viewport coordinates
    ///   - configuration: Scale limits and element scaling configuration
    public init(
        scale: CGFloat,
        offset: CGPoint,
        configuration: TransformConfiguration = .default
    ) {
        self.scale = min(max(scale, configuration.minScale), configuration.maxScale)
        self.offset = offset
        self.configuration = configuration
    }

    // MARK: - Transform Creation (Immutable Updates)

    /// Returns a new transform with the specified scale applied.
    ///
    /// - Parameter newScale: The new zoom scale (will be clamped to bounds)
    /// - Returns: New transform with updated scale
    public func withScale(_ newScale: CGFloat) -> Transform {
        Transform(scale: newScale, offset: offset, configuration: configuration)
    }

    /// Returns a new transform with the specified offset applied.
    ///
    /// - Parameter newOffset: The new pan offset
    /// - Returns: New transform with updated offset
    public func withOffset(_ newOffset: CGPoint) -> Transform {
        Transform(scale: scale, offset: newOffset, configuration: configuration)
    }

    /// Returns a new transform with scale and offset updated.
    ///
    /// - Parameters:
    ///   - newScale: The new zoom scale
    ///   - newOffset: The new pan offset
    /// - Returns: New transform with both values updated
    public func with(scale newScale: CGFloat, offset newOffset: CGPoint) -> Transform {
        Transform(scale: newScale, offset: newOffset, configuration: configuration)
    }

    /// Returns a new transform with offset adjusted by delta.
    ///
    /// - Parameter delta: Offset delta to add
    /// - Returns: New transform with offset adjusted
    public func offsetBy(_ delta: CGPoint) -> Transform {
        Transform(
            scale: scale,
            offset: CGPoint(x: offset.x + delta.x, y: offset.y + delta.y),
            configuration: configuration
        )
    }

    /// Returns a new transform scaled by multiplier around anchor point.
    ///
    /// - Parameters:
    ///   - multiplier: Scale multiplier (e.g., 1.1 for 10% zoom in)
    ///   - anchor: Anchor point in viewport space (e.g., pinch center)
    ///   - center: Canvas center point
    /// - Returns: New transform with scale and offset adjusted to keep anchor stationary
    public func scaled(by multiplier: CGFloat, anchor: CGPoint, center: CGPoint) -> Transform {
        let newScale = scale * multiplier

        // Calculate offset adjustment to keep anchor point stationary
        // When scaling, the anchor point should stay at the same screen position
        let anchorInCanvas = toCanvas(anchor, center: center)
        let newTransform = Transform(scale: newScale, offset: offset, configuration: configuration)
        let anchorAfterScale = newTransform.toViewport(anchorInCanvas, center: center)

        let offsetAdjustment = CGPoint(
            x: anchor.x - anchorAfterScale.x,
            y: anchor.y - anchorAfterScale.y
        )

        return Transform(
            scale: newScale,
            offset: CGPoint(x: offset.x + offsetAdjustment.x, y: offset.y + offsetAdjustment.y),
            configuration: configuration
        )
    }

    // MARK: - Coordinate Transformations

    /// Converts a point from canvas space to viewport space.
    ///
    /// This is the forward transform: applies scale around center, then translation.
    ///
    /// - Parameters:
    ///   - canvasPoint: Point in canvas coordinate space
    ///   - center: The center point of the canvas (usually viewport size / 2)
    /// - Returns: Point in viewport coordinate space
    public func toViewport(_ canvasPoint: CGPoint, center: CGPoint) -> CGPoint {
        // Translate to origin, scale, translate back, then apply offset
        let translatedToOrigin = CGPoint(
            x: canvasPoint.x - center.x,
            y: canvasPoint.y - center.y
        )

        let scaled = CGPoint(
            x: translatedToOrigin.x * scale,
            y: translatedToOrigin.y * scale
        )

        return CGPoint(
            x: scaled.x + center.x + offset.x,
            y: scaled.y + center.y + offset.y
        )
    }

    /// Converts a point from viewport space to canvas space.
    ///
    /// This is the inverse transform: removes translation, then removes scale.
    /// Use this for hit testing - convert tap location to canvas space before testing.
    ///
    /// - Parameters:
    ///   - viewportPoint: Point in viewport coordinate space (e.g., tap location)
    ///   - center: The center point of the canvas (usually viewport size / 2)
    ///   - initialOffset: Optional initial offset for content positioning
    /// - Returns: Point in canvas coordinate space (for hit testing)
    public func toCanvas(_ viewportPoint: CGPoint, center: CGPoint, initialOffset: CGPoint = .zero) -> CGPoint {
        // Remove total offset (user pan + initial positioning)
        let totalOffset = CGPoint(
            x: initialOffset.x + offset.x,
            y: initialOffset.y + offset.y
        )

        let withoutOffset = CGPoint(
            x: viewportPoint.x - totalOffset.x,
            y: viewportPoint.y - totalOffset.y
        )

        let translatedToOrigin = CGPoint(
            x: withoutOffset.x - center.x,
            y: withoutOffset.y - center.y
        )

        let unscaled = CGPoint(
            x: translatedToOrigin.x / scale,
            y: translatedToOrigin.y / scale
        )

        return CGPoint(
            x: unscaled.x + center.x,
            y: unscaled.y + center.y
        )
    }

    /// Converts a size/distance from canvas space to viewport space.
    ///
    /// - Parameter canvasSize: Size in canvas coordinate space
    /// - Returns: Size in viewport coordinate space
    public func toViewport(_ canvasSize: CGFloat) -> CGFloat {
        canvasSize * scale
    }

    /// Converts a size/distance from viewport space to canvas space.
    ///
    /// - Parameter viewportSize: Size in viewport coordinate space
    /// - Returns: Size in canvas coordinate space
    public func toCanvas(_ viewportSize: CGFloat) -> CGFloat {
        viewportSize / scale
    }

    // MARK: - Element Scaling

    /// Returns the scale factor for hit area radius.
    ///
    /// Hit areas scale slower than content to maintain usability at all zoom levels.
    /// Formula: `1.0 + (scale - 1.0) * hitAreaMultiplier`
    ///
    /// With default 0.3 multiplier:
    /// - At 1.0x zoom: 1.0x hit area
    /// - At 2.0x zoom: 1.3x hit area
    /// - At 3.0x zoom: 1.6x hit area
    public func hitAreaScale() -> CGFloat {
        1.0 + (scale - 1.0) * configuration.hitAreaMultiplier
    }

    /// Returns the scale factor for text rendering.
    ///
    /// Text scales slower than content to maintain readability.
    /// Formula: `1.0 + (scale - 1.0) * textMultiplier`
    ///
    /// With default 0.4 multiplier:
    /// - At 1.0x zoom: 1.0x text size
    /// - At 2.0x zoom: 1.4x text size
    /// - At 3.0x zoom: 1.8x text size
    public func textScale() -> CGFloat {
        1.0 + (scale - 1.0) * configuration.textMultiplier
    }

    /// Returns the scale factor for glyph/icon rendering.
    ///
    /// Glyphs scale slower than content to maintain visual balance.
    /// Formula: `1.0 + (scale - 1.0) * glyphMultiplier`
    ///
    /// With default 0.5 multiplier:
    /// - At 1.0x zoom: 1.0x glyph size
    /// - At 2.0x zoom: 1.5x glyph size
    /// - At 3.0x zoom: 2.0x glyph size
    public func glyphScale() -> CGFloat {
        1.0 + (scale - 1.0) * configuration.glyphMultiplier
    }

    /// Returns a custom element scale using the given multiplier.
    ///
    /// - Parameter multiplier: Scale multiplier (0.0 = no scaling, 1.0 = full scaling)
    /// - Returns: Interpolated scale factor
    public func elementScale(multiplier: CGFloat) -> CGFloat {
        1.0 + (scale - 1.0) * multiplier
    }

    // MARK: - State Queries

    /// Whether this transform has any zoom applied (scale != 1.0).
    public var isZoomed: Bool {
        scale != 1.0
    }

    /// Whether this transform has any pan applied (offset != .zero).
    public var isPanned: Bool {
        offset != .zero
    }

    /// Whether this is the identity transform (no zoom, no pan).
    public var isIdentity: Bool {
        scale == 1.0 && offset == .zero
    }

    /// Whether zoom is at minimum scale.
    public var isAtMinScale: Bool {
        scale <= configuration.minScale
    }

    /// Whether zoom is at maximum scale.
    public var isAtMaxScale: Bool {
        scale >= configuration.maxScale
    }
}

// MARK: - CGPoint Distance Extension

extension CGPoint {
    /// Calculates the Euclidean distance from this point to another.
    ///
    /// - Parameter other: The other point
    /// - Returns: Distance between the two points
    public func distance(to other: CGPoint) -> CGFloat {
        let dx = other.x - x
        let dy = other.y - y
        return sqrt(dx * dx + dy * dy)
    }
}
