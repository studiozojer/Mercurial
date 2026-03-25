// Tests/MercurialTests/GraphAnimatorTests.swift

import XCTest
@testable import Mercurial

final class GraphAnimatorTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsEmpty() {
        let animator = GraphAnimator()
        XCTAssertTrue(animator.positions.isEmpty)
        XCTAssertFalse(animator.isAnimating)
    }

    // MARK: - Snap To Targets

    func testSnapToTargetsSetsPositionsImmediately() {
        let animator = GraphAnimator()
        let targets: [String: CGPoint] = [
            "A": CGPoint(x: 100, y: 100),
            "B": CGPoint(x: 200, y: 200),
        ]
        animator.snapToTargets(targets)

        XCTAssertEqual(Double(animator.positions["A"]!.x), 100, accuracy: 0.001)
        XCTAssertEqual(Double(animator.positions["B"]!.x), 200, accuracy: 0.001)
        XCTAssertFalse(animator.isAnimating)
    }

    // MARK: - Set Targets Starts Animation

    func testSetTargetsStartsAnimation() {
        let animator = GraphAnimator()
        animator.snapToTargets(["A": CGPoint(x: 0, y: 0)])

        animator.setTargets(["A": CGPoint(x: 100, y: 100)])
        XCTAssertTrue(animator.isAnimating)
    }

    func testSetTargetsWithSamePositionDoesNotAnimate() {
        let animator = GraphAnimator()
        let target: [String: CGPoint] = ["A": CGPoint(x: 100, y: 100)]
        animator.snapToTargets(target)

        animator.setTargets(target)
        XCTAssertFalse(animator.isAnimating)
    }

    // MARK: - Update Drives Toward Target

    func testUpdateMovesTowardTarget() {
        let animator = GraphAnimator(configuration: .default)
        animator.snapToTargets(["A": CGPoint(x: 0, y: 0)])
        animator.setTargets(["A": CGPoint(x: 100, y: 0)])

        // Run several frames
        for _ in 0..<60 {
            animator.update(deltaTime: 1.0 / 60.0)
        }

        let pos = animator.positions["A"]!
        XCTAssertGreaterThan(pos.x, 50, "Node should have moved toward target after 60 frames")
    }

    // MARK: - Settling

    func testAnimationSettles() {
        let animator = GraphAnimator(configuration: .snappy)
        animator.snapToTargets(["A": CGPoint(x: 0, y: 0)])
        animator.setTargets(["A": CGPoint(x: 100, y: 100)])

        // Run many frames
        for _ in 0..<300 {
            if !animator.isAnimating { break }
            animator.update(deltaTime: 1.0 / 60.0)
        }

        XCTAssertFalse(animator.isAnimating, "Animation should have settled")
        let pos = animator.positions["A"]!
        XCTAssertEqual(pos.x, 100, accuracy: 1)
        XCTAssertEqual(pos.y, 100, accuracy: 1)
    }

    // MARK: - New Nodes

    func testNewNodeAppearsAtCenter() {
        let animator = GraphAnimator()
        animator.snapToTargets(["A": CGPoint(x: 50, y: 50)])

        // B is new — not in current positions
        animator.setTargets([
            "A": CGPoint(x: 50, y: 50),
            "B": CGPoint(x: 200, y: 200),
        ])

        // B should exist in positions now
        XCTAssertNotNil(animator.positions["B"])
        XCTAssertTrue(animator.isAnimating)
    }

    // MARK: - Removed Nodes

    func testRemovedNodeDisappears() {
        let animator = GraphAnimator()
        animator.snapToTargets([
            "A": CGPoint(x: 50, y: 50),
            "B": CGPoint(x: 150, y: 150),
        ])

        // Remove B
        animator.setTargets(["A": CGPoint(x: 50, y: 50)])
        XCTAssertNil(animator.positions["B"])
    }
}
