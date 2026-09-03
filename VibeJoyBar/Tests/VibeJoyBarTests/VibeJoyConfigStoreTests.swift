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
}
