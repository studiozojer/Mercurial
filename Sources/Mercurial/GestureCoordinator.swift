//
//  GestureCoordinator.swift
//  Mercurial
//
//  Observable coordinator for pan/zoom gestures with momentum.
//  Integrates Transform, Momentum2DAnimator, and hit testing.
//

import Foundation
import CoreGraphics
import QuartzCore
import Observation

// MARK: - Gesture State

/// Current state of gesture handling.
public enum GestureState: Equatable, Sendable {
    /// No active gesture or animation.
    case idle

    /// User is actively dragging.
    case dragging

    /// User is actively pinching to zoom.
    case zooming

    /// Momentum animation is running after drag release.
    case momentum

    /// Spring animation is returning content to bounds.
    case bouncing
}

// MARK: - Gesture Coordinator Configuration

/// Configuration for gesture behavior and bounds.
public struct GestureCoordinatorConfiguration: Equatable, Sendable {
    /// Transform configuration (scale limits, element scaling).
    public var transform: TransformConfiguration

    /// Physics configuration for momentum.
    public var physics: PhysicsConfiguration

    /// Optional content bounds in canvas space.
    /// When set, panning is constrained and rubber-banding applies at edges.
    public var contentBounds: PhysicsBounds?

    /// Whether to enable rubber-band effect when dragging past bounds.
    public var rubberBandEnabled: Bool

    /// Rubber-band configuration.
    public var rubberBand: RubberBandConfiguration

    /// Minimum velocity to trigger momentum (pt/s).
    public var minimumMomentumVelocity: CGFloat

    /// Creates a gesture coordinator configuration.
    public init(
        transform: TransformConfiguration = .default,
        physics: PhysicsConfiguration = .default,
        contentBounds: PhysicsBounds? = nil,
        rubberBandEnabled: Bool = true,
        rubberBand: RubberBandConfiguration = .default,
        minimumMomentumVelocity: CGFloat = 50
    ) {
        self.transform = transform
        self.physics = physics
        self.contentBounds = contentBounds
        self.rubberBandEnabled = rubberBandEnabled
        self.rubberBand = rubberBand
        self.minimumMomentumVelocity = minimumMomentumVelocity
    }

    /// Default configuration.
    public static let `default` = GestureCoordinatorConfiguration()
}

// MARK: - Gesture Coordinator

/// Coordinates pan and zoom gestures with momentum physics.
///
/// `GestureCoordinator` manages the relationship between user gestures,
/// transform state, and momentum animations. It handles:
///
/// - Pan gestures with momentum and boundary constraints
/// - Pinch-to-zoom with anchor point preservation
/// - Rubber-band effect at content boundaries
/// - Transform-aware hit testing coordination
///
/// ## Usage with SwiftUI
/// ```swift
/// struct ZoomableCanvas: View {
///     @State private var coordinator = GestureCoordinator()
///
///     var body: some View {
///         TimelineView(.animation(paused: !coordinator.isAnimating)) { timeline in
///             Canvas { context, size in
///                 // Use coordinator.transform for rendering
///             }
///             .gesture(panGesture)
///             .gesture(zoomGesture)
///             .onChange(of: timeline.date) { _, _ in
///                 coordinator.update()
///             }
///         }
///     }
///
///     var panGesture: some Gesture {
///         DragGesture()
///             .onChanged { coordinator.panChanged($0.translation, center: center) }
///             .onEnded { coordinator.panEnded(velocity: $0.velocity, center: center) }
///     }
/// }
/// ```
@Observable
@MainActor
public final class GestureCoordinator: @unchecked Sendable {
    // MARK: - Public Properties

    /// Current transform state.
    public private(set) var transform: Transform

    /// Current gesture/animation state.
    public private(set) var state: GestureState = .idle

    /// Configuration for gestures and physics.
    public var configuration: GestureCoordinatorConfiguration {
        didSet {
            // Update transform configuration
            transform = Transform(
                scale: transform.scale,
                offset: transform.offset,
                configuration: configuration.transform
            )
            // Update animator configuration
            momentumAnimator.configuration = configuration.physics
        }
    }

    /// Whether any animation is currently running.
    public var isAnimating: Bool {
        state == .momentum || state == .bouncing
    }

    /// Callback invoked when transform changes.
    public var onTransformChanged: ((Transform) -> Void)?

    /// Callback invoked when gesture state changes.
    public var onStateChanged: ((GestureState) -> Void)?

    // MARK: - Private Properties

