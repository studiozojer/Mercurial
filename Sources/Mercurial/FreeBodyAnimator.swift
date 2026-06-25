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
import Foundation
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
        if reduceMotion {
            settleInstantly()
            return
        }
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

    /// Accessibility path: jump straight to the resting pose, no animation.
    private func settleInstantly() {
        if let bounds = bounds { pose.position = bounds.clamp(pose.position) }
        if let target = angularSettle.settleTarget(for: pose.rotation) {
            pose.rotation += Physics.shortestAngleDelta(from: pose.rotation, to: target)
        }
        linearVelocity = .zero
        angularVelocity = 0
        state = .idle
    }

    /// Per-frame decay factor for a coefficient defined per 60fps frame, scaled to `dt`.
    /// `decay(c, 1/60) == c`; frame-rate independent.
    private func decay(_ coeff: CGFloat, over dt: CGFloat) -> CGFloat {
        CGFloat(pow(Double(coeff), Double(dt * 60)))
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
    /// Drives integration only — it does NOT touch the wall clock (`lastUpdateTime`,
    /// owned by `start`/`update`). Drive a given instance with either `step` (fixed
    /// timestep) or `update` (wall clock), not both interleaved.
    @discardableResult
    public func step(deltaTime: CGFloat) -> Bool {
        guard state != .idle else { return false }
        let dt = min(deltaTime, configuration.momentum.maxDeltaTime)

        let linearActive = stepLinear(dt)
        let angularActive = stepAngular(dt)

        state = (linearActive || angularActive) ? .momentum : .idle
        return state != .idle
    }

    /// Linear momentum + boundary spring — mirrors Momentum2DAnimator's path,
    /// operating on `pose.position`. Returns whether the linear channel is still moving.
    private func stepLinear(_ dt: CGFloat) -> Bool {
        let displacement = bounds?.displacement(from: pose.position) ?? .zero
        let pastBoundary = Physics.speed(displacement) > 0.001

        if pastBoundary {
            let force = Physics.springForce(
                displacement: displacement,
                velocity: linearVelocity,
                stiffness: configuration.spring.stiffness,
                damping: configuration.spring.damping
            )
            linearVelocity = linearVelocity + force * dt
            pose.position = Physics.integrate(position: pose.position, velocity: linearVelocity, deltaTime: dt)
            let newDisplacement = bounds?.displacement(from: pose.position) ?? .zero
            if Physics.speed(newDisplacement) < 0.5 && Physics.speed(linearVelocity) < 1 {
                if let bounds = bounds { pose.position = bounds.clamp(pose.position) }
                linearVelocity = .zero
                return false
            }
            return true
        } else {
            pose.position = Physics.integrate(position: pose.position, velocity: linearVelocity, deltaTime: dt)
            linearVelocity = linearVelocity * decay(configuration.momentum.friction, over: dt)
            if Physics.speed(linearVelocity) < configuration.momentum.minimumVelocity {
                linearVelocity = .zero
                // Came to rest; if that rest is outside bounds, let the next frame spring it.
                let rest = bounds?.displacement(from: pose.position) ?? .zero
                return Physics.speed(rest) > 0.001
            }
            return true
        }
    }

    /// Angular momentum settle. Two phases: free spin while fast, then a spring toward
    /// the nearest detent once the spin drops under `engageBelow`. Returns whether the
    /// angular channel is still moving.
    private func stepAngular(_ dt: CGFloat) -> Bool {
        let spinning = abs(angularVelocity) > angularSettle.engageBelow
        let target = angularSettle.settleTarget(for: pose.rotation)

        if spinning || target == nil {
            // Free spin (and the only behavior when there is no detent).
            pose.rotation += angularVelocity * dt
            angularVelocity *= decay(angularSettle.friction, over: dt)
            if abs(angularVelocity) < 0.01 {
                angularVelocity = 0
                return false   // spin fully decayed → stop. With a detent + the default engageBelow,
                               // the spring already engaged above this floor and snapped; an engageBelow
                               // below ~0.01 would rest here unsnapped.
            }
            return true
        }

        // Detent ease: spring rotation toward the nearest target the short way.
        let delta = Physics.shortestAngleDelta(from: pose.rotation, to: target!)
        let force = Physics.springForce(
            displacement: -delta,                 // displacement from rest = -(rest - current)
            velocity: angularVelocity,
            stiffness: angularSettle.stiffness,
            damping: angularSettle.damping
        )
        angularVelocity += force * dt
        pose.rotation += angularVelocity * dt

        if abs(delta) < 0.001 && abs(angularVelocity) < 0.01 {
            pose.rotation += Physics.shortestAngleDelta(from: pose.rotation, to: target!)  // snap exact
            angularVelocity = 0
            return false
        }
        return true
    }
}
