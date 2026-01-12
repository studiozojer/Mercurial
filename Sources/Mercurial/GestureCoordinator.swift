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

/// Current state of gesture handling (includes animations).
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

    /// Spring animation to a target transform (e.g., double-tap zoom).
    case animatingToTarget
}

// MARK: - Gesture Input Mode

/// Tracks the active user gesture (separate from animation state).
///
/// Use this to determine what gesture the user is currently performing,
/// which helps coordinate between simultaneous gesture recognizers.
public enum GestureInputMode: Equatable, Sendable {
    /// No active touch gesture.
    case idle

    /// Single-finger pan gesture is active.
    case panning

    /// Two-finger pinch-zoom gesture is active.
    case zooming

    /// User lifted one finger during a zoom gesture (2→1 transition).
    /// The gesture is still conceptually a "zoom" but with single-finger panning.
    case singleFingerInZoom
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

    /// Touch classification configuration.
    public var touchClassification: TouchClassificationConfiguration

    /// Whether to disable momentum and spring animations (for accessibility).
    /// When true:
    /// - Momentum is disabled (gesture stops immediately on finger lift)
    /// - Spring animations are instant (snap to target instead of animating)
    /// - Rubber-band effect clamps to bounds immediately instead of bouncing
    /// Gestures still work normally during active touch.
    public var reduceMotion: Bool

    /// Creates a gesture coordinator configuration.
    public init(
        transform: TransformConfiguration = .default,
        physics: PhysicsConfiguration = .default,
        contentBounds: PhysicsBounds? = nil,
        rubberBandEnabled: Bool = true,
        rubberBand: RubberBandConfiguration = .default,
        minimumMomentumVelocity: CGFloat = 50,
        touchClassification: TouchClassificationConfiguration = .default,
        reduceMotion: Bool = false
    ) {
        self.transform = transform
        self.physics = physics
        self.contentBounds = contentBounds
        self.rubberBandEnabled = rubberBandEnabled
        self.rubberBand = rubberBand
        self.minimumMomentumVelocity = minimumMomentumVelocity
        self.touchClassification = touchClassification
        self.reduceMotion = reduceMotion
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

    /// Current user input mode (what gesture is active).
    /// Use this to coordinate between simultaneous gesture recognizers.
    public private(set) var inputMode: GestureInputMode = .idle

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
        state == .momentum || state == .bouncing || state == .animatingToTarget
    }

    /// Callback invoked when transform changes.
    public var onTransformChanged: ((Transform) -> Void)?

    /// Callback invoked when gesture state changes.
    public var onStateChanged: ((GestureState) -> Void)?

    // MARK: - Private Properties

    private var momentumAnimator: Momentum2DAnimator
    private var lastUpdateTime: CFTimeInterval = 0
    private var dragStartOffset: CGPoint = .zero
    private var dragTranslationBaseline: CGPoint = .zero
    private var zoomStartScale: CGFloat = 1.0
    private var zoomStartOffset: CGPoint = .zero
    private var zoomScaleBaseline: CGFloat = 1.0

    // Velocity tracking state
    private var velocityLastLocation: CGPoint = .zero
    private var velocityLastTime: CFTimeInterval = 0
    private var velocitySmoothed: CGPoint = .zero

    // Single-finger pan during zoom state
    private var singleFingerPanAnchor: CGPoint = .zero
    private var singleFingerPanStartOffset: CGPoint = .zero

    // Gesture intent tracking state
    private var zoomPanStartScale: CGFloat = 1.0
    private var zoomPanTotalPanDistance: CGFloat = 0
    private var zoomPanLastLocation: CGPoint = .zero

    // Spring animation to target transform state
    private var springTargetScale: CGFloat = 1.0
    private var springTargetOffset: CGPoint = .zero
    private var springScaleVelocity: CGFloat = 0
    private var springOffsetVelocity: CGPoint = .zero
    private var springLastUpdateTime: CFTimeInterval = 0

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
        dragTranslationBaseline = .zero
        inputMode = .panning
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

        // Subtract baseline to handle mid-gesture transitions (e.g., zoom → pan)
        let effectiveTranslation = CGPoint(
            x: translation.x - dragTranslationBaseline.x,
            y: translation.y - dragTranslationBaseline.y
        )

