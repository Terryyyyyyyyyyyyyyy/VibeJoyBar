import SwiftUI
import AppKit

enum TactilePhysics {
    // MARK: - Spring Animation Constants
    static let appleSpring = Animation.spring(response: 0.22, dampingFraction: 0.52)
    static let hoverSpring = Animation.spring(response: 0.28, dampingFraction: 0.65)

    // MARK: - Stick Geometry Dimensions
    static let maxStickDeflection: CGFloat = 14.0
    static let maxStickTiltDegrees: Double = 18.0

    // MARK: - Physics & Deflection Helpers
    static func clampDeflection(offset: CGSize, maxRadius: CGFloat = maxStickDeflection) -> CGSize {
        let distance = hypot(offset.width, offset.height)
        if distance <= maxRadius || distance == 0 || maxRadius <= 0 {
            return offset
        }
        let ratio = maxRadius / distance
        return CGSize(width: offset.width * ratio, height: offset.height * ratio)
    }

    static func calculateTilt(
        offset: CGSize,
        maxRadius: CGFloat = maxStickDeflection,
        maxTilt: Double = maxStickTiltDegrees
    ) -> (pitch: Double, roll: Double) {
        let effectiveRadius = max(1.0, maxRadius)
        let rawPitch = Double(-offset.height / effectiveRadius) * maxTilt
        let rawRoll = Double(offset.width / effectiveRadius) * maxTilt
        let pitch = min(max(rawPitch, -maxTilt), maxTilt)
        let roll = min(max(rawRoll, -maxTilt), maxTilt)
        return (pitch: pitch, roll: roll)
    }

    static func dynamicSocketShadowOffset(deflection: CGSize) -> CGSize {
        CGSize(width: -deflection.width * 0.45, height: -deflection.height * 0.45)
    }

    static func directionForOffset(_ offset: CGSize, deadzone: CGFloat = 5.0) -> String? {
        let distance = hypot(offset.width, offset.height)
        guard distance >= deadzone else { return nil }
        if abs(offset.width) > abs(offset.height) {
            return offset.width > 0 ? "right" : "left"
        } else {
            return offset.height > 0 ? "down" : "up"
        }
    }

    static func offsetForDirection(_ direction: String, distance: CGFloat = 12.0) -> CGSize {
        switch direction.lowercased() {
        case "up":
            return CGSize(width: 0, height: -distance)
        case "down":
            return CGSize(width: 0, height: distance)
        case "left":
            return CGSize(width: -distance, height: 0)
        case "right":
            return CGSize(width: distance, height: 0)
        default:
            return .zero
        }
    }
}

// MARK: - Tactile Button Styles
struct TactileHotspotButtonBody: View {
    let configuration: ButtonStyle.Configuration
    var isEmphasized: Bool
    var travel: CGFloat = 4.2
    var depressedScale: CGFloat = 0.90
    var emphasizedScale: CGFloat = 1.05

    @State private var isVisiblyPressed: Bool = false
    @State private var pressStartTime: Date? = nil

    var body: some View {
        configuration.label
            .offset(y: isVisiblyPressed ? travel : 0)
            .scaleEffect(isVisiblyPressed ? depressedScale : (isEmphasized ? emphasizedScale : 1.0))
            .brightness(isVisiblyPressed ? -0.10 : 0)
            .shadow(
                color: isEmphasized
                    ? Color.accentColor.opacity(isVisiblyPressed ? 0.25 : 0.65)
                    : Color.black.opacity(isVisiblyPressed ? 0.20 : 0.50),
                radius: isVisiblyPressed ? 1.5 : (isEmphasized ? 6 : 4),
                x: 0,
                y: isVisiblyPressed ? 0.5 : (isEmphasized ? 2.5 : 3.0)
            )
            .animation(TactilePhysics.appleSpring, value: isVisiblyPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    isVisiblyPressed = true
                    pressStartTime = Date()
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                } else {
                    let elapsed = Date().timeIntervalSince(pressStartTime ?? Date())
                    let minDuration: TimeInterval = 0.12
                    if elapsed < minDuration {
                        DispatchQueue.main.asyncAfter(deadline: .now() + (minDuration - elapsed)) {
                            withAnimation(TactilePhysics.appleSpring) {
                                isVisiblyPressed = false
                            }
                        }
                    } else {
                        withAnimation(TactilePhysics.appleSpring) {
                            isVisiblyPressed = false
                        }
                    }
                }
            }
    }
}

struct TactileHotspotButtonStyle: ButtonStyle {
    var isEmphasized: Bool = false
    var travel: CGFloat = 4.2
    var depressedScale: CGFloat = 0.90
    var emphasizedScale: CGFloat = 1.05

    func makeBody(configuration: Configuration) -> some View {
        TactileHotspotButtonBody(
            configuration: configuration,
            isEmphasized: isEmphasized,
            travel: travel,
            depressedScale: depressedScale,
            emphasizedScale: emphasizedScale
        )
    }
}

struct TactileCapsuleButtonBody: View {
    let configuration: ButtonStyle.Configuration
    var isEmphasized: Bool
    var travel: CGFloat = 3.5
    var depressedScale: CGFloat = 0.92

    @State private var isVisiblyPressed: Bool = false
    @State private var pressStartTime: Date? = nil

    var body: some View {
        configuration.label
            .offset(y: isVisiblyPressed ? travel : 0)
            .scaleEffect(isVisiblyPressed ? depressedScale : (isEmphasized ? 1.04 : 1.0))
            .brightness(isVisiblyPressed ? -0.08 : 0)
            .shadow(
                color: isEmphasized
                    ? Color.accentColor.opacity(isVisiblyPressed ? 0.20 : 0.45)
                    : Color.black.opacity(isVisiblyPressed ? 0.10 : 0.25),
                radius: isVisiblyPressed ? 1.5 : (isEmphasized ? 4 : 2),
                x: 0,
                y: isVisiblyPressed ? 0.5 : 1.5
            )
            .animation(TactilePhysics.appleSpring, value: isVisiblyPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    isVisiblyPressed = true
                    pressStartTime = Date()
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                } else {
                    let elapsed = Date().timeIntervalSince(pressStartTime ?? Date())
                    let minDuration: TimeInterval = 0.12
                    if elapsed < minDuration {
                        DispatchQueue.main.asyncAfter(deadline: .now() + (minDuration - elapsed)) {
                            withAnimation(TactilePhysics.appleSpring) {
                                isVisiblyPressed = false
                            }
                        }
                    } else {
                        withAnimation(TactilePhysics.appleSpring) {
                            isVisiblyPressed = false
                        }
                    }
                }
            }
    }
}

struct TactileCapsuleButtonStyle: ButtonStyle {
    var isEmphasized: Bool = false
    var travel: CGFloat = 3.5
    var depressedScale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        TactileCapsuleButtonBody(
            configuration: configuration,
            isEmphasized: isEmphasized,
            travel: travel,
            depressedScale: depressedScale
        )
    }
}
