import SwiftUI
import AppKit

enum ControllerViewMode: String, CaseIterable {
    case front
    case shoulder

    var title: String { self == .front ? "正面" : "肩部" }
    var help: String { self == .front ? "正面按键与摇杆" : "肩部" }

    func assetName(for side: ActiveControllerSide) -> String {
        switch (self, side) {
        case (.front, .right):    return "right-joycon-front.png"
        case (.shoulder, .right): return "right-joycon-shoulder.png"
        case (.front, .left):     return "left-joycon-front.png"
        case (.shoulder, .left):  return "left-joycon-shoulder.png"
        }
    }
}

struct ControllerIllustrationView: View {
    @Binding var selection: MappingSelection?
    var controllerSide: ActiveControllerSide = .right
    @State private var mode: ControllerViewMode = .front
    @State private var hoveredHotspot: String?
    @FocusState private var focusedHotspot: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(controllerSide.displayName).font(.title3.weight(.semibold))
                    Text(mode == .front ? "正面按键与摇杆" : (controllerSide == .right ? "肩部 R / ZR" : "肩部 L / ZL"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("控制器视图", selection: $mode) {
                    ForEach(ControllerViewMode.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .accessibilityLabel("控制器视图")
            }
            .padding(.horizontal, 24).padding(.top, 22)

            if mode == .front {
                // Shoulder key quick-access capsules — visible without switching Tab
                HStack(spacing: 10) {
                    Text("肩键")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    if controllerSide == .right {
                        shoulderCapsule("r", label: "R")
                        shoulderCapsule("zr", label: "ZR")
                    } else {
                        shoulderCapsule("l", label: "L")
                        shoulderCapsule("zl", label: "ZL")
                    }
                    Spacer()
                }
                .padding(.horizontal, 26)
                .padding(.top, 10)

                stickLegend
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
            }

            Spacer(minLength: 8)
            assetCanvas
            Spacer(minLength: 8)
            Text("点击控制选择映射 · Tab 切换焦点")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .background(.regularMaterial)
    }

    private func shoulderCapsule(_ id: String, label: String) -> some View {
        let isSelected = selection == .button(id)
        let isHovered = hoveredHotspot == id
        let isEmphasized = isSelected || isHovered

        return Button {
            selection = .button(id)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.primary : Color.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 1.5)
                    } else if isHovered {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                    } else {
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    }
                }
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear : (isHovered ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.12)),
                            lineWidth: 1
                        )
                )
                .scaleEffect(isEmphasized ? 1.04 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isEmphasized)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered { hoveredHotspot = id } else if hoveredHotspot == id { hoveredHotspot = nil }
        }
        .accessibilityLabel("\(label) 肩键映射")
        .help("编辑 \(label) 映射")
    }

    @ViewBuilder private var assetCanvas: some View {
        if mode == .front {
            if controllerSide == .right {
                controllerAsset(mode.assetName(for: controllerSide), aspect: 0.40) { size in
                    // Stick compass backdrop centered directly on analog stick
                    stickCompassBackdrop(x: 0.677, y: 0.540, in: size)

                    // Face buttons matched to exact asset pixel centers
                    faceHotspot("plus", x: 0.442, y: 0.132, in: size)
                    faceHotspot("x", x: 0.651, y: 0.211, in: size)
                    faceHotspot("y", x: 0.494, y: 0.283, in: size)
                    faceHotspot("a", x: 0.807, y: 0.283, in: size)
                    faceHotspot("b", x: 0.651, y: 0.354, in: size)

                    // Stick center and 4 direction arrow dials
                    faceHotspot("r-stick", x: 0.677, y: 0.540, in: size)
                    stickDirectionHotspot("up", symbol: "arrow.up", x: 0.677, y: 0.468, in: size)
                    stickDirectionHotspot("left", symbol: "arrow.left", x: 0.535, y: 0.540, in: size)
                    stickDirectionHotspot("right", symbol: "arrow.right", x: 0.819, y: 0.540, in: size)
                    stickDirectionHotspot("down", symbol: "arrow.down", x: 0.677, y: 0.612, in: size)

                    // Home and rail buttons
                    faceHotspot("home", x: 0.529, y: 0.713, in: size)
                    faceHotspot("sl", x: 0.158, y: 0.290, in: size)
                    faceHotspot("sr", x: 0.160, y: 0.660, in: size)
                }
            } else {
                // Left Joy-Con front: rounded edge on LEFT, rail on RIGHT
                // L-Stick upper, D-Pad lower, Minus top, Capture bottom
                controllerAsset(mode.assetName(for: controllerSide), aspect: 0.40) { size in
                    // L-Stick area (upper region) — mirrored x from right-hand stick coords
                    stickCompassBackdrop(x: 0.400, y: 0.280, in: size)
                    faceHotspot("l-stick", x: 0.400, y: 0.280, in: size)
                    stickDirectionHotspot("up",    symbol: "arrow.up",    x: 0.400, y: 0.208, in: size)
                    stickDirectionHotspot("left",  symbol: "arrow.left",  x: 0.258, y: 0.280, in: size)
                    stickDirectionHotspot("right", symbol: "arrow.right", x: 0.542, y: 0.280, in: size)
                    stickDirectionHotspot("down",  symbol: "arrow.down",  x: 0.400, y: 0.352, in: size)
                    // Minus (top-right area, near rail) and Capture (bottom center)
                    faceHotspot("minus",   x: 0.442, y: 0.132, in: size)
                    faceHotspot("capture", x: 0.400, y: 0.780, in: size)
                    // D-Pad (lower region, center-left)
                    faceHotspot("up",    x: 0.380, y: 0.530, in: size)
                    faceHotspot("down",  x: 0.380, y: 0.672, in: size)
                    faceHotspot("left",  x: 0.238, y: 0.601, in: size)
                    faceHotspot("right", x: 0.522, y: 0.601, in: size)
                    // Rail buttons — on the RIGHT side now
                    faceHotspot("sl", x: 0.842, y: 0.290, in: size)
                    faceHotspot("sr", x: 0.842, y: 0.660, in: size)
                }
            }
        } else {
            if controllerSide == .right {
                controllerAsset(mode.assetName(for: controllerSide), aspect: 1.26) { size in
                    faceHotspot("zr", x: 0.652, y: 0.216, in: size)
                    faceHotspot("r", x: 0.663, y: 0.538, in: size)
                }
            } else {
                controllerAsset(mode.assetName(for: controllerSide), aspect: 1.26) { size in
                    faceHotspot("zl", x: 0.348, y: 0.216, in: size)
                    faceHotspot("l", x: 0.337, y: 0.538, in: size)
                }
            }
        }
    }

    private func stickCompassBackdrop(x: CGFloat, y: CGFloat, in size: CGSize) -> some View {
        let stickButtonID = controllerSide.stickButtonID
        let stickDirections = ["up", "down", "left", "right"]
        let isStickActive = {
            if case .stick = selection { return true }
            if selection == .button(stickButtonID) { return true }
            if let h = hoveredHotspot, (stickDirections + [stickButtonID]).contains(h) { return true }
            return false
        }()

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial.opacity(isStickActive ? 0.7 : 0.0))
                .frame(width: 76, height: 76)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isStickActive
                                    ? [Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.12)]
                                    : [.clear, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
        .position(x: x * size.width, y: y * size.height)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: isStickActive)
    }

    private func controllerAsset<Hotspots: View>(
        _ name: String,
        aspect: CGFloat,
        @ViewBuilder hotspots: @escaping (CGSize) -> Hotspots
    ) -> some View {
        let imageRatio = mode == .front ? (539.0 / 1349.0) : (1115.0 / 886.0)

        return ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(.quaternary.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary, lineWidth: 1))

            if let url = controllerAssetBundle.url(forResource: name, withExtension: nil),
               let image = NSImage(contentsOf: url) {
                Color.clear
                    .aspectRatio(imageRatio, contentMode: .fit)
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                    .overlay {
                        GeometryReader { proxy in
                            ZStack { hotspots(proxy.size) }
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                    .padding(20)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title)
                    Text("控制器图像不可用")
                        .font(.caption)
                    Text(name)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: mode == .front ? 380 : 580, maxHeight: mode == .front ? 560 : 360)
        .padding(.horizontal, 24)
    }

    private var controllerAssetBundle: Bundle {
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent("VibeJoyBar_VibeJoyBar.bundle")) {
            return bundle
        }
        return .module
    }

    // Hotspot indicators shaped according to physical hardware with elegant glowing highlights.
    private func faceHotspot(_ id: String, x: CGFloat, y: CGFloat, in size: CGSize) -> some View {
        let emphasized = selection == .button(id) || hoveredHotspot == id || focusedHotspot == id
        return Button {
            selection = .button(id)
        } label: {
            hotspotShape(for: id, emphasized: emphasized)
                .scaleEffect(emphasized ? 1.06 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.65), value: emphasized)
        }
        .buttonStyle(.plain)
        .position(x: x * size.width, y: y * size.height)
        .onHover { isHovered in
            if isHovered { hoveredHotspot = id } else if hoveredHotspot == id { hoveredHotspot = nil }
        }
        .focused($focusedHotspot, equals: id)
        .accessibilityLabel("\(hotspotTitle(id)) 控制")
        .accessibilityHint("打开映射检查器")
        .help("编辑 \(hotspotTitle(id)) 映射")
    }

    @ViewBuilder
    private func hotspotShape(for id: String, emphasized: Bool) -> some View {
        Group {
            switch id {
            case "a", "b", "x", "y":
                Circle()
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: Color.accentColor.opacity(0.55), radius: 6)
                    .frame(width: 34, height: 34)

            case "sl", "sr":
                Capsule()
                    .fill(Color.accentColor.opacity(0.28))
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 5)
                    .frame(width: 16, height: 38)

            case "plus", "minus":
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 5)
                    .frame(width: 24, height: 24)

            case "capture":
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 5)
                    .frame(width: 24, height: 24)

            case "home":
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 38, height: 38)

                    Circle()
                        .fill(Color.accentColor.opacity(0.24))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: 28, height: 28)
                }
                .shadow(color: Color.accentColor.opacity(0.5), radius: 6)

            case "r-stick", "l-stick":
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.20))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: 52, height: 52)

                    Circle()
                        .stroke(
                            Color.accentColor.opacity(0.65),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                        .frame(width: 30, height: 30)

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
                .shadow(color: Color.accentColor.opacity(0.5), radius: 6)

            case "r", "zr", "l", "zl":
                Capsule()
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(Capsule().stroke(Color.accentColor, lineWidth: 2))
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 6)
                    .frame(width: 76, height: 34)

            case "up", "down", "left", "right":
                Circle()
                    .fill(Color.accentColor.opacity(0.20))
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 5)
                    .frame(width: 30, height: 30)

            default:
                Circle()
                    .fill(Color.accentColor.opacity(0.20))
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 5)
                    .frame(width: 32, height: 32)
            }
        }
        .opacity(emphasized ? 1.0 : 0.0)
    }

    private var stickLegend: some View {
        let text = controllerSide == .right
            ? "R 摇杆：↑ / ↓ 滚动当前对话约一页 · ← / → 切换对话；按住 ZR 时 ← / → 改为系统 App 切换"
            : "L 摇杆：↑ / ↓ 滚动当前对话约一页 · ← / → 切换对话"
        return Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stickDirectionHotspot(_ id: String, symbol: String, x: CGFloat, y: CGFloat, in size: CGSize) -> some View {
        let isSelected = selection == .stick(id)
        let isHovered = hoveredHotspot == id
        let isFocused = focusedHotspot == id
        let emphasized = isSelected || isHovered || isFocused

        return Button {
            selection = .stick(id)
        } label: {
            ZStack {
                Circle()
                    .fill(emphasized ? Color.accentColor : Color.black.opacity(0.45))
                    .overlay(
                        Circle()
                            .stroke(
                                emphasized ? Color.white.opacity(0.85) : Color.white.opacity(0.20),
                                lineWidth: emphasized ? 1.5 : 0.8
                            )
                    )
                    .frame(width: 22, height: 22)

                Image(systemName: symbol)
                    .font(.system(size: 9, weight: emphasized ? .heavy : .bold))
                    .foregroundStyle(Color.white)
            }
            .shadow(color: emphasized ? Color.accentColor.opacity(0.65) : Color.black.opacity(0.3), radius: emphasized ? 5 : 2)
            .scaleEffect(emphasized ? 1.18 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: emphasized)
        }
        .buttonStyle(.plain)
        .position(x: x * size.width, y: y * size.height)
        .onHover { isHovered in
            if isHovered { hoveredHotspot = id } else if hoveredHotspot == id { hoveredHotspot = nil }
        }
        .focused($focusedHotspot, equals: id)
        .accessibilityLabel("\(controllerSide.stickLabel) \(id == "up" ? "上" : id == "down" ? "下" : id == "left" ? "左" : "右")方向")
        .accessibilityHint("编辑此方向的 Codex 映射")
        .help("编辑 \(controllerSide.stickLabel) \(id) 映射")
    }

    private func hotspotTitle(_ id: String) -> String {
        switch id {
        case "plus": "+"
        case "minus": "-"
        case "r-stick": "R 摇杆"
        case "l-stick": "L 摇杆"
        case "home": "Home"
        case "capture": "Capture"
        case "l": "L"
        case "zl": "ZL"
        case "up": controllerSide == .left ? "D-Pad ↑" : id.uppercased()
        case "down": controllerSide == .left ? "D-Pad ↓" : id.uppercased()
        case "left": controllerSide == .left ? "D-Pad ←" : id.uppercased()
        case "right": controllerSide == .left ? "D-Pad →" : id.uppercased()
        default: id.uppercased()
        }
    }
}