    private var momentumAnimator: Momentum2DAnimator
    private var lastUpdateTime: CFTimeInterval = 0
    private var dragStartOffset: CGPoint = .zero
    private var zoomStartScale: CGFloat = 1.0
    private var zoomStartOffset: CGPoint = .zero

    // MARK: - Initialization

    /// Creates a gesture coordinator with optional configuration.
    ///
    /// - Parameter configuration: Configuration for gestures and physics
    public init(configuration: GestureCoordinatorConfiguration = .default) {
        self.configuration = configuration
        self.transform = Transform(
            scale: 1.0,
            offset: .zero,
            configuration: configuration.transform
        )
        self.momentumAnimator = Momentum2DAnimator(configuration: configuration.physics)
    }

    // MARK: - Pan Gesture Handling

    /// Called when a pan gesture begins.
    ///
    /// Captures the current offset for relative translation calculations.
    public func panBegan() {
        momentumAnimator.stop()
        dragStartOffset = transform.offset
        setState(.dragging)
    }

    /// Called when a pan gesture changes.
    ///
    /// - Parameters:
    ///   - translation: Cumulative translation from gesture start
    ///   - center: Canvas center point (usually viewport size / 2)
    public func panChanged(_ translation: CGPoint, center: CGPoint) {
        if state != .dragging {
            panBegan()
        }

        var newOffset = CGPoint(
            x: dragStartOffset.x + translation.x,
            y: dragStartOffset.y + translation.y
        )

        // Apply rubber-band if we have bounds and it's enabled
        if let bounds = configuration.contentBounds, configuration.rubberBandEnabled {
            newOffset = applyRubberBand(to: newOffset, bounds: bounds, center: center)
        }

        setTransform(transform.withOffset(newOffset))
    }

    /// Called when a pan gesture ends.
    ///
    /// Starts momentum animation if velocity exceeds threshold.
    ///
    /// - Parameters:
    ///   - velocity: Gesture velocity at release
    ///   - center: Canvas center point
    public func panEnded(velocity: CGPoint, center: CGPoint) {
        let speed = Physics.speed(velocity)

        if speed > configuration.minimumMomentumVelocity {
            startMomentum(velocity: velocity, center: center)
        } else if let bounds = configuration.contentBounds {
            // Check if we need to bounce back
            let effectiveBounds = effectivePanBounds(for: bounds, center: center)
            let displacement = effectiveBounds.displacement(from: transform.offset)
            if displacement != .zero {
                startBounce(center: center)
            } else {
                setState(.idle)
            }
        } else {
            setState(.idle)
        }
    }

    /// Called when a pan gesture is cancelled.
    public func panCancelled() {
        setState(.idle)
    }

    // MARK: - Zoom Gesture Handling

    /// Called when a zoom gesture begins.
    ///
    /// Captures current scale and offset for relative calculations.
    public func zoomBegan() {
        momentumAnimator.stop()
        zoomStartScale = transform.scale
        zoomStartOffset = transform.offset
        setState(.zooming)
    }

    /// Called when a zoom gesture changes.
    ///
    /// - Parameters:
    ///   - scale: Cumulative scale from gesture start (1.0 = no change)
    ///   - anchor: Anchor point in viewport space (pinch center)
    ///   - center: Canvas center point
    public func zoomChanged(scale: CGFloat, anchor: CGPoint, center: CGPoint) {
        if state != .zooming {
            zoomBegan()
        }

        // Create transform at start state, then scale from anchor
        let startTransform = Transform(
            scale: zoomStartScale,
            offset: zoomStartOffset,
            configuration: configuration.transform
        )

        var scaledTransform = startTransform.scaled(
            by: scale,
            anchor: anchor,
            center: center
        )

        // Apply rubber-band if offset exceeds bounds at the new scale
        if let bounds = configuration.contentBounds, configuration.rubberBandEnabled {
            let constrainedOffset = applyRubberBand(
                to: scaledTransform.offset,
                bounds: bounds,
                center: center,
                atScale: scaledTransform.scale
            )
            scaledTransform = scaledTransform.withOffset(constrainedOffset)
        }

        setTransform(scaledTransform)
    }

