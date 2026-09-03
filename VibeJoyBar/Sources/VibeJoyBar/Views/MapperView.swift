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
    @State private var showingResetConfirmation = false
    @State private var showingSaveAsSheet = false
    @State private var newProfileName = ""
    @State private var showingDeleteConfirmation = false

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

            Menu {
                ForEach(model.configStore.availableProfiles) { profile in
                    Button {
                        model.switchToProfile(named: profile.name)
                    } label: {
                        if profile.isActive {
                            Label(profile.name + (profile.isDefault ? " (出厂基准)" : ""), systemImage: "checkmark")
                        } else {
                            Text(profile.name + (profile.isDefault ? " (出厂基准)" : ""))
                        }
                    }
                }
                Divider()
                Button {
                    newProfileName = ""
                    showingSaveAsSheet = true
                } label: {
                    Label("另存为新方案…", systemImage: "plus")
                }
                if model.configStore.activeProfileName != "default" {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("删除当前方案", systemImage: "trash")
                    }
                }
            } label: {
                Label("方案: \(model.configStore.activeProfileName)", systemImage: "slider.horizontal.3")
            }
            .menuStyle(.borderedButton)
            .disabled(model.isBusy)

            Button(model.processService.desiredRunning ? "停止后台" : "启动后台") {
                model.processService.desiredRunning ? model.processService.stop() : model.processService.start()
            }
            .buttonStyle(.bordered)
            Button { model.configStore.load() } label: { Label("重新读取", systemImage: "arrow.clockwise") }
                .help("从配置文件重新加载映射")
            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label("恢复默认", systemImage: "arrow.counterclockwise")
            }
            .help("恢复为出厂基准方案并备份当前配置")
            .disabled(model.isBusy)
            .confirmationDialog(
                "确认恢复出厂基准方案？",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("恢复出厂默认", role: .destructive) {
                    model.resetToDefaultProfile()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将重置所有按键、摇杆与 Codex 导航映射为官方默认配置。您当前的配置将自动备份。")
            }
            .confirmationDialog(
                "确认删除方案 '\(model.configStore.activeProfileName)'？",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除方案", role: .destructive) {
                    model.deleteProfile(named: model.configStore.activeProfileName)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后将自动切换回出厂基准方案 'default'。")
            }
            .sheet(isPresented: $showingSaveAsSheet) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("另存为新方案")
                        .font(.headline)
                    Text("输入新方案名称（例如 coding、browser、gaming）：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("方案名称", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("取消") {
                            showingSaveAsSheet = false
                        }
                        Button("保存并切换") {
                            let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty {
                                showingSaveAsSheet = false
                                model.saveAsNewProfile(named: name)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20)
                .frame(width: 340)
            }
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
