import XCTest
@testable import VibeJoyBar

final class VibeJoyConfigStoreTests: XCTestCase {
    func testApprovedMappingDefaults() {
        XCTAssertEqual(MappingDefaults.action(for: .button("a")), "tap:enter")
        XCTAssertEqual(MappingDefaults.action(for: .button("b")), "tap:escape")
        XCTAssertEqual(MappingDefaults.action(for: .button("x")), "combo:option+0")
        XCTAssertEqual(MappingDefaults.action(for: .button("y")), "combo:option+1")
        XCTAssertEqual(MappingDefaults.action(for: .button("r")), "combo:option+2")
        XCTAssertEqual(MappingDefaults.action(for: .button("zr")), "app_switcher:system")
        XCTAssertEqual(MappingDefaults.action(for: .button("plus")), "combo:cmd+s")
        XCTAssertEqual(MappingDefaults.action(for: .button("home")), "window_switch:com.openai.codex")
        XCTAssertEqual(MappingDefaults.action(for: .button("r-stick")), "none")
        XCTAssertEqual(MappingDefaults.action(for: .stick("up")), "macro:codex_page_up")
        XCTAssertEqual(MappingDefaults.action(for: .stick("down")), "macro:codex_page_down")
        XCTAssertEqual(MappingDefaults.action(for: .stick("left")), "macro:codex_previous_thread")
        XCTAssertEqual(MappingDefaults.action(for: .stick("right")), "macro:codex_next_thread")
    }

    @MainActor
    func testParsesAndRendersRightBindingsWithoutTouchingOtherSections() throws {
        let source = """
        [global]
        poll_hz = 100

        [profile.right.buttons]
        x       = "combo:cmd+z" # keep comment
        "r-stick" = "tap:tab"

        [profile.left.buttons]
        minus = "combo:cmd+z"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = VibeJoyConfigStore(configURL: url)
        let xIndex = try XCTUnwrap(store.bindings.firstIndex(where: { $0.button == "x" }))
        store.setAction("combo:option+0", at: xIndex)
        let rendered = try store.renderedText()

        XCTAssertTrue(rendered.contains("x       = \"combo:option+0\" # keep comment"))
        XCTAssertTrue(rendered.contains("[profile.left.buttons]"))
        XCTAssertTrue(rendered.contains("minus = \"combo:cmd+z\""))
    }

    @MainActor
    func testEditsStickAndDeadzoneWhileKeepingCommentsAndOtherProfiles() throws {
        let source = """
        # keep this header
        [global]
        deadzone = 0.35 # drift safety
        poll_hz = 100

        [profile.right.buttons]
        a = "tap:enter"

        [profile.right.stick]
        up = "none" # intentionally safe
        down = "none"
        left = "none"
        right = "none"

        [macro.keep]
        steps = ["tap:a"]
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = VibeJoyConfigStore(configURL: url)
        XCTAssertEqual(store.deadzone, 0.35, accuracy: 0.001)
        XCTAssertEqual(store.stickBindings.first(where: { $0.direction == "up" })?.action, "macro:codex_page_up")
        store.setDeadzone(0.42)
        let upIndex = try XCTUnwrap(store.stickBindings.firstIndex(where: { $0.direction == "up" }))
        store.setStickAction("tap:up", at: upIndex)

        let rendered = try store.renderedText()
        XCTAssertTrue(rendered.contains("deadzone = 0.42   # drift safety"))
        XCTAssertTrue(rendered.contains("up = \"tap:up\" # intentionally safe"))
        XCTAssertTrue(rendered.contains("# keep this header"))
        XCTAssertTrue(rendered.contains("[macro.keep]"))
        XCTAssertTrue(rendered.contains("steps = [\"tap:a\"]"))
    }

    @MainActor
    func testMigratesOnlyLegacyHomeAndZRDefaults() throws {
        let source = """
        [profile.right.buttons]
        zr = "window_switch:Codex,Google Chrome,Safari,Visual Studio Code"
        home = "window_switch:Codex"
        x = "window_switch:Codex"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = VibeJoyConfigStore(configURL: url)
        XCTAssertEqual(store.bindings.first(where: { $0.button == "zr" })?.action, "app_switcher:system")
        XCTAssertEqual(store.bindings.first(where: { $0.button == "home" })?.action, "window_switch:com.openai.codex")
        XCTAssertEqual(store.bindings.first(where: { $0.button == "x" })?.action, "window_switch:Codex")
        let migrated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(migrated.contains("zr = \"app_switcher:system\""))
        XCTAssertTrue(migrated.contains("home = \"window_switch:com.openai.codex\""))
        XCTAssertTrue(migrated.contains("x = \"window_switch:Codex\""))
    }

    @MainActor
    func testMigratesDisabledStickDefaultsToCodexNavigation() throws {
        let source = """
        [profile.right.buttons]
        a = "tap:enter"

        [profile.right.stick]
        up = "none"
        down = "none"
        left = "none"
        right = "none"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = VibeJoyConfigStore(configURL: url)
        XCTAssertEqual(store.stickBindings.first(where: { $0.direction == "up" })?.action, "macro:codex_page_up")
        XCTAssertEqual(store.stickBindings.first(where: { $0.direction == "right" })?.action, "macro:codex_next_thread")
        let migrated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(migrated.contains("[macro.codex_page_up]"))
        XCTAssertTrue(migrated.contains("steps = [\"scroll:up@8\"]"))
        XCTAssertTrue(migrated.contains("steps = [\"combo:cmd+shift+]\"]"))
    }

