import SwiftUI
import AppKit

enum ControllerViewMode: String, CaseIterable {
    case front
    case shoulder

    var title: String { self == .front ? "正面" : "肩部" }
    var assetName: String { self == .front ? "right-joycon-front.png" : "right-joycon-shoulder.png" }
    var help: String { self == .front ? "正面按键与摇杆" : "肩部 R / ZR" }
}

struct ControllerIllustrationView: View {
    @Binding var selection: MappingSelection?
    @State private var mode: ControllerViewMode = .front
    @State private var hoveredHotspot: String?
    @FocusState private var focusedHotspot: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("右 Joy-Con").font(.title3.weight(.semibold))
                    Text(mode.help).font(.caption).foregroundStyle(.secondary)
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
                    shoulderCapsule("r", label: "R")
                    shoulderCapsule("zr", label: "ZR")
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
            controllerAsset(mode.assetName, aspect: 0.40) { size in
                // Stick subtle compass backdrop disk for unified visual anchoring
                stickCompassBackdrop(x: 0.64, y: 0.65, in: size)

                faceHotspot("plus", x: 0.43, y: 0.20, in: size)
                faceHotspot("x", x: 0.67, y: 0.29, in: size)
                faceHotspot("y", x: 0.45, y: 0.38, in: size)
                faceHotspot("a", x: 0.76, y: 0.38, in: size)
                faceHotspot("b", x: 0.59, y: 0.47, in: size)
                faceHotspot("r-stick", x: 0.64, y: 0.65, in: size)
                stickDirectionHotspot("up", symbol: "arrow.up", x: 0.64, y: 0.56, in: size)
                stickDirectionHotspot("left", symbol: "arrow.left", x: 0.53, y: 0.65, in: size)
                stickDirectionHotspot("right", symbol: "arrow.right", x: 0.75, y: 0.65, in: size)
                stickDirectionHotspot("down", symbol: "arrow.down", x: 0.64, y: 0.74, in: size)
                faceHotspot("home", x: 0.53, y: 0.82, in: size)
                faceHotspot("sl", x: 0.13, y: 0.31, in: size)
                faceHotspot("sr", x: 0.13, y: 0.80, in: size)
            }
        } else {
            controllerAsset(mode.assetName, aspect: 1.26) { size in
                faceHotspot("zr", x: 0.56, y: 0.20, in: size)
                faceHotspot("r", x: 0.59, y: 0.52, in: size)
            }
        }
    }

    private func stickCompassBackdrop(x: CGFloat, y: CGFloat, in size: CGSize) -> some View {
        let isStickActive = {
            if case .stick = selection { return true }
            if selection == .button("r-stick") { return true }
            if let h = hoveredHotspot, ["up", "down", "left", "right", "r-stick"].contains(h) { return true }
            return false
        }()

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial.opacity(isStickActive ? 0.8 : 0.4))
                .frame(width: 82, height: 82)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isStickActive
                                    ? [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.12)]
                                    : [Color.primary.opacity(0.12), Color.primary.opacity(0.04)],
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
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(.quaternary.opacity(0.30))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary, lineWidth: 1))
            if let url = controllerAssetBundle.url(forResource: name, withExtension: nil),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .overlay {
                        GeometryReader { proxy in
                            ZStack { hotspots(proxy.size) }
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    GeometryReader { proxy in
                        ZStack { hotspots(proxy.size) }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: mode == .front ? 400 : 610, maxHeight: mode == .front ? 600 : 340)
        .padding(.horizontal, 30)
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
        switch id {
        case "a", "b", "x", "y":
            Circle()
                .fill(emphasized ? Color.accentColor.opacity(0.22) : Color.accentColor.opacity(0.04))
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: emphasized
                                    ? [Color.accentColor, Color.accentColor.opacity(0.6)]
                                    : [Color.primary.opacity(0.22), Color.primary.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: emphasized ? Color.accentColor.opacity(0.45) : .clear, radius: 5)
                .frame(width: 32, height: 32)

        case "sl", "sr":
            Capsule()
                .fill(emphasized ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: emphasized
                                    ? [Color.accentColor, Color.accentColor.opacity(0.7)]
                                    : [Color.primary.opacity(0.2), Color.primary.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: emphasized ? Color.accentColor.opacity(0.45) : .clear, radius: 4)
                .frame(width: 14, height: 36)

        case "plus":
            RoundedRectangle(cornerRadius: 6)
                .fill(emphasized ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            LinearGradient(
                                colors: emphasized
                                    ? [Color.accentColor, Color.accentColor.opacity(0.6)]
                                    : [Color.primary.opacity(0.22), Color.primary.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: emphasized ? Color.accentColor.opacity(0.45) : .clear, radius: 4)
                .frame(width: 24, height: 24)

        case "home":
            ZStack {
                Circle()
                    .stroke(
                        emphasized ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
                    .frame(width: 36, height: 36)

                Circle()
                    .fill(emphasized ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: emphasized
                                        ? [Color.accentColor, Color.accentColor.opacity(0.7)]
                                        : [Color.primary.opacity(0.22), Color.primary.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .frame(width: 28, height: 28)
            }
            .shadow(color: emphasized ? Color.accentColor.opacity(0.45) : .clear, radius: 5)

        case "r-stick":
            ZStack {
                Circle()
                    .fill(emphasized ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.04))
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: emphasized
                                        ? [Color.accentColor, Color.accentColor.opacity(0.65)]
                                        : [Color.primary.opacity(0.25), Color.primary.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .frame(width: 46, height: 46)

                Circle()
                    .stroke(
                        emphasized ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.16),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                    .frame(width: 26, height: 26)

                Circle()
                    .fill(emphasized ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
            .shadow(color: emphasized ? Color.accentColor.opacity(0.45) : .clear, radius: 5)

        case "r", "zr":
            Capsule()
                .fill(emphasized ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: emphasized
                                    ? [Color.accentColor, Color.accentColor.opacity(0.7)]
                                    : [Color.primary.opacity(0.22), Color.primary.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: emphasized ? Color.accentColor.opacity(0.45) : .clear, radius: 5)
                .frame(width: 76, height: 34)

        default:
            Circle()
                .fill(emphasized ? Color.accentColor.opacity(0.20) : Color.clear)
                .overlay(Circle().stroke(emphasized ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: 1.5))
                .shadow(color: emphasized ? Color.accentColor.opacity(0.45) : .clear, radius: 5)
                .frame(width: 32, height: 32)
        }
    }

    private var stickLegend: some View {
        Text("R 摇杆：↑ / ↓ 滚动当前对话约一页 · ← / → 切换对话；按住 ZR 时 ← / → 改为系统 App 切换")
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
                    .fill(emphasized ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07))
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: emphasized
                                        ? [Color.accentColor, Color.accentColor.opacity(0.7)]
                                        : [Color.primary.opacity(0.22), Color.primary.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: emphasized ? 1.5 : 1
                            )
                    )
                    .frame(width: 24, height: 24)

                Image(systemName: symbol)
                    .font(.system(size: 10, weight: emphasized ? .bold : .semibold))
                    .foregroundStyle(emphasized ? Color.accentColor : Color.secondary)
            }
            .shadow(color: emphasized ? Color.accentColor.opacity(0.55) : Color.clear, radius: 5)
            .scaleEffect(emphasized ? 1.12 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: emphasized)
        }
        .buttonStyle(.plain)
        .position(x: x * size.width, y: y * size.height)
        .onHover { isHovered in
            if isHovered { hoveredHotspot = id } else if hoveredHotspot == id { hoveredHotspot = nil }
        }
        .focused($focusedHotspot, equals: id)
        .accessibilityLabel("R 摇杆 \(id == "up" ? "上" : id == "down" ? "下" : id == "left" ? "左" : "右")方向")
        .accessibilityHint("编辑此方向的 Codex 映射")
        .help("编辑 R 摇杆 \(id) 映射")
    }

    private func hotspotTitle(_ id: String) -> String {
        switch id {
        case "plus": "+"
        case "r-stick": "R 摇杆"
        case "home": "Home"
        default: id.uppercased()
        }
    }
}
