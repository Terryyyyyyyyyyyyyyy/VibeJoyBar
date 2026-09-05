import SwiftUI
import AppKit

struct InteractiveJoyConStickView: View {
    let side: ActiveControllerSide
    @Binding var selection: MappingSelection?
    @Binding var hoveredSelection: MappingSelection?
    var onSelect: ((MappingSelection) -> Void)? = nil

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var isCenterPressed: Bool = false
    @State private var pulseScale: CGFloat = 0.6
    @State private var pulseOpacity: Double = 0.0

    // MARK: - Active Deflection & 3D Tilt
    private var activeDeflection: CGSize {
        if isDragging {
            return TactilePhysics.clampDeflection(offset: dragOffset)
        } else if case .stick(let dir) = hoveredSelection {
            return TactilePhysics.offsetForDirection(dir)
        } else if case .stick(let dir) = selection {
            return TactilePhysics.offsetForDirection(dir)
        } else {
            return .zero
        }
    }

    private var tilt: (pitch: Double, roll: Double) {
        TactilePhysics.calculateTilt(offset: activeDeflection)
    }

    private var isStickButtonSelected: Bool {
        selection == .button(side.stickButtonID)
    }

    private var isStickButtonHovered: Bool {
        hoveredSelection == .button(side.stickButtonID)
    }

    private var isStickActive: Bool {
        if isStickButtonSelected || isStickButtonHovered { return true }
        if case .stick = selection { return true }
        if case .stick = hoveredSelection { return true }
        return false
    }

    var body: some View {
        ZStack {
            // 1. Socket Base (球窝底座)
            socketBase

            // 2. Stick Click Pulse (同心光环微脉冲)
            pulseEffect

            // 3. Analog Stick Cap (3D 机械摇杆帽)
            stickCap

            // 4. Direction Arrow Hotspots (4 轴方向指示热区)
            directionButton("up", symbol: "arrow.up", x: 0, y: -38)
            directionButton("down", symbol: "arrow.down", x: 0, y: 38)
            directionButton("left", symbol: "arrow.left", x: -38, y: 0)
            directionButton("right", symbol: "arrow.right", x: 38, y: 0)
        }
        .frame(width: 100, height: 100)
    }

    // MARK: - Socket Base
    private var socketBase: some View {
        ZStack {
            // Recessed socket gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.16), Color(white: 0.08)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 38
                    )
                )
                .frame(width: 76, height: 76)

            // Dynamic socket inner shadow shifting opposite to deflection
            Circle()
                .stroke(Color.black.opacity(0.75), lineWidth: 4)
                .blur(radius: 2.5)
                .offset(TactilePhysics.dynamicSocketShadowOffset(deflection: activeDeflection))
                .clipShape(Circle().size(width: 76, height: 76))
                .frame(width: 76, height: 76)

            // Compass backdrop ring (accent glow when active)
            Circle()
                .stroke(
                    isStickActive
                        ? LinearGradient(
                            colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .frame(width: 76, height: 76)
        }
        .allowsHitTesting(false)
        .animation(TactilePhysics.hoverSpring, value: isStickActive)
    }

    // MARK: - Pulse Effect
    private var pulseEffect: some View {
        Circle()
            .stroke(Color.accentColor.opacity(pulseOpacity), lineWidth: 2)
            .frame(width: 52, height: 52)
            .scaleEffect(pulseScale)
            .allowsHitTesting(false)
    }

