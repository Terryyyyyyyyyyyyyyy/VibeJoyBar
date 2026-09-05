import XCTest
@testable import VibeJoyBar

final class TactilePhysicsTests: XCTestCase {

    // MARK: - Deflection Clamping
    func testClampingWithinRadius() {
        let inside = CGSize(width: 5, height: 5)
        let clamped = TactilePhysics.clampDeflection(offset: inside)
        XCTAssertEqual(clamped.width, 5.0, accuracy: 0.001)
        XCTAssertEqual(clamped.height, 5.0, accuracy: 0.001)

        let zero = CGSize.zero
        let clampedZero = TactilePhysics.clampDeflection(offset: zero)
        XCTAssertEqual(clampedZero, .zero)
    }

    func testClampingBeyondRadius() {
        let maxRadius: CGFloat = 14.0
        // Straight downward deflection beyond maxRadius
        let downward = CGSize(width: 0, height: 28)
        let clampedDown = TactilePhysics.clampDeflection(offset: downward, maxRadius: maxRadius)
        XCTAssertEqual(clampedDown.width, 0.0, accuracy: 0.001)
        XCTAssertEqual(clampedDown.height, 14.0, accuracy: 0.001)

        // 3-4-5 proportional diagonal deflection (30, 40 -> hypotenuse 50)
        let diagonal = CGSize(width: 30, height: 40)
        let clampedDiag = TactilePhysics.clampDeflection(offset: diagonal, maxRadius: maxRadius)
        let resultingHypot = hypot(clampedDiag.width, clampedDiag.height)
        XCTAssertEqual(resultingHypot, 14.0, accuracy: 0.001)
        XCTAssertEqual(clampedDiag.width, 30.0 * (14.0 / 50.0), accuracy: 0.001)
        XCTAssertEqual(clampedDiag.height, 40.0 * (14.0 / 50.0), accuracy: 0.001)
    }

    // MARK: - 3D Perspective Tilt Calculation
    func testCalculateTiltZero() {
        let tilt = TactilePhysics.calculateTilt(offset: .zero)
        XCTAssertEqual(tilt.pitch, 0.0, accuracy: 0.001)
        XCTAssertEqual(tilt.roll, 0.0, accuracy: 0.001)
    }

    func testCalculateTiltDirections() {
        let maxRadius: CGFloat = 14.0
        let maxTilt: Double = 18.0

        // Pushed UP: offset.height < 0 -> positive pitch (tilts back)
        let up = CGSize(width: 0, height: -14)
        let tiltUp = TactilePhysics.calculateTilt(offset: up, maxRadius: maxRadius, maxTilt: maxTilt)
        XCTAssertEqual(tiltUp.pitch, 18.0, accuracy: 0.001)
        XCTAssertEqual(tiltUp.roll, 0.0, accuracy: 0.001)

        // Pushed DOWN: offset.height > 0 -> negative pitch (tilts forward)
        let down = CGSize(width: 0, height: 14)
        let tiltDown = TactilePhysics.calculateTilt(offset: down, maxRadius: maxRadius, maxTilt: maxTilt)
        XCTAssertEqual(tiltDown.pitch, -18.0, accuracy: 0.001)
        XCTAssertEqual(tiltDown.roll, 0.0, accuracy: 0.001)

        // Pushed RIGHT: offset.width > 0 -> positive roll
        let right = CGSize(width: 14, height: 0)
        let tiltRight = TactilePhysics.calculateTilt(offset: right, maxRadius: maxRadius, maxTilt: maxTilt)
        XCTAssertEqual(tiltRight.pitch, 0.0, accuracy: 0.001)
        XCTAssertEqual(tiltRight.roll, 18.0, accuracy: 0.001)

        // Pushed LEFT: offset.width < 0 -> negative roll
        let left = CGSize(width: -14, height: 0)
        let tiltLeft = TactilePhysics.calculateTilt(offset: left, maxRadius: maxRadius, maxTilt: maxTilt)
        XCTAssertEqual(tiltLeft.pitch, 0.0, accuracy: 0.001)
        XCTAssertEqual(tiltLeft.roll, -18.0, accuracy: 0.001)
    }

