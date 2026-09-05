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
        case (.shoulder, .right): return "right-joycon-shoulder-base.png"
        case (.front, .left):     return "left-joycon-front.png"
        case (.shoulder, .left):  return "left-joycon-shoulder-base.png"
        }
    }
}

struct ControllerIllustrationView: View {
    @Binding var selection: MappingSelection?
    var controllerSide: ActiveControllerSide = .right
    @State private var mode: ControllerViewMode = .front
    @State private var hoveredSelection: MappingSelection?

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
            Text("点击控制器按键或摇杆选择映射")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .background(.regularMaterial)
    }

    private func shoulderCapsule(_ id: String, label: String) -> some View {
        let isSelected = selection == .button(id)
        let isHovered = hoveredSelection == .button(id)
        let isEmphasized = isSelected || isHovered

        return Button {
            selection = .button(id)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    ZStack {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: isSelected
                                        ? [Color.accentColor, Color.accentColor.opacity(0.85)]
                                        : (isHovered
                                            ? [Color(white: 0.30), Color(white: 0.20)]
                                            : [Color(white: 0.22), Color(white: 0.13)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Capsule()
                            .strokeBorder(
                                isSelected
                                    ? Color.white.opacity(0.4)
                                    : (isHovered ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.25)),
                                lineWidth: isHovered ? 1.5 : 1.0
                            )
                    }
                    .shadow(
                        color: isEmphasized ? Color.accentColor.opacity(0.55) : Color.black.opacity(0.35),
                        radius: isEmphasized ? 5 : 2,
                        y: 1.5
                    )
                }
                .contentShape(Capsule())
        }
        .buttonStyle(TactileCapsuleButtonStyle(isEmphasized: isEmphasized))
        .contentShape(Capsule())
        .onHover { isHovered in
            if isHovered {
                hoveredSelection = .button(id)
            } else if hoveredSelection == .button(id) {
                hoveredSelection = nil
            }
        }
        .accessibilityLabel("\(label) 肩键映射")
        .help("编辑 \(label) 映射")
    }

    @ViewBuilder private var assetCanvas: some View {
        if mode == .front {
            if controllerSide == .right {
                controllerAsset(mode.assetName(for: controllerSide), aspect: 0.40) { size in
                    // Face buttons matched to exact asset pixel centers
                    faceHotspot("plus", x: 0.442, y: 0.132, in: size)
                    faceHotspot("x", x: 0.648, y: 0.218, in: size)
                    faceHotspot("y", x: 0.513, y: 0.277, in: size)
                    faceHotspot("a", x: 0.786, y: 0.281, in: size)
                    faceHotspot("b", x: 0.648, y: 0.346, in: size)

                    // Interactive 3D Joy-Con Stick with tactile physics
                    InteractiveJoyConStickView(
                        side: .right,
                        selection: $selection,
                        hoveredSelection: $hoveredSelection
                    )
                    .position(x: 0.679 * size.width, y: 0.539 * size.height)

                    // Home and rail buttons
                    faceHotspot("home", x: 0.530, y: 0.709, in: size)
                    faceHotspot("sl", x: 0.157, y: 0.290, in: size)
                    faceHotspot("sr", x: 0.160, y: 0.661, in: size)
                }
            } else {
                // Left Joy-Con front: rounded edge on LEFT, rail on RIGHT
                // L-Stick upper, D-Pad lower, Minus top, Capture bottom
                controllerAsset(mode.assetName(for: controllerSide), aspect: 0.40) { size in
                    // Interactive 3D Joy-Con Stick with tactile physics (upper region)
                    InteractiveJoyConStickView(
                        side: .left,
                        selection: $selection,
                        hoveredSelection: $hoveredSelection
                    )
                    .position(x: 0.370 * size.width, y: 0.288 * size.height)

                    // Minus (top-right area) and Capture (bottom area)
                    faceHotspot("minus",   x: 0.594, y: 0.138, in: size)
                    faceHotspot("capture", x: 0.511, y: 0.714, in: size)
                    // Authentic Left Joy-Con directional circular buttons (diamond layout)
                    faceHotspot("up",    x: 0.380, y: 0.489, in: size)
                    faceHotspot("down",  x: 0.380, y: 0.623, in: size)
                    faceHotspot("left",  x: 0.247, y: 0.556, in: size)
                    faceHotspot("right", x: 0.514, y: 0.556, in: size)
                    // Rail buttons — on the RIGHT rail
                    faceHotspot("sl", x: 0.862, y: 0.289, in: size)
                    faceHotspot("sr", x: 0.860, y: 0.659, in: size)
                }
            }
        } else {
            if controllerSide == .right {
                controllerAsset(mode.assetName(for: controllerSide), aspect: 1.26) { size in
                    shoulderPhysicalButton(
                        id: "zr",
                        assetName: "right-joycon-zr-button.png",
                        centerX: 0.5565,
                        centerY: 0.1789,
                        widthRatio: 0.6287,
                        heightRatio: 0.3239,
                        travel: 6.5,
                        in: size
                    )
                    shoulderPhysicalButton(
                        id: "r",
                        assetName: "right-joycon-r-button.png",
                        centerX: 0.5816,
                        centerY: 0.5113,
                        widthRatio: 0.6825,
                        heightRatio: 0.1648,
                        travel: 4.8,
                        in: size
                    )
                }
            } else {
                controllerAsset(mode.assetName(for: controllerSide), aspect: 1.26) { size in
                    shoulderPhysicalButton(
                        id: "zl",
                        assetName: "left-joycon-zl-button.png",
                        centerX: 0.5610,
                        centerY: 0.1648,
                        widthRatio: 0.6233,
                        heightRatio: 0.2957,
                        travel: 6.5,
                        in: size
                    )
                    shoulderPhysicalButton(
                        id: "l",
                        assetName: "left-joycon-l-button.png",
                        centerX: 0.5879,
                        centerY: 0.4983,
                        widthRatio: 0.6897,
                        heightRatio: 0.1659,
                        travel: 4.8,
                        in: size
                    )
                }
            }
        }
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

    private func hotspotSize(for id: String) -> CGSize {
        switch id {
        case "a", "b", "x", "y":
            return CGSize(width: 34, height: 34)
        case "plus":
            return CGSize(width: 24, height: 24)
        case "minus":
            return CGSize(width: 26, height: 12)
        case "capture":
            return CGSize(width: 24, height: 24)
        case "home":
            return CGSize(width: 38, height: 38)
        case "sl", "sr":
            return CGSize(width: 16, height: 38)
        case "up", "down", "left", "right":
            return CGSize(width: 34, height: 34)
        case "r-stick", "l-stick":
            return CGSize(width: 52, height: 52)
        case "r", "zr", "l", "zl":
            return CGSize(width: 76, height: 32)
        default:
            return CGSize(width: 32, height: 32)
        }
    }

    // Hotspot indicators shaped around physical hardware with elegant glowing highlights & tactile depression.
    private func faceHotspot(_ id: String, x: CGFloat, y: CGFloat, in size: CGSize) -> some View {
        let isSelected = selection == .button(id)
        let isHovered = hoveredSelection == .button(id)
        let isEmphasized = isSelected || isHovered
        let btnSize = hotspotSize(for: id)

        return Button {
            selection = .button(id)
        } label: {
            tactileHaloShape(for: id, isSelected: isSelected, isHovered: isHovered)
        }
        .buttonStyle(TactileHotspotButtonStyle(isEmphasized: isEmphasized))
        .frame(width: btnSize.width + 4, height: btnSize.height + 4)
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                hoveredSelection = .button(id)
            } else if hoveredSelection == .button(id) {
                hoveredSelection = nil
            }
        }
        .position(x: x * size.width, y: y * size.height)
        .accessibilityLabel("\(hotspotTitle(id)) 控制")
        .accessibilityHint("打开映射检查器")
        .help("编辑 \(hotspotTitle(id)) 映射")
    }

    @ViewBuilder
    private func tactileHaloShape(for id: String, isSelected: Bool, isHovered: Bool) -> some View {
        switch id {
        case "a", "b", "x", "y":
            buttonHalo(shape: Circle(), width: 34, height: 34, isSelected: isSelected, isHovered: isHovered)
        case "up", "down", "left", "right":
            buttonHalo(shape: Circle(), width: 34, height: 34, isSelected: isSelected, isHovered: isHovered)
        case "plus":
            buttonHalo(shape: RoundedRectangle(cornerRadius: 5), width: 24, height: 24, isSelected: isSelected, isHovered: isHovered)
        case "minus":
            buttonHalo(shape: Capsule(), width: 26, height: 12, isSelected: isSelected, isHovered: isHovered)
        case "home":
            buttonHalo(shape: Circle(), width: 38, height: 38, isSelected: isSelected, isHovered: isHovered)
        case "capture":
            buttonHalo(shape: RoundedRectangle(cornerRadius: 4), width: 24, height: 24, isSelected: isSelected, isHovered: isHovered)
        case "sl", "sr":
            buttonHalo(shape: Capsule(), width: 16, height: 38, isSelected: isSelected, isHovered: isHovered)
        case "r", "zr", "l", "zl":
            buttonHalo(shape: Capsule(), width: 76, height: 32, isSelected: isSelected, isHovered: isHovered)
        default:
            buttonHalo(shape: Circle(), width: 32, height: 32, isSelected: isSelected, isHovered: isHovered)
        }
    }

    private func buttonHalo<S: InsettableShape>(
        shape: S,
        width: CGFloat,
        height: CGFloat,
        isSelected: Bool,
        isHovered: Bool
    ) -> some View {
        let isEmphasized = isSelected || isHovered

        return ZStack {
            // 1. Recessed dark socket rim (simulates the physical gap around the button)
            shape
                .stroke(Color.black.opacity(0.50), lineWidth: 2)

            // 2. Translucent accent tint (keeps the artwork's button & lettering clearly visible!)
            shape
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.24)
                        : (isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                )

            // 3. Crisp luminous highlight outline around the real button
            shape
                .strokeBorder(
                    isSelected
                        ? Color.accentColor
                        : (isHovered ? Color.accentColor.opacity(0.85) : Color.clear),
                    lineWidth: isSelected ? 2.5 : 1.8
                )
        }
        .frame(width: width, height: height)
        .shadow(
            color: isEmphasized ? Color.accentColor.opacity(isSelected ? 0.70 : 0.45) : Color.clear,
            radius: isSelected ? 8 : 4,
            y: isSelected ? 1.5 : 1.0
        )
        .opacity(isEmphasized ? 1.0 : 0.0)
        .animation(TactilePhysics.hoverSpring, value: isEmphasized)
    }

    private func shoulderPhysicalButton(
        id: String,
        assetName: String,
        centerX: CGFloat,
        centerY: CGFloat,
        widthRatio: CGFloat,
        heightRatio: CGFloat,
        travel: CGFloat,
        in size: CGSize
    ) -> some View {
        let isSelected = selection == .button(id)
        let isHovered = hoveredSelection == .button(id)
        let isEmphasized = isSelected || isHovered
        let w = widthRatio * size.width
        let h = heightRatio * size.height

        return Button {
            selection = .button(id)
        } label: {
            if let url = controllerAssetBundle.url(forResource: assetName, withExtension: nil),
               let img = NSImage(contentsOfFile: url.path) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)
                    .brightness(isHovered ? 0.04 : 0.0)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.2))
                    .frame(width: w, height: h)
            }
        }
        .buttonStyle(
            TactileHotspotButtonStyle(
                isEmphasized: isEmphasized,
                travel: travel,
                depressedScale: 0.99,
                emphasizedScale: 1.0
            )
        )
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                hoveredSelection = .button(id)
            } else if hoveredSelection == .button(id) {
                hoveredSelection = nil
            }
        }
        .position(x: centerX * size.width, y: centerY * size.height)
        .accessibilityLabel("\(id.uppercased()) 肩部控制")
        .accessibilityHint("打开映射检查器")
        .help("编辑 \(id.uppercased()) 映射")
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