    // MARK: - Analog Stick Cap
    private var stickCap: some View {
        let isEmphasized = isStickButtonSelected || isStickButtonHovered

        return ZStack {
            // Outer rubber ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.26), Color(white: 0.18)],
                        center: .center,
                        startRadius: 10,
                        endRadius: 26
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Circle()
                        .stroke(
                            isEmphasized
                                ? Color.accentColor
                                : Color(white: 0.32),
                            lineWidth: isEmphasized ? 2 : 1
                        )
                )

            // 4 Tactile grip nubs at 12, 3, 6, 9 o'clock
            Group {
                // 12 o'clock
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.38))
                    .frame(width: 3, height: 5)
                    .offset(y: -21)
                // 6 o'clock
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.38))
                    .frame(width: 3, height: 5)
                    .offset(y: 21)
                // 9 o'clock
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.38))
                    .frame(width: 5, height: 3)
                    .offset(x: -21)
                // 3 o'clock
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.38))
                    .frame(width: 5, height: 3)
                    .offset(x: 21)
            }

            // Concave thumb depression
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.12), Color(white: 0.16)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 18
                    )
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(Color(white: 0.22), lineWidth: 1)
                )

            // Center tactile dot / accent indicator
            if isEmphasized {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 52, height: 52)
        .contentShape(Circle())
        // 3D Perspective Tilt
        .rotation3DEffect(.degrees(tilt.pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(tilt.roll), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        // 2D Deflection and mechanical press depression
        .offset(x: activeDeflection.width, y: activeDeflection.height + (isCenterPressed ? 3.8 : 0))
        .scaleEffect(isCenterPressed ? 0.90 : 1.0)
        .shadow(
            color: isEmphasized
                ? Color.accentColor.opacity(isCenterPressed ? 0.25 : 0.55)
                : Color.black.opacity(0.4),
            radius: isCenterPressed ? 1.5 : 5,
            x: activeDeflection.width * 0.2,
            y: (isCenterPressed ? 0.5 : 3.5) + activeDeflection.height * 0.2
        )
        .animation(TactilePhysics.appleSpring, value: activeDeflection)
        .animation(TactilePhysics.appleSpring, value: isCenterPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let translation = value.translation
                    let dist = hypot(translation.width, translation.height)
                    if dist > 3.0 {
                        isDragging = true
                        isCenterPressed = false
                        dragOffset = TactilePhysics.clampDeflection(offset: translation)
                        if let dir = TactilePhysics.directionForOffset(dragOffset) {
                            hoveredSelection = .stick(dir)
                        }
                    } else {
                        isCenterPressed = true
                    }
                }
                .onEnded { value in
                    let translation = value.translation
                    let dist = hypot(translation.width, translation.height)
                    if dist <= 3.0 {
                        triggerStickClick()
                    } else if let dir = TactilePhysics.directionForOffset(dragOffset) {
                        selection = .stick(dir)
                        onSelect?(.stick(dir))
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    withAnimation(TactilePhysics.appleSpring) {
                        dragOffset = .zero
                        isDragging = false
                        isCenterPressed = false
                        hoveredSelection = nil
                    }
                }
        )
        .onHover { isHovered in
            if isHovered {
                if hoveredSelection == nil {
                    hoveredSelection = .button(side.stickButtonID)
                }
            } else if hoveredSelection == .button(side.stickButtonID) {
                hoveredSelection = nil
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.stickLabel) 按压")
        .accessibilityHint("点击选择摇杆下压映射，或拖拽选择方向")
        .help("编辑 \(side.stickLabel) 映射")
    }

    // MARK: - Stick Center Click Action
    private func triggerStickClick() {
        selection = .button(side.stickButtonID)
        onSelect?(.button(side.stickButtonID))
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        isCenterPressed = true
        pulseScale = 0.6
        pulseOpacity = 0.85
        withAnimation(.easeOut(duration: 0.45)) {
            pulseScale = 1.6
            pulseOpacity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(TactilePhysics.appleSpring) {
                isCenterPressed = false
            }
        }
    }

    // MARK: - Direction Arrow Hotspot Button
    private func directionButton(_ dir: String, symbol: String, x: CGFloat, y: CGFloat) -> some View {
        let isSelected = selection == .stick(dir)
        let isHovered = hoveredSelection == .stick(dir)
        let isEmphasized = isSelected || isHovered

        return Button {
            selection = .stick(dir)
            onSelect?(.stick(dir))
        } label: {
            ZStack {
                Circle()
                    .fill(isEmphasized ? Color.accentColor : Color.black.opacity(0.55))
                    .overlay(
                        Circle()
                            .stroke(
                                isEmphasized ? Color.white.opacity(0.9) : Color.white.opacity(0.25),
                                lineWidth: isEmphasized ? 1.5 : 0.8
                            )
                    )
                    .frame(width: 22, height: 22)

                Image(systemName: symbol)
                    .font(.system(size: 9, weight: isEmphasized ? .heavy : .bold))
                    .foregroundStyle(Color.white)
            }
            .shadow(
                color: isEmphasized ? Color.accentColor.opacity(0.65) : Color.black.opacity(0.3),
                radius: isEmphasized ? 5 : 2
            )
        }
        .buttonStyle(TactileHotspotButtonStyle(isEmphasized: isEmphasized))
        .frame(width: 24, height: 24)
        .contentShape(Circle())
        .offset(x: x, y: y)
        .onHover { isHovered in
            if isHovered {
                hoveredSelection = .stick(dir)
            } else if hoveredSelection == .stick(dir) {
                hoveredSelection = nil
            }
        }
        .accessibilityLabel("\(side.stickLabel) \(directionChinese(dir))方向")
        .accessibilityHint("编辑此方向映射")
        .help("编辑 \(side.stickLabel) \(dir) 映射")
    }

    private func directionChinese(_ dir: String) -> String {
        switch dir {
        case "up": return "上"
        case "down": return "下"
        case "left": return "左"
        case "right": return "右"
        default: return dir
        }
    }
}
