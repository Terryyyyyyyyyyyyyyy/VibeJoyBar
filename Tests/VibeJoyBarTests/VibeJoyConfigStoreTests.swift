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
        XCTAssertTrue(migrated.contains("steps = [\"tap:page_up\"]"))
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
}