    /// Called when a combined zoom+pan gesture changes.
    ///
    /// Use this when you want pinch gestures to support simultaneous panning
    /// (i.e., moving two fingers while pinching translates the content 1:1).
    ///
    /// - Parameters:
    ///   - scale: Cumulative scale from gesture start (1.0 = no change)
    ///   - anchor: Fixed anchor point in viewport space (where gesture started)
    ///   - panDelta: Translation since gesture start (currentPosition - startPosition)
    ///   - center: Canvas center point
    public func zoomPanChanged(
        scale: CGFloat,
        anchor: CGPoint,
        panDelta: CGPoint,
        center: CGPoint
    ) {
        if state != .zooming {
            zoomBegan()
        }

        // Create transform at start state
        let startTransform = Transform(
            scale: zoomStartScale,
            offset: zoomStartOffset,
            configuration: configuration.transform
        )

        // Apply zoom at the fixed anchor point
        let scaledTransform = startTransform.scaled(
            by: scale,
            anchor: anchor,
            center: center
        )

        // Add pan delta (1:1 with finger movement)
        var combinedOffset = CGPoint(
            x: scaledTransform.offset.x + panDelta.x,
            y: scaledTransform.offset.y + panDelta.y
        )

        // Apply rubber-band if offset exceeds bounds at the new scale
        if let bounds = configuration.contentBounds, configuration.rubberBandEnabled {
            combinedOffset = applyRubberBand(
                to: combinedOffset,
                bounds: bounds,
                center: center,
                atScale: scaledTransform.scale
            )
        }

        let finalTransform = scaledTransform.withOffset(combinedOffset)
        setTransform(finalTransform)
    }

    /// Called when a zoom gesture ends.
    ///
    /// - Parameter center: Canvas center point
    public func zoomEnded(center: CGPoint) {
        if let bounds = configuration.contentBounds {
            let effectiveBounds = effectivePanBounds(for: bounds, center: center)
            let displacement = effectiveBounds.displacement(from: transform.offset)
            if displacement != .zero {
                startBounce(center: center)
            } else {
                setState(.idle)
            }
        } else {
            setState(.idle)
        }
    }

    /// Called when a zoom gesture is cancelled.
    public func zoomCancelled() {
        setState(.idle)
    }

    // MARK: - Animation Update

    /// Updates momentum/bounce animation.
    ///
    /// Call this from a `TimelineView` or display link callback.
    /// Does nothing if no animation is active.
    ///
    /// - Returns: `true` if animation is still active
    @discardableResult
    public func update() -> Bool {
        guard isAnimating else { return false }

        let stillActive = momentumAnimator.update()
        let newOffset = momentumAnimator.position

        setTransform(transform.withOffset(newOffset))

        if !stillActive {
            setState(.idle)
        }

        return stillActive
    }

    // MARK: - State Management

    /// Resets to identity transform.
    public func reset() {
        momentumAnimator.stop()
        setTransform(Transform(
            scale: 1.0,
            offset: .zero,
            configuration: configuration.transform
        ))
        setState(.idle)
    }

    /// Sets a specific transform directly.
    ///
    /// Stops any active animation.
    ///
    /// - Parameter newTransform: Transform to apply
    public func setTransformDirectly(_ newTransform: Transform) {
        momentumAnimator.stop()
        setTransform(newTransform)
        setState(.idle)
    }

    /// Stops any active animation.
    public func stopAnimation() {
        momentumAnimator.stop()
        setState(.idle)
    }

    // MARK: - Private Methods

    private func setTransform(_ newTransform: Transform) {
        guard newTransform != transform else { return }
        transform = newTransform
        onTransformChanged?(transform)
    }

    private func setState(_ newState: GestureState) {
        guard newState != state else { return }
        state = newState
        onStateChanged?(state)
    }

    private func startMomentum(velocity: CGPoint, center: CGPoint) {
        if let bounds = configuration.contentBounds {
            momentumAnimator.bounds = effectivePanBounds(for: bounds, center: center)
        } else {
            momentumAnimator.bounds = nil
        }

        momentumAnimator.setPosition(transform.offset)
        momentumAnimator.start(velocity: velocity)
        setState(.momentum)
    }

    private func startBounce(center: CGPoint) {
        if let bounds = configuration.contentBounds {
            momentumAnimator.bounds = effectivePanBounds(for: bounds, center: center)
        }

        momentumAnimator.setPosition(transform.offset)
        // Start with zero velocity to trigger bounce-back
        momentumAnimator.start(velocity: .zero)
        setState(.bouncing)
    }

    /// Calculates effective pan bounds accounting for scale.
    ///
    /// When zoomed in, you can pan further. When zoomed out, bounds shrink.
    ///
    /// - Parameters:
    ///   - contentBounds: The content bounds in canvas space
    ///   - center: Canvas center point
    ///   - scale: Scale to use for calculation (defaults to current transform scale)
    /// - Returns: Effective bounds scaled appropriately
    private func effectivePanBounds(
        for contentBounds: PhysicsBounds,
        center: CGPoint,
        atScale scale: CGFloat? = nil
    ) -> PhysicsBounds {
        let effectiveScale = scale ?? transform.scale
        // At scale 1.0, offset bounds match content bounds
        // At scale 2.0, offset can go twice as far
        let scaledMin = CGPoint(
            x: contentBounds.min.x * effectiveScale,
            y: contentBounds.min.y * effectiveScale
        )
        let scaledMax = CGPoint(
            x: contentBounds.max.x * effectiveScale,
            y: contentBounds.max.y * effectiveScale
        )
        return PhysicsBounds(min: scaledMin, max: scaledMax)
    }

