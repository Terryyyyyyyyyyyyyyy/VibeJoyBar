import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.startOnLaunchIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.processService.terminateForShutdown()
    }
}

@main
struct VibeJoyBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Label("VibeJoy", systemImage: model.processService.phase.symbolName)
        }
        .menuBarExtraStyle(.menu)

        Window("VibeJoy 映射", id: "mapper") {
            MapperView(model: model)
        }
        .defaultSize(width: 1180, height: 760)

        Window("VibeJoy 日志", id: "logs") {
            LogsView(model: model)
        }
        .defaultSize(width: 760, height: 460)

        Settings {
            SettingsView(model: model)
        }
    }
}
