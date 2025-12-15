//
//  HitTesting.swift
//  Mercurial
//
//  Hit testing protocols and utilities for interactive canvas elements.
//

import Foundation
import CoreGraphics

// MARK: - Hit Testing Protocol

/// A type that can be hit-tested at a point.
///
/// Conform to this protocol to make elements selectable via tap gestures.
/// The default implementation uses circular hit areas based on `hitRadius`.
///
/// ## Example
/// ```swift
/// struct MapPin: Hittable {
///     let id: String
///     var position: CGPoint
///     var hitRadius: CGFloat { 22 }  // 44pt touch target
/// }
///
/// let pin = MapPin(id: "home", position: CGPoint(x: 100, y: 200))
/// if pin.hitTest(location: tapLocation) {
///     // Pin was tapped
/// }
/// ```
public protocol Hittable: Identifiable {
    /// Position in canvas coordinate space.
    var position: CGPoint { get }

    /// Hit radius for circular hit testing.
    /// Apple HIG recommends minimum 44pt touch targets.
    var hitRadius: CGFloat { get }

    /// Tests if a location hits this element.
    ///
    /// Default implementation uses circular hit area with `hitRadius`.
    /// Override for custom hit shapes (rectangles, polygons, etc.).
    ///
    /// - Parameter location: Point in canvas coordinate space
    /// - Returns: `true` if the location hits this element
    func hitTest(location: CGPoint) -> Bool
}

// MARK: - Default Implementation

extension Hittable {
    /// Default circular hit test using `hitRadius`.
    public func hitTest(location: CGPoint) -> Bool {
        let dx = location.x - position.x
        let dy = location.y - position.y
        let distanceSquared = dx * dx + dy * dy
        return distanceSquared <= hitRadius * hitRadius
    }

    /// Distance from this element's position to a point.
    public func distance(to point: CGPoint) -> CGFloat {
        position.distance(to: point)
    }
}

// MARK: - Rectangular Hit Testing

/// A type that uses rectangular hit areas instead of circular.
public protocol RectHittable: Identifiable {
    /// Position (center) in canvas coordinate space.
    var position: CGPoint { get }

    /// Size of the hit rectangle.
    var hitSize: CGSize { get }

    /// Tests if a location hits this element's rectangle.
    func hitTest(location: CGPoint) -> Bool
}

extension RectHittable {
    /// Default rectangular hit test.
    public func hitTest(location: CGPoint) -> Bool {
        let halfWidth = hitSize.width / 2
        let halfHeight = hitSize.height / 2
        return location.x >= position.x - halfWidth &&
               location.x <= position.x + halfWidth &&
               location.y >= position.y - halfHeight &&
               location.y <= position.y + halfHeight
    }
}

// MARK: - Hit Test Helpers

/// Utilities for hit testing collections of elements.
public enum HitTest {

    /// Finds all elements hit by a location.
    ///
    /// - Parameters:
    ///   - location: Point in canvas coordinate space
    ///   - elements: Elements to test
    /// - Returns: Array of elements that were hit
    public static func findHits<T: Hittable>(
        at location: CGPoint,
        in elements: [T]
    ) -> [T] {
        elements.filter { $0.hitTest(location: location) }
    }

    /// Finds the closest hit element to a location.
    ///
    /// When multiple elements are hit, returns the one closest to the tap point.
    /// This provides intuitive selection when elements overlap.
    ///
    /// - Parameters:
    ///   - location: Point in canvas coordinate space
    ///   - elements: Elements to test
    /// - Returns: Closest hit element, or `nil` if nothing was hit
    public static func findClosest<T: Hittable>(
        at location: CGPoint,
        in elements: [T]
    ) -> T? {
        let hits = findHits(at: location, in: elements)
        return hits.min { $0.distance(to: location) < $1.distance(to: location) }
    }

    /// Finds all elements hit by a location, with transform applied.
    ///
    /// Converts viewport location to canvas space before hit testing.
    /// Also scales hit radii according to transform's `hitAreaScale()`.
    ///
    /// - Parameters:
    ///   - viewportLocation: Point in viewport (screen) coordinate space
    ///   - elements: Elements to test (positions in canvas space)
    ///   - transform: Current pan/zoom transform
    ///   - center: Canvas center point
    ///   - initialOffset: Optional initial content offset
    /// - Returns: Array of elements that were hit
    public static func findHits<T: Hittable>(
        at viewportLocation: CGPoint,
        in elements: [T],
        transform: Transform,
        center: CGPoint,
        initialOffset: CGPoint = .zero
    ) -> [T] {
        let canvasLocation = transform.toCanvas(
            viewportLocation,
            center: center,
            initialOffset: initialOffset
        )
        let hitScale = transform.hitAreaScale()

        return elements.filter { element in
            let scaledRadius = element.hitRadius * hitScale
            let dx = canvasLocation.x - element.position.x
            let dy = canvasLocation.y - element.position.y
            let distanceSquared = dx * dx + dy * dy
            return distanceSquared <= scaledRadius * scaledRadius
        }
    }

