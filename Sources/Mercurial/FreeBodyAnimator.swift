//
//  FreeBodyAnimator.swift
//  Mercurial
//
//  A free body with momentum: a Pose (position + rotation) carrying linear and
//  angular velocity, coasting to rest. The rotational cousin of Momentum2DAnimator
//  — same shape, plus an angular channel. Reuses Physics / PhysicsBounds wholesale;
//  the viewport Transform/GestureCoordinator stack is untouched.
//
//  EVOLUTION (the "C" door): a future `FreeBodySimulation` — id-keyed, multi-body,
//  stepping all bodies in one update(), the home for inter-card collision/jostling —
//  is reached by having that simulation OWN a collection of these animators, not by
//  replacing them. This primitive is forward-compatible with that by construction.
//
//  REVIVAL: `init(initialPose:)` is also the save/restore entry point — a body born
//  there is `.idle` with zero velocity and never replays physics, so a saved spread
//  is restored verbatim (the angular detent only fires inside update(), after a flick).
//

import CoreGraphics
import QuartzCore

public final class FreeBodyAnimator: @unchecked Sendable {
    // MARK: - State

    public private(set) var pose: Pose
    public private(set) var linearVelocity: CGPoint = .zero   // pt/s
    public private(set) var angularVelocity: CGFloat = 0      // rad/s
    public private(set) var state: MomentumState = .idle
    public var isActive: Bool { state != .idle }

    // MARK: - Configuration

    public var configuration: PhysicsConfiguration
    /// Position walls (nil ⇒ unbounded). Card stays on the cloth when set.
    public var bounds: PhysicsBounds?
    /// How rotation comes to rest. Defaults to `.free`.
    public var angularSettle: AngularSettleConfiguration = .free
    /// When true, `start` skips inertia and settles instantly (accessibility).
    public var reduceMotion: Bool = false

    // MARK: - Private

    private var lastUpdateTime: CFTimeInterval = 0

    // MARK: - Init

    public init(configuration: PhysicsConfiguration = .default, initialPose: Pose = .identity) {
        self.configuration = configuration
        self.pose = initialPose
    }

    // MARK: - Control

    /// Set the pose directly during a live drag (no physics).
    public func setPose(_ pose: Pose) { self.pose = pose }

    /// Hand off both velocities; physics takes over until both channels rest.
    public func start(linearVelocity: CGPoint, angularVelocity: CGFloat) {
        let fastEnoughLinear = Physics.speed(linearVelocity) > configuration.momentum.minimumVelocity
        let fastEnoughAngular = abs(angularVelocity) > angularSettle.engageBelow

        guard fastEnoughLinear || fastEnoughAngular else {
            // Nothing worth animating; leave the pose where it was placed.
            self.linearVelocity = .zero
            self.angularVelocity = 0
            state = .idle
            return
        }

        self.linearVelocity = fastEnoughLinear ? linearVelocity : .zero
        self.angularVelocity = fastEnoughAngular ? angularVelocity : 0
        self.lastUpdateTime = CACurrentMediaTime()
        state = .momentum
    }

    /// Immediately stop (e.g. the user grabbed a settling card).
    public func stop() {
        linearVelocity = .zero
        angularVelocity = 0
        state = .idle
    }

    // MARK: - Frame loop

    /// Drive one frame from the wall clock. Call from a TimelineView / display link.
    @discardableResult
    public func update() -> Bool {
        guard state != .idle else { return false }
        let now = CACurrentMediaTime()
        let dt = CGFloat(now - lastUpdateTime)
        lastUpdateTime = now
        return step(deltaTime: dt)
    }

    /// Deterministic one-frame integration (testability seam; `update` delegates here).
    /// Channels land in A6 (linear) and A7 (angular); stub for now.
    @discardableResult
    internal func step(deltaTime: CGFloat) -> Bool {
        guard state != .idle else { return false }
        state = .idle
        return false
    }
}