        var newOffset = CGPoint(
            x: dragStartOffset.x + effectiveTranslation.x,
            y: dragStartOffset.y + effectiveTranslation.y
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
    /// When reduceMotion is enabled, stops immediately and clamps to bounds.
    ///
    /// - Parameters:
    ///   - velocity: Gesture velocity at release
    ///   - center: Canvas center point
    public func panEnded(velocity: CGPoint, center: CGPoint) {
        inputMode = .idle

        // When reduce motion is enabled, skip momentum entirely
        if configuration.reduceMotion {
            // Clamp to bounds if needed (instant, no bounce)
            if let bounds = configuration.contentBounds {
                let effectiveBounds = effectivePanBounds(for: bounds, center: center)
                let clampedOffset = effectiveBounds.clamp(transform.offset)
                if clampedOffset != transform.offset {
                    setTransform(transform.withOffset(clampedOffset))
                }
            }
            setState(.idle)
            return
        }

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
        inputMode = .idle
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
        zoomScaleBaseline = 1.0

        // Reset gesture intent tracking
        zoomPanStartScale = transform.scale
        zoomPanTotalPanDistance = 0
        zoomPanLastLocation = .zero

        inputMode = .zooming
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

        // Compute effective scale relative to baseline (handles mid-gesture transitions)
        let effectiveScale = scale / zoomScaleBaseline

        // Create transform at start state, then scale from anchor
        let startTransform = Transform(
            scale: zoomStartScale,
            offset: zoomStartOffset,
            configuration: configuration.transform
        )

        var scaledTransform = startTransform.scaled(
            by: effectiveScale,
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

        // Track gesture intent: accumulate pan distance
        let currentLocation = CGPoint(x: anchor.x + panDelta.x, y: anchor.y + panDelta.y)
        if zoomPanLastLocation != .zero {
            let dx = currentLocation.x - zoomPanLastLocation.x
            let dy = currentLocation.y - zoomPanLastLocation.y
            zoomPanTotalPanDistance += hypot(dx, dy)
        }
        zoomPanLastLocation = currentLocation

        // Compute effective scale relative to baseline (handles mid-gesture transitions)
        let effectiveScale = scale / zoomScaleBaseline

        // Create transform at start state
        let startTransform = Transform(
            scale: zoomStartScale,
            offset: zoomStartOffset,
            configuration: configuration.transform
        )

        // Apply zoom at the fixed anchor point
        let scaledTransform = startTransform.scaled(
            by: effectiveScale,
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
        inputMode = .idle

        // When reduce motion is enabled, clamp to bounds instantly
        if configuration.reduceMotion {
            if let bounds = configuration.contentBounds {
                let effectiveBounds = effectivePanBounds(for: bounds, center: center)
                let clampedOffset = effectiveBounds.clamp(transform.offset)
                if clampedOffset != transform.offset {
                    setTransform(transform.withOffset(clampedOffset))
                }
            }
            setState(.idle)
            return
        }

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

    /// Called when a combined zoom+pan gesture ends.
    ///
    /// Starts momentum animation if velocity exceeds threshold and gesture
    /// was sufficiently "pan-like". Pure zoom gestures get no momentum.
    /// When reduceMotion is enabled, stops immediately and clamps to bounds.
    ///
    /// - Parameters:
    ///   - velocity: Pan velocity at release (calculated from position history)
    ///   - center: Canvas center point
    public func zoomPanEnded(velocity: CGPoint, center: CGPoint) {
        inputMode = .idle

        // When reduce motion is enabled, skip momentum entirely
        if configuration.reduceMotion {
            // Clamp to bounds if needed (instant, no bounce)
            if let bounds = configuration.contentBounds {
                let effectiveBounds = effectivePanBounds(for: bounds, center: center)
                let clampedOffset = effectiveBounds.clamp(transform.offset)
                if clampedOffset != transform.offset {
                    setTransform(transform.withOffset(clampedOffset))
                }
            }
            setState(.idle)
            return
        }

        // Compute gesture intent: how much was this a pan vs a zoom?
        let intentConfig = configuration.physics.gestureIntent
        let scaleDelta = abs(transform.scale - zoomPanStartScale)
        let panMagnitude = zoomPanTotalPanDistance / intentConfig.panToScaleEquivalence
        let totalMagnitude = scaleDelta + panMagnitude

        // panIntent: 0.0 = pure zoom, 1.0 = pure pan
        let panIntent = totalMagnitude > 0 ? panMagnitude / totalMagnitude : 0

        // Scale velocity by pan intent (zoom-dominant gestures get reduced momentum)
        let effectiveVelocity: CGPoint
        if panIntent < intentConfig.minimumPanIntent {
            // Below threshold: no momentum (pure zoom)
            effectiveVelocity = .zero
        } else {
            // Scale velocity by intent
            effectiveVelocity = CGPoint(
                x: velocity.x * panIntent,
                y: velocity.y * panIntent
            )
        }

        let speed = Physics.speed(effectiveVelocity)

        if speed > configuration.minimumMomentumVelocity {
            startMomentum(velocity: effectiveVelocity, center: center)
        } else if let bounds = configuration.contentBounds {
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
        inputMode = .idle
        setState(.idle)
    }

    // MARK: - Gesture Transitions

    /// Smoothly transitions from a zoom gesture to a pan gesture.
    ///
    /// Call this when a two-finger pinch becomes a one-finger drag (e.g., user
    /// lifts one finger). This captures the current translation as a baseline
    /// so subsequent `panChanged` calls produce smooth, continuous movement.
    ///
    /// - Parameter currentTranslation: The gesture's current cumulative translation
    ///   at the moment of transition
    public func transitionFromZoomToPan(currentTranslation: CGPoint) {
        momentumAnimator.stop()
        dragStartOffset = transform.offset
        dragTranslationBaseline = currentTranslation
        setState(.dragging)
    }

    /// Smoothly transitions from a pan gesture to a zoom gesture.
    ///
    /// Call this when a one-finger drag becomes a two-finger pinch (e.g., user
    /// adds a second finger). This captures the current scale and offset so
    /// subsequent `zoomChanged` calls produce smooth, continuous movement.
    ///
    /// - Parameters:
    ///   - currentScale: The gesture's current cumulative scale at transition
    ///   - center: Canvas center point
    public func transitionFromPanToZoom(
        currentScale: CGFloat,
        center: CGPoint
    ) {
        momentumAnimator.stop()
        // Capture current state as the starting point
        zoomStartScale = transform.scale
        zoomStartOffset = transform.offset
        // Set baseline so effectiveScale = scale / baseline starts at 1.0
        zoomScaleBaseline = currentScale
        inputMode = .zooming
        setState(.zooming)
    }

    // MARK: - Velocity Tracking

    /// The current smoothed velocity from tracking.
    ///
    /// Use this value when ending a gesture to get momentum velocity.
    /// Returns zero if tracking data is stale (older than `maxReleaseAge`).
    public var trackedVelocity: CGPoint {
        let config = configuration.physics.velocityTracker
        let timeSinceLastSample = CACurrentMediaTime() - velocityLastTime
        return timeSinceLastSample < config.maxReleaseAge ? velocitySmoothed : .zero
    }

    /// Tracks a position sample for velocity calculation.
    ///
    /// Call this during gesture `.changed` events to accumulate velocity samples.
    /// Uses exponential smoothing to filter noise from high-frequency samples.
    ///
    /// - Parameter location: Current gesture location in viewport space
    public func trackVelocity(at location: CGPoint) {
        let config = configuration.physics.velocityTracker
        let currentTime = CACurrentMediaTime()
        let dt = currentTime - velocityLastTime

        // Only calculate velocity if we have a previous sample and it's recent enough
        if velocityLastTime > 0 && dt > 0 && dt < config.maxSampleAge {
            var instantVelocity = CGPoint(
                x: (location.x - velocityLastLocation.x) / dt,
                y: (location.y - velocityLastLocation.y) / dt
            )

            // Clamp instant velocity to prevent extreme values
            let speed = Physics.speed(instantVelocity)
            if speed > config.maxVelocity {
                let scale = config.maxVelocity / speed
                instantVelocity.x *= scale
                instantVelocity.y *= scale
            }

            // For first sample, use it directly instead of smoothing against zero
            // This ensures quick gestures get accurate velocity
            if velocitySmoothed == .zero {
                velocitySmoothed = instantVelocity
            } else {
                // Exponential moving average for subsequent samples
                velocitySmoothed = CGPoint(
                    x: config.smoothingFactor * instantVelocity.x + (1 - config.smoothingFactor) * velocitySmoothed.x,
                    y: config.smoothingFactor * instantVelocity.y + (1 - config.smoothingFactor) * velocitySmoothed.y
                )
            }
        }

        velocityLastLocation = location
        velocityLastTime = currentTime
    }

    /// Resets velocity tracking state.
    ///
    /// Call this at the start of a new gesture to clear stale data.
    public func resetVelocityTracking() {
        velocitySmoothed = .zero
        velocityLastLocation = .zero
        velocityLastTime = 0
    }

    /// Notifies that the touch count changed during a gesture.
    ///
    /// When touch count changes (e.g., 2→1 or 1→2), the gesture center point
    /// jumps discontinuously. This method updates the tracking baseline without
    /// calculating velocity across the discontinuity, preserving the last good
    /// velocity for momentum on release.
    ///
    /// - Parameter location: Current gesture location after the touch count change
    public func notifyTouchCountChanged(at location: CGPoint) {
        // Update baseline location/time but preserve the smoothed velocity
        // This prevents calculating invalid velocity across the center jump
        velocityLastLocation = location
        velocityLastTime = CACurrentMediaTime()
        // Note: We intentionally do NOT reset velocitySmoothed here
    }

    // MARK: - Single-Finger Pan During Zoom

    /// Begins single-finger panning while maintaining zoom state.
    ///
    /// Call this when transitioning from two-finger pinch to one-finger drag
    /// (e.g., user lifts one finger during a pinch gesture). This captures the
    /// current location as an anchor point and preserves the current offset
    /// for relative calculations.
    ///
    /// - Parameter location: The gesture location when transition occurred
    public func beginSingleFingerPanDuringZoom(at location: CGPoint) {
        singleFingerPanAnchor = location
        singleFingerPanStartOffset = transform.offset
        inputMode = .singleFingerInZoom
    }

    /// Updates single-finger pan position during zoom.
    ///
    /// Call this during gesture `.changed` events when only one finger is down
    /// but the gesture started as a pinch. The offset is updated relative to
    /// the anchor captured in `beginSingleFingerPanDuringZoom`.
    ///
    /// - Parameter location: Current gesture location
    public func updateSingleFingerPanDuringZoom(to location: CGPoint) {
        let panDelta = CGPoint(
            x: location.x - singleFingerPanAnchor.x,
            y: location.y - singleFingerPanAnchor.y
        )
        let newOffset = CGPoint(
            x: singleFingerPanStartOffset.x + panDelta.x,
            y: singleFingerPanStartOffset.y + panDelta.y
        )
        setTransform(transform.withOffset(newOffset))
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

        // Handle spring animation to target transform
        if state == .animatingToTarget {
            return updateSpringAnimation()
        }

        // Handle momentum/bounce animation
        let stillActive = momentumAnimator.update()
        let newOffset = momentumAnimator.position

        setTransform(transform.withOffset(newOffset))

        if !stillActive {
            setState(.idle)
        }

        return stillActive
    }

    /// Updates spring animation toward target transform.
    private func updateSpringAnimation() -> Bool {
        let currentTime = CACurrentMediaTime()
        let rawDelta = currentTime - springLastUpdateTime
        let deltaTime = CGFloat(min(rawDelta, 1.0 / 30.0))
        springLastUpdateTime = currentTime

        let stiffness: CGFloat = 300
        let damping: CGFloat = 25

        // Animate scale
        let scaleDisplacement = transform.scale - springTargetScale
        let scaleForce = Physics.springForce(
            displacement: scaleDisplacement,
            velocity: springScaleVelocity,
            stiffness: stiffness,
            damping: damping
        )
        springScaleVelocity += scaleForce * deltaTime
        let newScale = transform.scale + springScaleVelocity * deltaTime

        // Animate offset
        let offsetDisplacement = CGPoint(
            x: transform.offset.x - springTargetOffset.x,
            y: transform.offset.y - springTargetOffset.y
        )
        let offsetForce = Physics.springForce(
            displacement: offsetDisplacement,
            velocity: springOffsetVelocity,
            stiffness: stiffness,
            damping: damping
        )
        springOffsetVelocity = CGPoint(
            x: springOffsetVelocity.x + offsetForce.x * deltaTime,
            y: springOffsetVelocity.y + offsetForce.y * deltaTime
        )
        let newOffset = CGPoint(
            x: transform.offset.x + springOffsetVelocity.x * deltaTime,
            y: transform.offset.y + springOffsetVelocity.y * deltaTime
        )

        // Apply new transform
        let newTransform = Transform(
            scale: newScale,
            offset: newOffset,
            configuration: configuration.transform
        )
        setTransform(newTransform)

        // Check if animation is complete
        let scaleSettled = abs(scaleDisplacement) < 0.001 && abs(springScaleVelocity) < 0.01
        let offsetSettled = Physics.speed(offsetDisplacement) < 0.5 && Physics.speed(springOffsetVelocity) < 1

        if scaleSettled && offsetSettled {
            // Snap to exact target
            setTransform(Transform(
                scale: springTargetScale,
                offset: springTargetOffset,
                configuration: configuration.transform
            ))
            setState(.idle)
            return false
        }

        return true
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
        inputMode = .idle
        setState(.idle)
    }

    /// Animates to identity transform with spring physics.
    public func animatedReset() {
        animateToTransform(scale: 1.0, offset: .zero)
    }

    /// Animates to a target transform using spring physics.
    ///
    /// Use this for programmatic zoom changes like double-tap to zoom.
    /// The animation uses spring physics for a natural feel.
    /// When reduceMotion is enabled, snaps instantly to target.
    ///
    /// - Parameters:
    ///   - scale: Target scale
    ///   - offset: Target offset
    public func animateToTransform(scale: CGFloat, offset: CGPoint) {
        momentumAnimator.stop()

        // When reduce motion is enabled, snap instantly to target
        if configuration.reduceMotion {
            let newTransform = Transform(
                scale: scale,
                offset: offset,
                configuration: configuration.transform
            )
            setTransform(newTransform)
            inputMode = .idle
            setState(.idle)
            return
        }

        springTargetScale = scale
        springTargetOffset = offset
        springScaleVelocity = 0
        springOffsetVelocity = .zero
        springLastUpdateTime = CACurrentMediaTime()

        inputMode = .idle
        setState(.animatingToTarget)
    }

    /// Animates zoom to a target scale at a specific anchor point.
    ///
    /// The offset is calculated to keep the anchor point stationary during zoom.
    ///
    /// - Parameters:
    ///   - scale: Target scale
    ///   - anchor: Point in viewport space that should remain stationary
    ///   - center: Canvas center point
    public func animateToScale(_ scale: CGFloat, anchor: CGPoint, center: CGPoint) {
        // Calculate the offset needed to keep anchor stationary at target scale
        let currentScale = transform.scale
        let currentOffset = transform.offset

        // Convert anchor to content space at current transform
        let anchorInContent = CGPoint(
            x: (anchor.x - center.x - currentOffset.x) / currentScale + center.x,
            y: (anchor.y - center.y - currentOffset.y) / currentScale + center.y
        )

        // Calculate where anchor would be at new scale (with same offset)
        let anchorAtNewScale = CGPoint(
            x: (anchorInContent.x - center.x) * scale + center.x + currentOffset.x,
            y: (anchorInContent.y - center.y) * scale + center.y + currentOffset.y
        )

        // Offset needed to bring anchor back to original position
        let targetOffset = CGPoint(
            x: currentOffset.x + (anchor.x - anchorAtNewScale.x),
            y: currentOffset.y + (anchor.y - anchorAtNewScale.y)
        )

        animateToTransform(scale: scale, offset: targetOffset)
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

    /// Sets the transform offset without changing gesture state.
    ///
    /// Use during mid-gesture transitions, such as single-finger panning
    /// within an active pinch gesture. This preserves the current gesture
    /// state (e.g., `.zooming`) so subsequent gesture calls work correctly.
    ///
    /// - Parameter offset: The new offset to apply
    public func setOffsetDuringGesture(_ offset: CGPoint) {
        setTransform(transform.withOffset(offset))
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

    // MARK: - Touch Classification

    /// Classifies a touch as tap or drag based on movement distance.
    ///
    /// Use this at the end of a touch sequence to determine intent.
    /// The touch still responds immediately; this determines retroactively
    /// whether the movement was intentional dragging or incidental.
    ///
    /// - Parameters:
    ///   - startPoint: Where the touch began
    ///   - endPoint: Where the touch ended
    /// - Returns: `.tap` if movement was within threshold, `.drag` otherwise
    public func classifyTouch(from startPoint: CGPoint, to endPoint: CGPoint) -> TouchClassification {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let distance = hypot(dx, dy)
        let threshold = configuration.touchClassification.tapMovementThreshold
        return distance < threshold ? .tap : .drag
    }

    // MARK: - Coordinate Conversion

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