    /// Finds the closest hit element with transform applied.
    ///
    /// - Parameters:
    ///   - viewportLocation: Point in viewport (screen) coordinate space
    ///   - elements: Elements to test
    ///   - transform: Current pan/zoom transform
    ///   - center: Canvas center point
    ///   - initialOffset: Optional initial content offset
    /// - Returns: Closest hit element, or `nil` if nothing was hit
    public static func findClosest<T: Hittable>(
        at viewportLocation: CGPoint,
        in elements: [T],
        transform: Transform,
        center: CGPoint,
        initialOffset: CGPoint = .zero
    ) -> T? {
        let canvasLocation = transform.toCanvas(
            viewportLocation,
            center: center,
            initialOffset: initialOffset
        )

        let hits = findHits(
            at: viewportLocation,
            in: elements,
            transform: transform,
            center: center,
            initialOffset: initialOffset
        )

        return hits.min { $0.distance(to: canvasLocation) < $1.distance(to: canvasLocation) }
    }

    /// Checks if a location would hit any element (without returning which one).
    ///
    /// Useful for deciding whether to handle a gesture (e.g., skip zoom if tap hits an element).
    ///
    /// - Parameters:
    ///   - viewportLocation: Point in viewport coordinate space
    ///   - elements: Elements to test
    ///   - transform: Current pan/zoom transform
    ///   - center: Canvas center point
    ///   - initialOffset: Optional initial content offset
    /// - Returns: `true` if any element was hit
    public static func wouldHit<T: Hittable>(
        at viewportLocation: CGPoint,
        in elements: [T],
        transform: Transform,
        center: CGPoint,
        initialOffset: CGPoint = .zero
    ) -> Bool {
        let canvasLocation = transform.toCanvas(
            viewportLocation,
            center: center,
            initialOffset: initialOffset
        )
        let hitScale = transform.hitAreaScale()

        return elements.contains { element in
            let scaledRadius = element.hitRadius * hitScale
            let dx = canvasLocation.x - element.position.x
            let dy = canvasLocation.y - element.position.y
            let distanceSquared = dx * dx + dy * dy
            return distanceSquared <= scaledRadius * scaledRadius
        }
    }
}

// MARK: - Hit Test Result

/// Result of a hit test operation.
public struct HitTestResult<T: Hittable>: Sendable where T: Sendable {
    /// Elements that were hit.
    public let hits: [T]

    /// The closest hit element (if any).
    public let closest: T?

    /// Location in canvas coordinate space where the hit test was performed.
    public let canvasLocation: CGPoint

    /// Whether any element was hit.
    public var didHit: Bool { !hits.isEmpty }

    /// Whether the tap was in empty space (no hits).
    public var isEmptySpaceTap: Bool { hits.isEmpty }

    /// Creates a hit test result.
    public init(hits: [T], closest: T?, canvasLocation: CGPoint) {
        self.hits = hits
        self.closest = closest
        self.canvasLocation = canvasLocation
    }
}

extension HitTest {
    /// Performs a complete hit test and returns a result object.
    ///
    /// - Parameters:
    ///   - viewportLocation: Point in viewport coordinate space
    ///   - elements: Elements to test
    ///   - transform: Current pan/zoom transform
    ///   - center: Canvas center point
    ///   - initialOffset: Optional initial content offset
    /// - Returns: Hit test result with all hits and closest element
    public static func test<T: Hittable & Sendable>(
        at viewportLocation: CGPoint,
        in elements: [T],
        transform: Transform,
        center: CGPoint,
        initialOffset: CGPoint = .zero
    ) -> HitTestResult<T> {
        let canvasLocation = transform.toCanvas(
            viewportLocation,
            center: center,
            initialOffset: initialOffset
        )

        let hits = findHits(
            at: viewportLocation,
            in: elements,
            transform: transform,
            center: center,
            initialOffset: initialOffset
        )

        let closest = hits.min { $0.distance(to: canvasLocation) < $1.distance(to: canvasLocation) }

        return HitTestResult(
            hits: hits,
            closest: closest,
            canvasLocation: canvasLocation
        )
    }
}