    /// Applies rubber-band resistance to offset when past bounds.
    ///
    /// - Parameters:
    ///   - offset: The offset to constrain
    ///   - bounds: Content bounds in canvas space
    ///   - center: Canvas center point
    ///   - scale: Scale to use for effective bounds (defaults to current transform scale)
    /// - Returns: Offset with rubber-band resistance applied
    private func applyRubberBand(
        to offset: CGPoint,
        bounds: PhysicsBounds,
        center: CGPoint,
        atScale scale: CGFloat? = nil
    ) -> CGPoint {
        let effectiveBounds = effectivePanBounds(for: bounds, center: center, atScale: scale)

        var result = offset

        // Apply rubber-band on X axis
        if offset.x < effectiveBounds.min.x {
            let overshoot = effectiveBounds.min.x - offset.x
            let resistance = Physics.rubberBand(
                offset: overshoot,
                limit: configuration.rubberBand.limit,
                coefficient: configuration.rubberBand.coefficient
            )
            result.x = effectiveBounds.min.x - resistance
        } else if offset.x > effectiveBounds.max.x {
            let overshoot = offset.x - effectiveBounds.max.x
            let resistance = Physics.rubberBand(
                offset: overshoot,
                limit: configuration.rubberBand.limit,
                coefficient: configuration.rubberBand.coefficient
            )
            result.x = effectiveBounds.max.x + resistance
        }

        // Apply rubber-band on Y axis
        if offset.y < effectiveBounds.min.y {
            let overshoot = effectiveBounds.min.y - offset.y
            let resistance = Physics.rubberBand(
                offset: overshoot,
                limit: configuration.rubberBand.limit,
                coefficient: configuration.rubberBand.coefficient
            )
            result.y = effectiveBounds.min.y - resistance
        } else if offset.y > effectiveBounds.max.y {
            let overshoot = offset.y - effectiveBounds.max.y
            let resistance = Physics.rubberBand(
                offset: overshoot,
                limit: configuration.rubberBand.limit,
                coefficient: configuration.rubberBand.coefficient
            )
            result.y = effectiveBounds.max.y + resistance
        }

        return result
    }
}

// MARK: - Convenience Extensions

extension GestureCoordinator {
    /// Performs a hit test at viewport location using current transform.
    ///
    /// - Parameters:
    ///   - viewportLocation: Tap location in viewport space
    ///   - elements: Elements to test
    ///   - center: Canvas center point
    /// - Returns: Hit test result
    public func hitTest<T: Hittable & Sendable>(
        at viewportLocation: CGPoint,
        in elements: [T],
        center: CGPoint
    ) -> HitTestResult<T> {
        HitTest.test(
            at: viewportLocation,
            in: elements,
            transform: transform,
            center: center
        )
    }

    /// Checks if a tap would hit any element.
    ///
    /// - Parameters:
    ///   - viewportLocation: Tap location in viewport space
    ///   - elements: Elements to test
    ///   - center: Canvas center point
    /// - Returns: `true` if any element was hit
    public func wouldHit<T: Hittable>(
        at viewportLocation: CGPoint,
        in elements: [T],
        center: CGPoint
    ) -> Bool {
        HitTest.wouldHit(
            at: viewportLocation,
            in: elements,
            transform: transform,
            center: center
        )
    }

    /// Converts a viewport point to canvas space using current transform.
    ///
    /// - Parameters:
    ///   - viewportPoint: Point in viewport space
    ///   - center: Canvas center point
    /// - Returns: Point in canvas space
    public func toCanvas(_ viewportPoint: CGPoint, center: CGPoint) -> CGPoint {
        transform.toCanvas(viewportPoint, center: center)
    }

    /// Converts a canvas point to viewport space using current transform.
    ///
    /// - Parameters:
    ///   - canvasPoint: Point in canvas space
    ///   - center: Canvas center point
    /// - Returns: Point in viewport space
    public func toViewport(_ canvasPoint: CGPoint, center: CGPoint) -> CGPoint {
        transform.toViewport(canvasPoint, center: center)
    }
}