    @MainActor
    func testPreservesCustomStickMappingsDuringCodexMigration() throws {
        let source = """
        [profile.right.stick]
        up = "tap:home"
        down = "none"
        left = "none"
        right = "none"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = VibeJoyConfigStore(configURL: url)
        XCTAssertEqual(store.stickBindings.first(where: { $0.direction == "up" })?.action, "tap:home")
        XCTAssertEqual(store.stickBindings.first(where: { $0.direction == "down" })?.action, "macro:codex_page_down")
    }

    @MainActor
    func testMigratesExistingPageMacrosWithoutChangingCustomSteps() throws {
        let source = """
        [profile.right.stick]
        up = "macro:codex_page_up"
        down = "macro:codex_page_down"

        [macro.codex_page_up]
        if_app = "com.openai.codex"
        steps = ["tap:page_up"]

        [macro.custom]
        steps = ["tap:page_up", "tap:enter"]
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = VibeJoyConfigStore(configURL: url)
        let migrated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(store.action(for: .stick("up")), "macro:codex_page_up")
        XCTAssertTrue(migrated.contains("steps = [\"scroll:up@8\"]"))
        XCTAssertTrue(migrated.contains("steps = [\"tap:page_up\", \"tap:enter\"]"))
    }

    @MainActor
    func testResetToDefaultProfileCreatesBackupAndRestoresBaseline() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        let customSource = """
        [global]
        deadzone = 0.50
        poll_hz = 60

        [profile.right.buttons]
        a = "combo:cmd+c"
        b = "combo:cmd+v"
        """
        try customSource.write(to: configURL, atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        XCTAssertEqual(store.action(for: .button("a")), "combo:cmd+c")
        XCTAssertEqual(store.action(for: .button("b")), "combo:cmd+v")

        try store.resetToDefaultProfile(createBackup: true)

        let backupsDir = tempDir.appendingPathComponent("backups")
        let backupFiles = try FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(backupFiles.count, 1)
        let backupContent = try String(contentsOf: backupFiles[0], encoding: .utf8)
        XCTAssertTrue(backupContent.contains("combo:cmd+c"))

        XCTAssertEqual(store.action(for: .button("a")), "tap:enter")
        XCTAssertEqual(store.action(for: .button("b")), "tap:escape")
        XCTAssertEqual(store.action(for: .button("zr")), "app_switcher:system")
        XCTAssertEqual(store.action(for: .button("home")), "window_switch:com.openai.codex")
        XCTAssertEqual(store.action(for: .stick("up")), "macro:codex_page_up")
        XCTAssertEqual(store.action(for: .stick("down")), "macro:codex_page_down")
        XCTAssertEqual(store.action(for: .stick("left")), "macro:codex_previous_thread")
        XCTAssertEqual(store.action(for: .stick("right")), "macro:codex_next_thread")
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    @MainActor
    func testProfileScanningAndSorting() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let profilesDir = tempDir.appendingPathComponent("profiles")
        try FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        try "dummy".write(to: profilesDir.appendingPathComponent("default.toml"), atomically: true, encoding: .utf8)
        try "dummy".write(to: profilesDir.appendingPathComponent("gaming.toml"), atomically: true, encoding: .utf8)
        try "dummy".write(to: profilesDir.appendingPathComponent("browser.toml"), atomically: true, encoding: .utf8)
        try "dummy".write(to: profilesDir.appendingPathComponent("alpha.toml"), atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        let names = store.availableProfiles.map(\.name)
        XCTAssertEqual(names, ["default", "alpha", "browser", "gaming"])
        XCTAssertEqual(store.activeProfileName, "default")
        XCTAssertTrue(store.availableProfiles[0].isActive)
        XCTAssertTrue(store.availableProfiles[0].isDefault)
    }

    @MainActor
    func testSaveAsNewProfile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        let aIndex = try XCTUnwrap(store.bindings.firstIndex(where: { $0.button == "a" }))
        store.setAction("combo:cmd+t", at: aIndex)

        // Invalid names should throw
        XCTAssertThrowsError(try store.saveAsNewProfile(named: ""))
        XCTAssertThrowsError(try store.saveAsNewProfile(named: "   "))
        XCTAssertThrowsError(try store.saveAsNewProfile(named: "../evil"))
        XCTAssertThrowsError(try store.saveAsNewProfile(named: ".hidden"))

        // Save as valid profile
        try store.saveAsNewProfile(named: "coding")
        XCTAssertEqual(store.activeProfileName, "coding")

        let profilesDir = tempDir.appendingPathComponent("profiles")
        let codingURL = profilesDir.appendingPathComponent("coding.toml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: codingURL.path))
        let savedContent = try String(contentsOf: codingURL, encoding: .utf8)
        XCTAssertTrue(savedContent.contains("\"combo:cmd+t\""))

        let activeProfileFile = tempDir.appendingPathComponent("active_profile")
        let activeContent = try String(contentsOf: activeProfileFile, encoding: .utf8)
        XCTAssertEqual(activeContent, "coding")

        let activeItem = try XCTUnwrap(store.availableProfiles.first(where: { $0.name == "coding" }))
        XCTAssertTrue(activeItem.isActive)
        XCTAssertFalse(activeItem.isDefault)
    }

    @MainActor
    func testSwitchProfileWithBackup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        let aIndex = try XCTUnwrap(store.bindings.firstIndex(where: { $0.button == "a" }))
        store.setAction("combo:cmd+n", at: aIndex)
        try store.saveAsNewProfile(named: "browsing")

        // Now switch back to default
        try store.switchToProfile(named: "default")
        XCTAssertEqual(store.activeProfileName, "default")
        XCTAssertEqual(store.action(for: .button("a")), "tap:enter")

        // Verify backup was made during switch
        let backupsDir = tempDir.appendingPathComponent("backups")
        let backups = try FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)
        XCTAssertFalse(backups.isEmpty)

