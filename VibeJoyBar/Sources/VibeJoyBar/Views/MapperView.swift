import SwiftUI

struct MapperView: View {
    @Bindable var model: AppModel
    @State private var selection: MappingSelection? = .button("a")
    @State private var showingStickEditor = false

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader(model: model)
            Divider()
            HSplitView {
                DashboardSidebar(model: model, selection: $selection, showingStickEditor: $showingStickEditor)
                    .frame(minWidth: 230, idealWidth: 270, maxWidth: 320)
                ControllerIllustrationView(selection: $selection)
                    .frame(minWidth: 470, idealWidth: 560)
                MappingInspector(model: model, selection: $selection, showingStickEditor: $showingStickEditor)
                    .frame(minWidth: 340, idealWidth: 390, maxWidth: 450)
            }
            .frame(maxHeight: .infinity)
            Divider()
            DashboardFooter(model: model)
        }
        .frame(minWidth: 1100, idealWidth: 1180, minHeight: 700, idealHeight: 760)
        .background(.regularMaterial)
        .sheet(isPresented: $showingStickEditor) {
            JoystickEditorView(model: model, selection: $selection)
                .frame(width: 540, height: 390)
        }
    }
}

struct DashboardHeader: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.14)).frame(width: 38, height: 38)
                Image(systemName: model.processService.phase.symbolName).foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("右 Joy-Con 控制器")
                    .font(.title3.weight(.semibold))
                Text(model.processService.phase.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.processService.desiredRunning ? "停止后台" : "启动后台") {
                model.processService.desiredRunning ? model.processService.stop() : model.processService.start()
            }
            .buttonStyle(.bordered)
            Button { model.configStore.load() } label: { Label("重新读取", systemImage: "arrow.clockwise") }
                .help("从配置文件重新加载映射")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var statusColor: Color {
        switch model.processService.phase {
        case .running: .green
        case .starting, .waitingForController, .needsAccessibility: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }
}

struct DashboardFooter: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.configStore.hasUnsavedChanges ? "circle.dotted" : "checkmark.circle.fill")
                .foregroundStyle(model.configStore.hasUnsavedChanges ? .orange : .green)
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("仅校验") { model.validateCurrentConfig() }.disabled(model.isBusy)
            Button("保存并重启") { model.saveMappings() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || !model.configStore.hasUnsavedChanges)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
    }
    private var message: String {
        if !model.activityMessage.isEmpty { return model.activityMessage }
        if let error = model.configStore.errorMessage { return error }
        return model.configStore.hasUnsavedChanges ? "有未保存的更改" : "配置已同步 · 不使用自动震动"
    }
}
