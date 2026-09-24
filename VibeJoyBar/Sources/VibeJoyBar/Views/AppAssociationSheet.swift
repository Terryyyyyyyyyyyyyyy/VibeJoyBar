import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppAssociationSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProfileName: String
    @State private var associatedApps: [String] = []
    @State private var searchText = ""
    @State private var manualAppInput = ""
    @State private var runningApps: [RunningAppItem] = []
    @State private var showingNewProfileSheet = false
    @State private var newProfileName = ""

    init(model: AppModel, initialProfileName: String? = nil) {
        self.model = model
        let initial = initialProfileName ?? model.configStore.activeProfileName
        _selectedProfileName = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("关联目标应用与方案")
                        .font(.headline)
                    Text("为各个前台应用关联专属按键方案；当对应 App 激活时，方案将毫秒级自动切换。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Picker("目标方案", selection: $selectedProfileName) {
                        ForEach(model.configStore.availableProfiles) { profile in
                            Text(profile.name + (profile.isDefault ? " (出厂基准)" : "")).tag(profile.name)
                        }
                    }
                    .frame(width: 170)

                    Button {
                        newProfileName = ""
                        showingNewProfileSheet = true
                    } label: {
                        Label("新建方案", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help("为新应用创建独立配置方案…")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // Main Content Area
            HSplitView {
                // Left column: Currently associated apps for selected profile
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("当前关联应用 (\(associatedApps.count))")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }

                    if associatedApps.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "app.dashed")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("未关联任何应用")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("从右侧勾选运行中应用或手动添加")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(associatedApps, id: \.self) { app in
                                HStack {
                                    Image(systemName: "app.fill")
                                        .foregroundStyle(.tint)
                                        .font(.system(size: 14))
                                    Text(app)
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        removeApp(app)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                    }

                    Divider()

                    // Manual input & browse button
                    VStack(spacing: 8) {
                        HStack {
                            TextField("输入 Bundle ID 或应用名…", text: $manualAppInput)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addManualApp()
                                }
                            Button("+ 添加") {
                                addManualApp()
                            }
                            .disabled(manualAppInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Button {
                            browseForApplication()
                        } label: {
                            Label("从 Applications 浏览选取…", systemImage: "folder.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .frame(minWidth: 260, idealWidth: 290, maxWidth: 350)

                // Right column: Running applications list with filter
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("运行中的应用")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            refreshRunningApps()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .help("刷新运行中的应用列表")
                    }

                    TextField("搜索应用或 Bundle ID…", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    List {
                        ForEach(filteredRunningApps) { app in
                            let isAssociated = isAppAssociated(app)
                            let otherProfile = profileAssigned(for: app)

                            HStack(spacing: 10) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                } else {
                                    Image(systemName: "app")
                                        .font(.system(size: 20))
                                        .frame(width: 24, height: 24)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.localizedName)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(app.bundleIdentifier)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if let other = otherProfile, other != selectedProfileName {
                                    Text("已关联: \(other)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }

                                Toggle("", isOn: Binding(
                                    get: { isAssociated },
                                    set: { selected in
                                        toggleApp(app, isSelected: selected)
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
                .padding(16)
                .frame(minWidth: 340, idealWidth: 400)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("完成") {
                    saveAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 720, height: 500)
        .onAppear {
            loadAppsForSelectedProfile()
            refreshRunningApps()
        }
        .onChange(of: selectedProfileName) { _, _ in
            loadAppsForSelectedProfile()
        }
        .sheet(isPresented: $showingNewProfileSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("新建配置方案")
                    .font(.headline)
                Text("输入新方案名称（例如 coding、browser、gaming）：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("方案名称", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("取消") { showingNewProfileSheet = false }
                    Button("创建并选择") {
                        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            model.saveAsNewProfile(named: name)
                            selectedProfileName = name
                            showingNewProfileSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
    }

    private var filteredRunningApps: [RunningAppItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return runningApps
        }
        return runningApps.filter {
            $0.localizedName.localizedCaseInsensitiveContains(query) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private func loadAppsForSelectedProfile() {
        if let profile = model.configStore.availableProfiles.first(where: { $0.name == selectedProfileName }) {
            associatedApps = profile.targetApps
        } else if selectedProfileName == model.configStore.activeProfileName {
            associatedApps = model.configStore.targetApps
        } else {
            associatedApps = []
        }
    }

    private func removeApp(_ app: String) {
        associatedApps.removeAll { $0 == app }
    }

    private func addManualApp() {
        let trimmed = manualAppInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !associatedApps.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            associatedApps.append(trimmed)
        }
        manualAppInput = ""
    }

    private func browseForApplication() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                if !associatedApps.contains(where: { $0.caseInsensitiveCompare(bundleId) == .orderedSame }) {
                    associatedApps.append(bundleId)
                }
            } else {
                let appName = url.deletingPathExtension().lastPathComponent
                if !associatedApps.contains(where: { $0.caseInsensitiveCompare(appName) == .orderedSame }) {
                    associatedApps.append(appName)
                }
            }
        }
    }

    private func refreshRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningAppItem? in
                guard let bid = app.bundleIdentifier, !bid.isEmpty else { return nil }
                let name = app.localizedName ?? bid
                return RunningAppItem(id: bid, bundleIdentifier: bid, localizedName: name, icon: app.icon)
            }

        var seen = Set<String>()
        var unique: [RunningAppItem] = []
        for app in apps {
            if !seen.contains(app.bundleIdentifier) {
                seen.insert(app.bundleIdentifier)
                unique.append(app)
            }
        }
        runningApps = unique.sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
    }

    private func isAppAssociated(_ app: RunningAppItem) -> Bool {
        associatedApps.contains { target in
            target.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame ||
            target.caseInsensitiveCompare(app.localizedName) == .orderedSame
        }
    }

    private func toggleApp(_ app: RunningAppItem, isSelected: Bool) {
        if isSelected {
            if !isAppAssociated(app) {
                associatedApps.append(app.bundleIdentifier)
            }
        } else {
            associatedApps.removeAll {
                $0.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame ||
                $0.caseInsensitiveCompare(app.localizedName) == .orderedSame
            }
        }
    }

    private func profileAssigned(for app: RunningAppItem) -> String? {
        let nonDefaultProfiles = model.configStore.availableProfiles.filter { !$0.isDefault }
        for profile in nonDefaultProfiles {
            if profile.targetApps.contains(where: {
                $0.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame ||
                $0.caseInsensitiveCompare(app.localizedName) == .orderedSame
            }) {
                return profile.name
            }
        }
        if let defaultProfile = model.configStore.availableProfiles.first(where: { $0.isDefault }),
           defaultProfile.targetApps.contains(where: {
               $0.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame ||
               $0.caseInsensitiveCompare(app.localizedName) == .orderedSame
           }) {
            return defaultProfile.name
        }
        return nil
    }

    private func saveAndDismiss() {
        model.updateTargetApps(for: selectedProfileName, apps: associatedApps)
        dismiss()
    }
}
