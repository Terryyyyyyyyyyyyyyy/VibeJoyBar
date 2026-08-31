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

            Spacer(minLength: 8)
            if mode == .front {
                stickLegend
                    .padding(.horizontal, 24)
            }
            assetCanvas
            Spacer(minLength: 8)
            Text("点击控制选择映射 · Tab 切换焦点")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder private var assetCanvas: some View {
        if mode == .front {
            controllerAsset(mode.assetName, aspect: 0.40) { size in
                faceHotspot("plus", x: 0.43, y: 0.20, in: size)
                faceHotspot("x", x: 0.67, y: 0.29, in: size)
                faceHotspot("y", x: 0.45, y: 0.38, in: size)
                faceHotspot("a", x: 0.76, y: 0.38, in: size)
                faceHotspot("b", x: 0.59, y: 0.47, in: size)
                stickDirectionHotspot("up", symbol: "arrow.up", x: 0.64, y: 0.56, in: size)
                stickDirectionHotspot("left", symbol: "arrow.left", x: 0.53, y: 0.65, in: size)
                stickDirectionHotspot("right", symbol: "arrow.right", x: 0.75, y: 0.65, in: size)
                stickDirectionHotspot("down", symbol: "arrow.down", x: 0.64, y: 0.74, in: size)
                faceHotspot("r-stick", x: 0.64, y: 0.65, in: size)
                faceHotspot("home", x: 0.53, y: 0.79, in: size)
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

    private func controllerAsset<Hotspots: View>(_ name: String, aspect: CGFloat, @ViewBuilder hotspots: @escaping (CGSize) -> Hotspots) -> some View {
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
        .frame(maxWidth: mode == .front ? 360 : 610, maxHeight: mode == .front ? 560 : 340)
        .padding(.horizontal, 30)
    }

    private var controllerAssetBundle: Bundle {
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent("VibeJoyBar_VibeJoyBar.bundle")) {
            return bundle
        }
        return .module
    }

    private func faceHotspot(_ id: String, x: CGFloat, y: CGFloat, in size: CGSize) -> some View {
        Button { selection = .button(id) } label: {
            Text(hotspotTitle(id))
                .font(.system(size: id == "r-stick" ? 8 : 10, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(selection == .button(id) ? Color.accentColor : Color.primary)
                .frame(width: id == "r-stick" ? 43 : 30, height: id == "r-stick" ? 43 : 30)
                .background(selection == .button(id) ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.10), in: Circle())
                .overlay(Circle().stroke(selection == .button(id) ? Color.accentColor : Color.primary.opacity(0.34), lineWidth: selection == .button(id) ? 2.5 : 1))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .position(x: x * size.width, y: y * size.height)
        .accessibilityLabel("\(hotspotTitle(id)) 控制")
        .accessibilityHint("打开映射检查器")
        .help("编辑 \(hotspotTitle(id)) 映射")
    }

    private var stickLegend: some View {
        Text("R 摇杆：↑ / ↓ 当前对话翻页 · ← / → 切换对话；按住 ZR 时 ← / → 改为系统 App 切换")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stickDirectionHotspot(_ id: String, symbol: String, x: CGFloat, y: CGFloat, in size: CGSize) -> some View {
        Button { selection = .stick(id) } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(selection == .stick(id) ? Color.accentColor : Color.primary)
                .frame(width: 24, height: 24)
                .background(selection == .stick(id) ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.09), in: Circle())
                .overlay(Circle().stroke(selection == .stick(id) ? Color.accentColor : Color.primary.opacity(0.28), lineWidth: selection == .stick(id) ? 2 : 1))
        }
        .buttonStyle(.plain)
        .position(x: x * size.width, y: y * size.height)
        .accessibilityLabel("R 摇杆 \(id == "up" ? "上" : id == "down" ? "下" : id == "left" ? "左" : "右")方向")
        .accessibilityHint("编辑此方向的 Codex 映射")
        .help("编辑 R 摇杆 \(id) 映射")
    }

    private func hotspotTitle(_ id: String) -> String {
        switch id {
        case "plus": "+"
        case "r-stick": "R\nSTICK"
        case "home": "HOME"
        default: id.uppercased()
        }
    }
}
