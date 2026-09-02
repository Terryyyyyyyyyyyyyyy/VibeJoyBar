import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemService {
    private(set) var isEnabled = false
    private(set) var statusMessage = ""

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                statusMessage = "已设为登录时启动"
            } else {
                try SMAppService.mainApp.unregister()
                statusMessage = "已关闭登录时启动"
            }
            refresh()
        } catch {
            refresh()
            statusMessage = "设置失败：\(error.localizedDescription)"
        }
    }
}
