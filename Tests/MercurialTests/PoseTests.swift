import XCTest
@testable import Mercurial

final class PoseTests: XCTestCase {
    func testDefaultRotationIsZero() {
        let p = Pose(position: CGPoint(x: 3, y: 4))
        XCTAssertEqual(p.rotation, 0)
    }
    func testIdentity() {
        XCTAssertEqual(Pose.identity, Pose(position: .zero, rotation: 0))
    }
    func testMovedAndRotatedAreImmutableUpdates() {
        let p = Pose(position: CGPoint(x: 1, y: 1), rotation: 0.5)
        XCTAssertEqual(p.moved(to: CGPoint(x: 9, y: 9)),
                       Pose(position: CGPoint(x: 9, y: 9), rotation: 0.5))
        XCTAssertEqual(p.rotated(to: 1.0),
                       Pose(position: CGPoint(x: 1, y: 1), rotation: 1.0))
    }
    func testHashableInSet() {
        let set: Set<Pose> = [Pose.identity, Pose.identity, Pose(position: CGPoint(x: 1, y: 0))]
        XCTAssertEqual(set.count, 2)
    }
    func testCodableRoundTrip() throws {
        let p = Pose(position: CGPoint(x: 12.5, y: -7), rotation: 1.25)
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Pose.self, from: data)
        XCTAssertEqual(decoded, p)
    }
}