        // Switching to non-existent profile throws
        XCTAssertThrowsError(try store.switchToProfile(named: "non_existent"))
    }

    @MainActor
    func testSafeProfileDeletion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        try store.saveAsNewProfile(named: "temp_profile")
        XCTAssertEqual(store.activeProfileName, "temp_profile")

        // Deleting default must fail
        XCTAssertThrowsError(try store.deleteProfile(named: "default"))

        // Deleting active profile must switch back to default and delete file
        try store.deleteProfile(named: "temp_profile")
        XCTAssertEqual(store.activeProfileName, "default")
        let profilePath = tempDir.appendingPathComponent("profiles/temp_profile.toml").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: profilePath))

        // Deleting non-existent profile throws
        XCTAssertThrowsError(try store.deleteProfile(named: "temp_profile"))
    }

    @MainActor
    func testParsesAndRendersLeftBindings() throws {
        let source = """
        [global]
        poll_hz = 100

        [profile.left.buttons]
        minus = "combo:cmd+z"
        capture = "combo:cmd+shift+3"

        [profile.left.stick]
        up = "macro:codex_page_up"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = VibeJoyConfigStore(configURL: url)
        XCTAssertEqual(store.action(for: .button("minus"), side: .left), "combo:cmd+z")
        XCTAssertEqual(store.action(for: .button("capture"), side: .left), "combo:cmd+shift+3")
        XCTAssertEqual(store.action(for: .stick("up"), side: .left), "macro:codex_page_up")

        store.setAction("tap:enter", for: .button("l"), side: .left)
        let rendered = try store.renderedText()
        XCTAssertTrue(rendered.contains("[profile.left.buttons]"))
        XCTAssertTrue(rendered.contains("minus = \"combo:cmd+z\""))
        XCTAssertTrue(rendered.contains("l         = \"tap:enter\""))
    }

    func testControllerBatterySymbolNames() {
        let charging = ControllerBattery(level: 2, percentage: 50, isCharging: true)
        XCTAssertEqual(charging.symbolName, "battery.100.bolt")

        let bat100 = ControllerBattery(level: 4, percentage: 100, isCharging: false)
        XCTAssertEqual(bat100.symbolName, "battery.100")

        let bat88 = ControllerBattery(level: 4, percentage: 88, isCharging: false)
        XCTAssertEqual(bat88.symbolName, "battery.100")

        let bat75 = ControllerBattery(level: 3, percentage: 75, isCharging: false)
        XCTAssertEqual(bat75.symbolName, "battery.75")

        let bat63 = ControllerBattery(level: 3, percentage: 63, isCharging: false)
        XCTAssertEqual(bat63.symbolName, "battery.75")

        let bat50 = ControllerBattery(level: 2, percentage: 50, isCharging: false)
        XCTAssertEqual(bat50.symbolName, "battery.50")

        let bat38 = ControllerBattery(level: 2, percentage: 38, isCharging: false)
        XCTAssertEqual(bat38.symbolName, "battery.50")

        let bat25 = ControllerBattery(level: 1, percentage: 25, isCharging: false)
        XCTAssertEqual(bat25.symbolName, "battery.25")

        let bat13 = ControllerBattery(level: 1, percentage: 13, isCharging: false)
        XCTAssertEqual(bat13.symbolName, "battery.25")

        let bat0 = ControllerBattery(level: 0, percentage: 5, isCharging: false)
        XCTAssertEqual(bat0.symbolName, "battery.0")

        let batDead = ControllerBattery(level: 0, percentage: 0, isCharging: false)
        XCTAssertEqual(batDead.symbolName, "battery.0")
    }

    func testControllerBatteryLowBattery() {
        let low = ControllerBattery(level: 0, percentage: 5, isCharging: false)
        XCTAssertTrue(low.isLowBattery)

        let low20 = ControllerBattery(level: 1, percentage: 20, isCharging: false)
        XCTAssertTrue(low20.isLowBattery)

        let lowCharging = ControllerBattery(level: 0, percentage: 5, isCharging: true)
        XCTAssertFalse(lowCharging.isLowBattery)

        let normal = ControllerBattery(level: 1, percentage: 25, isCharging: false)
        XCTAssertFalse(normal.isLowBattery)
    }

    @MainActor
    func testActiveControllerSideAutoLock() {
        let model = AppModel.shared
        XCTAssertNotNil(model.activeControllerSide)
        model.activeControllerSide = .left
        XCTAssertEqual(model.activeControllerSide, .left)
        model.activeControllerSide = .right
        XCTAssertEqual(model.activeControllerSide, .right)
    }

    @MainActor
    func testParseTargetAppsFromMetaSection() {
        let multiAppText = """
        [meta]
        description = "开发方案"
        apps = ["com.apple.dt.Xcode", "com.microsoft.VSCode"]

        [global]
        deadzone = 0.2
        """
        let parsed = VibeJoyConfigStore.parseTargetApps(from: multiAppText)
        XCTAssertEqual(parsed, ["com.apple.dt.Xcode", "com.microsoft.VSCode"])

        let singleAppText = """
        [meta]
        apps = "com.apple.Safari"
        """
        XCTAssertEqual(VibeJoyConfigStore.parseTargetApps(from: singleAppText), ["com.apple.Safari"])

        let emptyAppsText = """
        [meta]
        apps = []
        """
        XCTAssertEqual(VibeJoyConfigStore.parseTargetApps(from: emptyAppsText), [])

        let noMetaText = """
        [global]
        deadzone = 0.2
        """
        XCTAssertEqual(VibeJoyConfigStore.parseTargetApps(from: noMetaText), [])
    }

    @MainActor
    func testRenderTargetAppsIntoMetaSection() {
        let initialText = """
        [global]
        deadzone = 0.2
        """
        let rendered = VibeJoyConfigStore.renderTargetApps(["com.apple.dt.Xcode", "com.openai.codex"], in: initialText)
        XCTAssertTrue(rendered.contains("[meta]"))
        XCTAssertTrue(rendered.contains("apps = [\"com.apple.dt.Xcode\", \"com.openai.codex\"]"))

        let existingMetaText = """
        [meta]
        description = "My profile"
        apps = ["old.app"]

        [global]
        deadzone = 0.2
        """
        let updated = VibeJoyConfigStore.renderTargetApps(["new.app"], in: existingMetaText)
        XCTAssertTrue(updated.contains("description = \"My profile\""))
        XCTAssertTrue(updated.contains("apps = [\"new.app\"]"))
        XCTAssertFalse(updated.contains("old.app"))
    }

    @MainActor
    func testUpdateTargetAppsForProfile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        try store.saveAsNewProfile(named: "coding")

        try store.updateTargetApps(for: "coding", apps: ["com.openai.codex", "Visual Studio Code"])

        let profileItem = try XCTUnwrap(store.availableProfiles.first(where: { $0.name == "coding" }))
        XCTAssertEqual(profileItem.targetApps, ["com.openai.codex", "Visual Studio Code"])

        let codingFile = tempDir.appendingPathComponent("profiles/coding.toml")
        let content = try String(contentsOf: codingFile, encoding: .utf8)
        XCTAssertTrue(content.contains("apps = [\"com.openai.codex\", \"Visual Studio Code\"]"))
    }

    @MainActor
    func testAutoSwitchDoesNotCreateBackup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        try store.saveAsNewProfile(named: "gaming")

        let backupsDir = tempDir.appendingPathComponent("backups")
        if FileManager.default.fileExists(atPath: backupsDir.path) {
            let files = try FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
        }

        // Auto switch should not generate backup
        try store.switchToProfile(named: "default", isAutoSwitch: true)
        XCTAssertEqual(store.activeProfileName, "default")

        let backupsAfterAuto = (try? FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(backupsAfterAuto.isEmpty)

        // Manual switch should generate backup
        try store.switchToProfile(named: "gaming", isAutoSwitch: false)
        XCTAssertEqual(store.activeProfileName, "gaming")
        let backupsAfterManual = try FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)
        XCTAssertFalse(backupsAfterManual.isEmpty)
    }

    @MainActor
    func testAppRouterMatching() {
        let dummyURL = URL(fileURLWithPath: "/dummy")
        let profiles: [ProfileItem] = [
            ProfileItem(name: "coding", isDefault: false, isActive: false, fileURL: dummyURL, targetApps: ["com.openai.codex", "Visual Studio Code"]),
            ProfileItem(name: "browser", isDefault: false, isActive: false, fileURL: dummyURL, targetApps: ["com.apple.Safari"]),
            ProfileItem(name: "default", isDefault: true, isActive: true, fileURL: dummyURL, targetApps: [])
        ]

        let match1 = AppRouterService.matchProfile(bundleId: "com.openai.codex", appName: "ChatGPT", in: profiles)
        XCTAssertEqual(match1, "coding")

        let match2 = AppRouterService.matchProfile(bundleId: "com.apple.Safari", appName: "Safari", in: profiles)
        XCTAssertEqual(match2, "browser")

        let match3 = AppRouterService.matchProfile(bundleId: "COM.APPLE.SAFARI", appName: "Safari", in: profiles)
        XCTAssertEqual(match3, "browser")

        let match4 = AppRouterService.matchProfile(bundleId: "com.random.unknown", appName: "Visual Studio Code", in: profiles)
        XCTAssertEqual(match4, "coding")

        let match5 = AppRouterService.matchProfile(bundleId: "com.spotify.client", appName: "Spotify", in: profiles)
        XCTAssertEqual(match5, "default")
    }

    @MainActor
    func testCrossProfileAppDeduplication() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        try store.saveAsNewProfile(named: "profileA")
        try store.updateTargetApps(for: "profileA", apps: ["com.openai.codex", "com.apple.Safari"])

        let itemA = try XCTUnwrap(store.availableProfiles.first(where: { $0.name == "profileA" }))
        XCTAssertEqual(itemA.targetApps, ["com.openai.codex", "com.apple.Safari"])

        // Now profileB claims com.openai.codex
        try store.saveAsNewProfile(named: "profileB")
        try store.updateTargetApps(for: "profileB", apps: ["com.openai.codex", "com.google.Chrome"])

        // Refresh and check profileA: com.openai.codex must have been stripped
        store.refreshProfiles()
        let updatedA = try XCTUnwrap(store.availableProfiles.first(where: { $0.name == "profileA" }))
        XCTAssertEqual(updatedA.targetApps, ["com.apple.Safari"])

        let updatedB = try XCTUnwrap(store.availableProfiles.first(where: { $0.name == "profileB" }))
        XCTAssertEqual(updatedB.targetApps, ["com.openai.codex", "com.google.Chrome"])
    }

    @MainActor
    func testAppRouterMatchingPrioritizesNonDefaultOverDefault() {
        let dummyURL = URL(fileURLWithPath: "/dummy")
        let profiles: [ProfileItem] = [
            ProfileItem(name: "default", isDefault: true, isActive: false, fileURL: dummyURL, targetApps: ["com.openai.codex"]),
            ProfileItem(name: "coding", isDefault: false, isActive: false, fileURL: dummyURL, targetApps: ["com.openai.codex"])
        ]

        let matched = AppRouterService.matchProfile(bundleId: "com.openai.codex", appName: "Codex", in: profiles)
        XCTAssertEqual(matched, "coding")
    }

    @MainActor
    func testBindingScopeAndResetToGlobalDefault() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        // 1. In default profile, scope is globalBaseline
        XCTAssertEqual(store.activeProfileName, "default")
        XCTAssertEqual(store.bindingScope(for: .button("a")), .globalBaseline)
        XCTAssertEqual(store.bindingScope(for: .stick("left")), .globalBaseline)

        // 2. Create and switch to subprofile "coding"
        try store.saveAsNewProfile(named: "coding")
        try store.switchToProfile(named: "coding")
        XCTAssertEqual(store.activeProfileName, "coding")

        // Right button 'a' starts out as "tap:enter", matching default
        XCTAssertEqual(store.action(for: .button("a")), "tap:enter")
        XCTAssertEqual(store.bindingScope(for: .button("a")), .inheritedFromGlobal)

        // Override 'a' to "tap:space"
        store.setAction("tap:space", for: .button("a"))
        XCTAssertEqual(store.action(for: .button("a")), "tap:space")
        XCTAssertEqual(store.bindingScope(for: .button("a")), .profileOverride)

        // Reset 'a' to global default
        store.resetToGlobalDefault(selection: .button("a"))
        XCTAssertEqual(store.action(for: .button("a")), "tap:enter")
        XCTAssertEqual(store.bindingScope(for: .button("a")), .inheritedFromGlobal)
    }

    @MainActor
    func testRecommendedGlobalKey() {
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("a")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("b")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("x")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("y")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("r")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("zr")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("plus")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("right")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("down")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("up")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("left")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("l")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("zl")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .button("minus")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .stick("up")))
        XCTAssertTrue(MappingDefaults.isRecommendedGlobalKey(for: .stick("down")))

        // Delta/app-specific keys
        XCTAssertFalse(MappingDefaults.isRecommendedGlobalKey(for: .stick("left")))
        XCTAssertFalse(MappingDefaults.isRecommendedGlobalKey(for: .stick("right")))
        XCTAssertFalse(MappingDefaults.isRecommendedGlobalKey(for: .button("home")))
        XCTAssertFalse(MappingDefaults.isRecommendedGlobalKey(for: .button("capture")))
    }

    @MainActor
    func testLayerParsingAndRendering() throws {
        let source = """
        [global]
        poll_hz = 100

        [profile.right.buttons]
        a = "tap:enter"
        b = "tap:escape"
        sl = "modifier:layer1?tap:space"

        [profile.right.layers.layer1.buttons]
        a = "combo:cmd+c"
        b = "combo:cmd+v"

        [profile.right.layers.layer1.stick]
        up = "tap:page_up"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = VibeJoyConfigStore(configURL: url)
        XCTAssertTrue(store.availableLayers.contains("layer1"))

        // Base layer actions
        XCTAssertEqual(store.action(for: .button("a")), "tap:enter")
        XCTAssertEqual(store.action(for: .button("sl")), "modifier:layer1?tap:space")

        // Layer1 actions
        XCTAssertEqual(store.action(for: .button("a"), layer: "layer1"), "combo:cmd+c")
        XCTAssertEqual(store.action(for: .button("b"), layer: "layer1"), "combo:cmd+v")
        XCTAssertEqual(store.action(for: .stick("up"), layer: "layer1"), "tap:page_up")

        // Unset button in layer1 falls back to base layer
        XCTAssertEqual(store.action(for: .button("x"), layer: "layer1"), store.action(for: .button("x")))

        // Binding scope in layer
        XCTAssertEqual(store.bindingScope(for: .button("a"), layer: "layer1"), .profileOverride)
        XCTAssertEqual(store.bindingScope(for: .button("x"), layer: "layer1"), .inheritedFromGlobal)

        // Modify layer action
        store.setAction("combo:cmd+x", for: .button("a"), layer: "layer1")
        XCTAssertEqual(store.action(for: .button("a"), layer: "layer1"), "combo:cmd+x")

        let rendered = try store.renderedText()
        XCTAssertTrue(rendered.contains("[profile.right.layers.layer1.buttons]"))
        XCTAssertTrue(rendered.contains("a = \"combo:cmd+x\""))
        XCTAssertTrue(rendered.contains("[profile.right.layers.layer1.stick]"))
        XCTAssertTrue(rendered.contains("up = \"tap:page_up\""))

        // Reset layer action
        store.resetToGlobalDefault(selection: .button("a"), layer: "layer1")
        XCTAssertEqual(store.action(for: .button("a"), layer: "layer1"), "tap:enter")
        XCTAssertEqual(store.bindingScope(for: .button("a"), layer: "layer1"), .inheritedFromGlobal)
    }

    @MainActor
    func testHUDFeedbackSetting() {
        let model = AppModel.shared
        let original = model.hudFeedbackEnabled
        defer { model.setHudFeedbackEnabled(original) }

        model.setHudFeedbackEnabled(false)
        XCTAssertFalse(model.hudFeedbackEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppPaths.hudFeedbackKey))

        model.setHudFeedbackEnabled(true)
        XCTAssertTrue(model.hudFeedbackEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppPaths.hudFeedbackKey))
    }

    func testModifierActionSummaryAndPreset() {
        XCTAssertEqual(ActionSummary.text(for: "modifier:layer1"), "物理修饰层 · layer1")
        XCTAssertEqual(ActionSummary.text(for: "modifier:layer1?tap:space"), "物理修饰层 · layer1 (按一下 · SPACE)")

        let preset = MappingPreset.common.first(where: { $0.action.hasPrefix("modifier:") })
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.action, "modifier:layer1")
    }

    func testGlobalLockedKeyAndFreedKey() {
        // Right Joy-Con locked keys: r, x, y, zr, a, b
        let rightLocked: [MappingSelection] = [
            .button("r"), .button("x"), .button("y"), .button("zr"), .button("a"), .button("b")
        ]
        for sel in rightLocked {
            XCTAssertTrue(MappingDefaults.isGlobalLockedKey(for: sel), "Expected \(sel) to be global locked")
            XCTAssertFalse(MappingDefaults.isFreedKey(for: sel), "Expected \(sel) not to be freed")
        }

        // Left Joy-Con locked keys: l, up, left, zl, right, down
        let leftLocked: [MappingSelection] = [
            .button("l"), .button("up"), .button("left"), .button("zl"), .button("right"), .button("down")
        ]
        for sel in leftLocked {
            XCTAssertTrue(MappingDefaults.isGlobalLockedKey(for: sel), "Expected \(sel) to be global locked")
            XCTAssertFalse(MappingDefaults.isFreedKey(for: sel), "Expected \(sel) not to be freed")
        }

        // Freed keys: stick directions, plus, minus, home, capture, sl, sr, r-stick, l-stick
        let freedSelections: [MappingSelection] = [
            .stick("up"), .stick("down"), .stick("left"), .stick("right"),
            .button("plus"), .button("minus"), .button("home"), .button("capture"),
            .button("sl"), .button("sr"), .button("r-stick"), .button("l-stick")
        ]
        for sel in freedSelections {
            XCTAssertTrue(MappingDefaults.isFreedKey(for: sel), "Expected \(sel) to be freed")
            XCTAssertFalse(MappingDefaults.isGlobalLockedKey(for: sel), "Expected \(sel) not to be locked")
        }
    }

    func testShortcutKeyModelParsingAndFormatting() {
        // 1. Combo with multiple modifiers
        let combo1 = ShortcutKeyModel.parse(dsl: "combo:cmd+shift+p")
        XCTAssertNotNil(combo1)
        XCTAssertEqual(combo1?.modifiers, [.command, .shift])
        XCTAssertEqual(combo1?.key, "p")
        XCTAssertEqual(combo1?.dsl, "combo:cmd+shift+p")
        XCTAssertEqual(combo1?.displayKeySymbol, "P")

        // 2. Single tap with space
        let tapSpace = ShortcutKeyModel.parse(dsl: "tap:space")
        XCTAssertNotNil(tapSpace)
        XCTAssertEqual(tapSpace?.modifiers, [])
        XCTAssertEqual(tapSpace?.key, "space")
        XCTAssertEqual(tapSpace?.dsl, "tap:space")
        XCTAssertEqual(tapSpace?.displayKeySymbol, "␣ Space")

        // 3. Return / Enter
        let tapEnter = ShortcutKeyModel.parse(dsl: "tap:enter")
        XCTAssertNotNil(tapEnter)
        XCTAssertEqual(tapEnter?.displayKeySymbol, "⏎ Return")
        XCTAssertEqual(tapEnter?.dsl, "tap:enter")

        // 4. Escape
        let tapEsc = ShortcutKeyModel.parse(dsl: "tap:escape")
        XCTAssertNotNil(tapEsc)
        XCTAssertEqual(tapEsc?.displayKeySymbol, "⎋ Esc")
        XCTAssertEqual(tapEsc?.dsl, "tap:escape")

        // 5. Option + 2 (Type4Me Prompt)
        let type4me = ShortcutKeyModel.parse(dsl: "combo:option+2")
        XCTAssertNotNil(type4me)
        XCTAssertEqual(type4me?.modifiers, [.option])
        XCTAssertEqual(type4me?.key, "2")
        XCTAssertEqual(type4me?.dsl, "combo:option+2")

        // 6. None / empty
        XCTAssertNil(ShortcutKeyModel.parse(dsl: "none"))
        XCTAssertNil(ShortcutKeyModel.parse(dsl: ""))
        let emptyModel = ShortcutKeyModel(modifiers: [], key: "")
        XCTAssertEqual(emptyModel.dsl, "none")

        // 7. Programmatic construction and modifier ordering
        let customModel = ShortcutKeyModel(modifiers: [.shift, .command, .control], key: "k")
        XCTAssertEqual(customModel.dsl, "combo:cmd+ctrl+shift+k")

        // 8. Hold and Repeat trigger styles
        let holdSpace = ShortcutKeyModel.parse(dsl: "hold:space")
        XCTAssertNotNil(holdSpace)
        XCTAssertEqual(holdSpace?.triggerStyle, .hold)
        XCTAssertEqual(holdSpace?.dsl, "hold:space")

        let repeatUp = ShortcutKeyModel.parse(dsl: "repeat:up@100")
        XCTAssertNotNil(repeatUp)
        XCTAssertEqual(repeatUp?.triggerStyle, .repeat)
        XCTAssertEqual(repeatUp?.key, "up")
        XCTAssertEqual(repeatUp?.dsl, "repeat:up")

        let manualRepeat = ShortcutKeyModel(modifiers: [], key: "down", triggerStyle: .repeat)
        XCTAssertEqual(manualRepeat.dsl, "repeat:down")
    }

    @MainActor
    func testCascadingInheritanceFromDefaultProfile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let store = VibeJoyConfigStore(configURL: configURL)
        // In default, R is combo:option+2
        XCTAssertEqual(store.action(for: .button("r")), "combo:option+2")

        // Save as new subprofile "work"
        try store.saveAsNewProfile(named: "work")
        XCTAssertEqual(store.activeProfileName, "work")
        XCTAssertEqual(store.action(for: .button("r")), "combo:option+2")
        XCTAssertEqual(store.bindingScope(for: .button("r")), .inheritedFromGlobal)

        // Switch to default and update R to tap:f18
        try store.switchToProfile(named: "default")
        let rIndex = try XCTUnwrap(store.bindings.firstIndex(where: { $0.button == "r" }))
        store.setAction("tap:f18", at: rIndex)
        try store.commit(try store.renderedText())
        XCTAssertEqual(store.action(for: .button("r")), "tap:f18")

        // Switch back to "work" - R should dynamically inherit tap:f18 from default.toml!
        try store.switchToProfile(named: "work")
        XCTAssertEqual(store.activeProfileName, "work")
        XCTAssertEqual(store.action(for: .button("r")), "tap:f18")
        XCTAssertEqual(store.bindingScope(for: .button("r")), .inheritedFromGlobal)
    }

    @MainActor
    func testUnsavedEditsProtectionDuringAutoSwitch() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.toml")
        try VibeJoyConfigStore.fallbackDefaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let model = AppModel.shared
        model.configStore.updateURL(configURL)
        try model.configStore.saveAsNewProfile(named: "browsing")
        XCTAssertEqual(model.configStore.activeProfileName, "browsing")

        // Simulate user making an uncommitted edit
        let aIndex = try XCTUnwrap(model.configStore.bindings.firstIndex(where: { $0.button == "a" }))
        model.configStore.setAction("combo:cmd+t", at: aIndex)
        XCTAssertTrue(model.configStore.hasUnsavedChanges)

        // When auto switch is triggered, it MUST be suppressed to protect user edits
        model.switchToProfile(named: "default", isAutoSwitch: true)
        XCTAssertEqual(model.configStore.activeProfileName, "browsing")
        XCTAssertTrue(model.configStore.hasUnsavedChanges)
        XCTAssertEqual(model.configStore.action(for: .button("a")), "combo:cmd+t")
        XCTAssertTrue(model.activityMessage.contains("已保留未保存的映射编辑"))
    }

    func testAppVersionAndBuildDefaultValues() {
        XCTAssertEqual(AppPaths.appVersion, "0.9.9")
        XCTAssertEqual(AppPaths.appBuild, "10")
        XCTAssertEqual(AppPaths.versionString, "v0.9.9")
    }

    @MainActor
    func testProcessServicePhaseTransitions() {
        let service = VibeJoyProcessService(
            projectURL: URL(fileURLWithPath: "/tmp"),
            uvURL: URL(fileURLWithPath: "/tmp/uv")
        )

        // Initial state
        XCTAssertEqual(service.phase, .stopped)

        // Connect right controller
        service.consume("vibejoy ▶ connected: right")
        XCTAssertEqual(service.connectedSides, ["right"])
        XCTAssertEqual(service.phase, .running("右手柄"))

        // Connect left controller (dual mode)
        service.consume("vibejoy ▶ connected: left")
        XCTAssertEqual(service.connectedSides, ["left", "right"])
        XCTAssertEqual(service.phase, .running("双持"))

        // Disconnect right controller
        service.consume("vibejoy ▶ disconnected: right; waiting for reconnect")
        XCTAssertEqual(service.connectedSides, ["left"])
        XCTAssertEqual(service.phase, .running("左手柄"))

        // Disconnect left controller -> should transition to waitingForController
        service.consume("vibejoy ▶ disconnected: left; waiting for reconnect")
        XCTAssertEqual(service.connectedSides, [])
        XCTAssertEqual(service.phase, .waitingForController)

        // Empty sides with nil line also updates to waitingForController
        service.updatePhaseFromConnectedSides()
        XCTAssertEqual(service.phase, .waitingForController)
    }

    @MainActor
    func testHUDControllerWakePresentation() {
        HUDFeedbackService.shared.showControllerWake(
            sides: ["right"],
            batteries: [.right: ControllerBattery(level: 4, percentage: 100, isCharging: false)]
        )
        // Verify dual wake as well
        HUDFeedbackService.shared.showControllerWake(
            sides: ["left", "right"],
            batteries: [
                .left: ControllerBattery(level: 3, percentage: 75, isCharging: false),
                .right: ControllerBattery(level: 4, percentage: 100, isCharging: false)
            ]
        )
    }
}
