//
//  AngularVelocityTracker.swift
//  Mercurial
//
//  Smoothed angular velocity from a stream of angle samples. The 1-D analog of
//  GestureCoordinator's built-in velocity tracking: SwiftUI's RotationGesture
//  reports an angle but no velocity, so any rotatable free body needs this to
//  flick. Sampled during the gesture; read once at release.
//

import CoreGraphics
import QuartzCore

public final class AngularVelocityTracker: @unchecked Sendable {
    public var configuration: VelocityTrackerConfiguration

    private var lastAngle: CGFloat = 0
    private var lastTime: CFTimeInterval = -1
    private var smoothed: CGFloat = 0

    public init(configuration: VelocityTrackerConfiguration = .default) {
        self.configuration = configuration
    }

    /// Record an angle sample. `time` is injectable for deterministic tests.
    public func record(angle: CGFloat, at time: CFTimeInterval = CACurrentMediaTime()) {
        let dt = time - lastTime
        if lastTime >= 0 && dt > 0 && dt < configuration.maxSampleAge {
            var instant = (angle - lastAngle) / CGFloat(dt)
            // Reuse the linear clamp (rad/s vs pt/s, but the ceiling is high enough
            // to be effectively a sanity bound, not a feel limiter).
            if abs(instant) > configuration.maxVelocity {
                instant = instant > 0 ? configuration.maxVelocity : -configuration.maxVelocity
            }
            smoothed = (smoothed == 0)
                ? instant
                : configuration.smoothingFactor * instant + (1 - configuration.smoothingFactor) * smoothed
        }
        lastAngle = angle
        lastTime = time
    }

    /// Smoothed angular velocity (rad/s), or 0 if the last sample is stale.
    public func velocity(asOf time: CFTimeInterval = CACurrentMediaTime()) -> CGFloat {
        (time - lastTime) < configuration.maxReleaseAge ? smoothed : 0
    }

    public func reset() {
        lastAngle = 0
        lastTime = -1
        smoothed = 0
    }
}