    func testCalculateTiltBoundsClamping() {
        let extreme = CGSize(width: 200, height: -300)
        let tilt = TactilePhysics.calculateTilt(offset: extreme, maxRadius: 14.0, maxTilt: 18.0)
        XCTAssertEqual(tilt.pitch, 18.0, accuracy: 0.001)
        XCTAssertEqual(tilt.roll, 18.0, accuracy: 0.001)

        let extremeNegative = CGSize(width: -200, height: 300)
        let tiltNeg = TactilePhysics.calculateTilt(offset: extremeNegative, maxRadius: 14.0, maxTilt: 18.0)
        XCTAssertEqual(tiltNeg.pitch, -18.0, accuracy: 0.001)
        XCTAssertEqual(tiltNeg.roll, -18.0, accuracy: 0.001)
    }

    // MARK: - Dynamic Socket Shadow Offset
    func testDynamicSocketShadowOffset() {
        let zero = TactilePhysics.dynamicSocketShadowOffset(deflection: .zero)
        XCTAssertEqual(zero, .zero)

        let deflection = CGSize(width: 10, height: -20)
        let shadow = TactilePhysics.dynamicSocketShadowOffset(deflection: deflection)
        XCTAssertEqual(shadow.width, -4.5, accuracy: 0.001)
        XCTAssertEqual(shadow.height, 9.0, accuracy: 0.001)
    }

    // MARK: - Direction For Offset
    func testDirectionForOffsetDeadzone() {
        // Below deadzone 5.0
        XCTAssertNil(TactilePhysics.directionForOffset(.zero))
        XCTAssertNil(TactilePhysics.directionForOffset(CGSize(width: 2, height: 2)))
        XCTAssertNil(TactilePhysics.directionForOffset(CGSize(width: 0, height: 4.9)))
    }

    func testDirectionForOffsetCardinals() {
        XCTAssertEqual(TactilePhysics.directionForOffset(CGSize(width: 0, height: -10)), "up")
        XCTAssertEqual(TactilePhysics.directionForOffset(CGSize(width: 0, height: 10)), "down")
        XCTAssertEqual(TactilePhysics.directionForOffset(CGSize(width: -10, height: 0)), "left")
        XCTAssertEqual(TactilePhysics.directionForOffset(CGSize(width: 10, height: 0)), "right")
    }

    func testDirectionForOffsetDominantAxis() {
        // Horizontal dominance
        XCTAssertEqual(TactilePhysics.directionForOffset(CGSize(width: 12, height: 4)), "right")
        XCTAssertEqual(TactilePhysics.directionForOffset(CGSize(width: -12, height: -4)), "left")

        // Vertical dominance
        XCTAssertEqual(TactilePhysics.directionForOffset(CGSize(width: 4, height: -12)), "up")
        XCTAssertEqual(TactilePhysics.directionForOffset(CGSize(width: -4, height: 12)), "down")
    }

    // MARK: - Offset For Direction
    func testOffsetForDirection() {
        XCTAssertEqual(TactilePhysics.offsetForDirection("up"), CGSize(width: 0, height: -12))
        XCTAssertEqual(TactilePhysics.offsetForDirection("down"), CGSize(width: 0, height: 12))
        XCTAssertEqual(TactilePhysics.offsetForDirection("left"), CGSize(width: -12, height: 0))
        XCTAssertEqual(TactilePhysics.offsetForDirection("right"), CGSize(width: 12, height: 0))

        // Case insensitivity
        XCTAssertEqual(TactilePhysics.offsetForDirection("UP"), CGSize(width: 0, height: -12))
        XCTAssertEqual(TactilePhysics.offsetForDirection("Right"), CGSize(width: 12, height: 0))

        // Custom distance
        XCTAssertEqual(TactilePhysics.offsetForDirection("up", distance: 20), CGSize(width: 0, height: -20))

        // Unknown direction
        XCTAssertEqual(TactilePhysics.offsetForDirection("unknown"), .zero)
    }
}
