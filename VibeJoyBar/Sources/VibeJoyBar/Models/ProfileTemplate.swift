import Foundation
import SwiftUI

public struct ProfileTemplate: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let tintColorHex: String
    public let targetApps: [String]
    public let highlights: [String]
    public let tomlContent: String

    public var tintColor: Color {
        Color(hex: tintColorHex)
    }

    public static let allTemplates: [ProfileTemplate] = [
        .init(
            id: "vscode",
            title: "VS Code & Cursor",
            subtitle: "主流代码编辑器高效开发方案",
            icon: "chevron.left.forwardslash.chevron.right",
            tintColorHex: "#007ACC",
            targetApps: [
                "com.microsoft.VSCode",
                "com.microsoft.VSCodeInsiders",
                "com.todesktop.230313mzl4w4u92",
                "com.cursor.Cursor"
            ],
            highlights: ["摇杆切标签", "SL 打开终端", "SR 转到定义", "🔒 Type4Me 全局锁"],
            tomlContent: """
            # VibeJoy — VS Code & Cursor Profile
            # 主流代码编辑器高效开发方案

            [meta]
            description = "VS Code & Cursor 专属方案"
            apps = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"]

            [global]
            deadzone       = 0.2
            poll_hz        = 100
            long_press_ms  = 250
            stick_mode     = "4dir"

            # ─────────── Right Joy-Con ───────────

            [profile.right.buttons]
            a       = "tap:enter"                       # 确定
            b       = "tap:escape"                      # 取消 / 退出
            x       = "combo:option+0"                  # Type4Me 麦克风 1
            y       = "combo:option+1"                  # Type4Me 麦克风 2
            r       = "combo:option+2"                  # Type4Me Prompt 优化
            zr      = "app_switcher:system"             # 系统应用轮播切换
            plus    = "combo:cmd+s"                     # 保存文件
            home    = "combo:cmd+shift+p"               # 命令面板
            sl      = "combo:ctrl+grave"                # 切换集成终端
            sr      = "tap:f12"                         # 转到定义
            "r-stick" = "combo:cmd+."                   # 快速修复 / 建议

            [profile.right.stick]
            up      = "macro:codex_page_up"             # 向上滚动
            down    = "macro:codex_page_down"           # 向下滚动
            left    = "combo:cmd+alt+left"              # 切换至左侧标签页
            right   = "combo:cmd+alt+right"             # 切换至右侧标签页

            # ─────────── Left Joy-Con ───────────

            [profile.left.buttons]
            right   = "tap:enter"                       # 对应 A
            down    = "tap:escape"                      # 对应 B
            up      = "combo:option+0"                  # 对应 X
            left    = "combo:option+1"                  # 对应 Y
            l       = "combo:option+2"                  # 对应 R
            zl      = "app_switcher:system"             # 对应 ZR
            minus   = "combo:cmd+s"                     # 对应 +
            capture = "combo:cmd+shift+p"               # 对应 Home
            sl      = "combo:ctrl+grave"                # 切换集成终端
            sr      = "tap:f12"                         # 转到定义
            "l-stick" = "combo:cmd+."                   # 快速修复 / 建议

            [profile.left.stick]
            up      = "macro:codex_page_up"             # 向上滚动
            down    = "macro:codex_page_down"           # 向下滚动
            left    = "combo:cmd+alt+left"              # 切换至左侧标签页
            right   = "combo:cmd+alt+right"             # 切换至右侧标签页

            # ─────────── Macros ───────────

            [macro.codex_page_up]
            steps   = ["scroll:up@8"]

            [macro.codex_page_down]
            steps   = ["scroll:down@8"]
            """
        ),
        .init(
            id: "xcode",
            title: "Apple Xcode",
            subtitle: "macOS / iOS 极速原生工程构建",
            icon: "hammer.fill",
            tintColorHex: "#147EFB",
            targetApps: [
                "com.apple.dt.Xcode"
            ],
            highlights: ["摇杆切问题/文件", "SL 运行测试", "SR 报错跳转", "🔒 Type4Me 全局锁"],
            tomlContent: """
            # VibeJoy — Xcode Profile
            # macOS / iOS 原生开发方案

            [meta]
            description = "Xcode 专属方案"
            apps = ["com.apple.dt.Xcode"]

            [global]
            deadzone       = 0.2
            poll_hz        = 100
            long_press_ms  = 250
            stick_mode     = "4dir"

            # ─────────── Right Joy-Con ───────────

            [profile.right.buttons]
            a       = "tap:enter"                       # 确定
            b       = "tap:escape"                      # 取消
            x       = "combo:option+0"                  # Type4Me 麦克风 1
            y       = "combo:option+1"                  # Type4Me 麦克风 2
            r       = "combo:option+2"                  # Type4Me Prompt 优化
            zr      = "app_switcher:system"             # 系统应用轮播切换
            plus    = "combo:cmd+r"                     # 编译并运行
            home    = "combo:cmd+shift+o"               # 快速打开文件 (Open Quickly)
            sl      = "combo:cmd+u"                     # 运行测试用例 (Test)
            sr      = "combo:cmd+."                     # 停止运行 (Stop)
            "r-stick" = "combo:cmd+ctrl+j"              # 跳转至定义 (Jump to Definition)

            [profile.right.stick]
            up      = "combo:cmd+'"                     # 跳转到下一个问题/警告 (Next Issue)
            down    = "combo:cmd+\\""                    # 跳转到上一个问题/警告 (Previous Issue)
            left    = "combo:cmd+ctrl+left"             # 后退浏览历史
            right   = "combo:cmd+ctrl+right"            # 前进浏览历史

            # ─────────── Left Joy-Con ───────────

            [profile.left.buttons]
            right   = "tap:enter"                       # 对应 A
            down    = "tap:escape"                      # 对应 B
            up      = "combo:option+0"                  # 对应 X
            left    = "combo:option+1"                  # 对应 Y
            l       = "combo:option+2"                  # 对应 R
            zl      = "app_switcher:system"             # 对应 ZR
            minus   = "combo:cmd+r"                     # 编译并运行
            capture = "combo:cmd+shift+o"               # 快速打开文件
            sl      = "combo:cmd+u"                     # 运行测试用例
            sr      = "combo:cmd+."                     # 停止运行
            "l-stick" = "combo:cmd+ctrl+j"              # 跳转至定义

            [profile.left.stick]
            up      = "combo:cmd+'"                     # 跳转到下一个问题/警告
            down    = "combo:cmd+\\""                    # 跳转到上一个问题/警告
            left    = "combo:cmd+ctrl+left"             # 后退浏览历史
            right   = "combo:cmd+ctrl+right"            # 前进浏览历史
            """
        ),
        .init(
            id: "terminal",
            title: "终端全家桶",
            subtitle: "Terminal / iTerm2 / Ghostty / Kitty 命令行方案",
            icon: "terminal.fill",
            tintColorHex: "#34C759",
            targetApps: [
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.mitchellh.ghostty",
                "net.kovidgoyal.kitty"
            ],
            highlights: ["摇杆单词跳跃", "SL 中断 ^C", "SR Tab 补全", "🔒 Type4Me 全局锁"],
            tomlContent: """
            # VibeJoy — Terminal Profile
            # Terminal / iTerm2 / Ghostty / Kitty 命令行高效方案

            [meta]
            description = "终端命令行方案"
            apps = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "net.kovidgoyal.kitty"]

            [global]
            deadzone       = 0.2
            poll_hz        = 100
            long_press_ms  = 250
            stick_mode     = "4dir"

            # ─────────── Right Joy-Con ───────────

            [profile.right.buttons]
            a       = "tap:enter"                       # 确定 / 执行命令
            b       = "tap:escape"                      # 取消
            x       = "combo:option+0"                  # Type4Me 麦克风 1
            y       = "combo:option+1"                  # Type4Me 麦克风 2
            r       = "combo:option+2"                  # Type4Me Prompt 优化
            zr      = "app_switcher:system"             # 系统应用轮播切换
            plus    = "combo:cmd+k"                     # 清屏 (Clear Screen)
            home    = "combo:ctrl+r"                    # 历史命令反向搜索 (Reverse Search)
            sl      = "combo:ctrl+c"                    # 中断当前命令 (SIGINT)
            sr      = "tap:tab"                         # 自动补全 (Autocomplete)
            "r-stick" = "combo:ctrl+d"                  # 退出会话 / EOF

            [profile.right.stick]
            up      = "tap:up"                          # 上一条命令
            down    = "tap:down"                        # 下一条命令
            left    = "combo:alt+b"                     # 光标向左跳跃一个单词
            right   = "combo:alt+f"                     # 光标向右跳跃一个单词

            # ─────────── Left Joy-Con ───────────

            [profile.left.buttons]
            right   = "tap:enter"                       # 对应 A
            down    = "tap:escape"                      # 对应 B
            up      = "combo:option+0"                  # 对应 X
            left    = "combo:option+1"                  # 对应 Y
            l       = "combo:option+2"                  # 对应 R
            zl      = "app_switcher:system"             # 对应 ZR
            minus   = "combo:cmd+k"                     # 清屏
            capture = "combo:ctrl+r"                    # 历史命令搜索
            sl      = "combo:ctrl+c"                    # 中断命令
            sr      = "tap:tab"                         # 自动补全
            "l-stick" = "combo:ctrl+d"                  # 退出会话

            [profile.left.stick]
            up      = "tap:up"                          # 上一条命令
            down    = "tap:down"                        # 下一条命令
            left    = "combo:alt+b"                     # 光标向左跳跃一个单词
            right   = "combo:alt+f"                     # 光标向右跳跃一个单词
            """
        ),
        .init(
            id: "antigravity",
            title: "Antigravity & Codex",
            subtitle: "新一代 AI 辅助结对编程控制台",
            icon: "sparkles",
            tintColorHex: "#AF52DE",
            targetApps: [
                "com.google.antigravity",
                "com.openai.codex"
            ],
            highlights: ["摇杆切换会话", "多行平滑滚动", "SL 物理修饰层", "🔒 Type4Me 全局锁"],
            tomlContent: """
            # VibeJoy — Antigravity & Codex Profile
            # 新一代 AI 结对编程控制台方案

            [meta]
            description = "Antigravity & Codex 专属方案"
            apps = ["com.google.antigravity", "com.openai.codex"]

            [global]
            deadzone       = 0.2
            poll_hz        = 100
            long_press_ms  = 250
            stick_mode     = "4dir"

            # ─────────── Right Joy-Con ───────────

            [profile.right.buttons]
            a       = "tap:enter"                       # 确定
            b       = "tap:escape"                      # 取消
            x       = "combo:option+0"                  # Type4Me 麦克风 1
            y       = "combo:option+1"                  # Type4Me 麦克风 2
            r       = "combo:option+2"                  # Type4Me Prompt 优化
            zr      = "app_switcher:system"             # 系统应用轮播切换
            plus    = "combo:cmd+s"                     # 保存 / 采纳变更
            home    = "window_switch:com.google.antigravity,com.openai.codex" # 双窗口极速切换
            sl      = "modifier:layer1"                 # 物理修饰层 1 (按住切换第二套按键)
            sr      = "combo:cmd+n"                     # 新建对话 / 会话
            "r-stick" = "none"

            [profile.right.stick]
            up      = "macro:codex_page_up"             # 向上滚动对话
            down    = "macro:codex_page_down"           # 向下滚动对话
            left    = "macro:codex_previous_thread"     # 切换到上一个会话
            right   = "macro:codex_next_thread"         # 切换到下一个会话

            [profile.right.layers.layer1.buttons]
            a       = "combo:cmd+enter"                 # 发送提示词 / 消息
            b       = "combo:cmd+w"                     # 关闭当前会话标签
            x       = "combo:cmd+k"                     # 命令控制面板
            y       = "combo:cmd+l"                     # 聚焦输入框

            # ─────────── Left Joy-Con ───────────

            [profile.left.buttons]
            right   = "tap:enter"                       # 对应 A
            down    = "tap:escape"                      # 对应 B
            up      = "combo:option+0"                  # 对应 X
            left    = "combo:option+1"                  # 对应 Y
            l       = "combo:option+2"                  # 对应 R
            zl      = "app_switcher:system"             # 对应 ZR
            minus   = "combo:cmd+s"                     # 对应 +
            capture = "window_switch:com.google.antigravity,com.openai.codex" # 对应 Home
            sl      = "modifier:layer1"                 # 对应 SL 修饰层
            sr      = "combo:cmd+n"                     # 对应 SR 新建会话
            "l-stick" = "none"

            [profile.left.stick]
            up      = "macro:codex_page_up"             # 向上滚动对话
            down    = "macro:codex_page_down"           # 向下滚动对话
            left    = "macro:codex_previous_thread"     # 切换到上一个会话
            right   = "macro:codex_next_thread"         # 切换到下一个会话

            [profile.left.layers.layer1.buttons]
            right   = "combo:cmd+enter"                 # 对应 A
            down    = "combo:cmd+w"                     # 对应 B
            up      = "combo:cmd+k"                     # 对应 X
            left    = "combo:cmd+l"                     # 对应 Y

            # ─────────── Macros ───────────

            [macro.codex_page_up]
            steps   = ["scroll:up@8"]

            [macro.codex_page_down]
            steps   = ["scroll:down@8"]

            [macro.codex_previous_thread]
            steps   = ["combo:option+up"]

            [macro.codex_next_thread]
            steps   = ["combo:option+down"]
            """
        ),
        .init(
            id: "browser",
            title: "网页浏览与多媒体",
            subtitle: "Safari / Chrome / Arc / Edge 冲浪专属",
            icon: "safari.fill",
            tintColorHex: "#FF9500",
            targetApps: [
                "com.apple.Safari",
                "com.google.Chrome",
                "company.thebrowser.Browser",
                "com.microsoft.edgemac"
            ],
            highlights: ["摇杆切标签", "下压摇杆关标签", "减号新建/方块恢复", "侧键历史前进后退", "🔒 Type4Me 全局锁"],
            tomlContent: """
            # VibeJoy — Browser Profile (浏览器专属方案)
            # 针对 Safari, Chrome, Arc, Edge 等浏览器优化

            [meta]
            description = "网页浏览与多媒体"
            apps = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac"]

            [global]
            deadzone       = 0.2
            poll_hz        = 100
            long_press_ms  = 250
            stick_mode     = "4dir"

            # ─────────── Right Joy-Con ───────────

            [profile.right.buttons]
            a       = "tap:enter"                       # 确定
            b       = "tap:escape"                      # 取消
            x       = "combo:option+0"                  # Type4Me 麦克风 1
            y       = "combo:option+1"                  # Type4Me 麦克风 2
            r       = "combo:option+2"                  # Type4Me Prompt 优化
            zr      = "app_switcher:system"             # 系统应用轮播切换
            plus    = "combo:cmd+t"                     # 新建标签页
            home    = "combo:cmd+shift+t"               # 恢复关闭的标签页
            sl      = "combo:cmd+["                     # 历史后退
            sr      = "combo:cmd+]"                     # 历史前进
            "r-stick" = "combo:cmd+w"                   # 关闭当前标签页

            [profile.right.stick]
            up      = "macro:browser_scroll_up"         # 向上流畅滚动
            down    = "macro:browser_scroll_down"       # 向下流畅滚动
            left    = "combo:cmd+alt+left"              # 切换至左侧标签页
            right   = "combo:cmd+alt+right"             # 切换至右侧标签页

            # ─────────── Left Joy-Con ───────────

            [profile.left.buttons]
            right   = "tap:enter"                       # 对应 A
            down    = "tap:escape"                      # 对应 B
            up      = "combo:option+0"                  # 对应 X
            left    = "combo:option+1"                  # 对应 Y
            l       = "combo:option+2"                  # 对应 R
            zl      = "app_switcher:system"             # 对应 ZR
            minus   = "combo:cmd+t"                     # 新建标签页
            capture = "combo:cmd+shift+t"               # 恢复关闭的标签页
            sl      = "combo:cmd+["                     # 历史后退
            sr      = "combo:cmd+]"                     # 历史前进
            "l-stick" = "combo:cmd+w"                   # 关闭当前标签页

            [profile.left.stick]
            up      = "macro:browser_scroll_up"         # 向上流畅滚动
            down    = "macro:browser_scroll_down"       # 向下流畅滚动
            left    = "combo:cmd+alt+left"              # 切换至左侧标签页
            right   = "combo:cmd+alt+right"             # 切换至右侧标签页

            # ─────────── Macros ───────────

            [macro.browser_scroll_up]
            steps   = ["scroll:up@18"]

            [macro.browser_scroll_down]
            steps   = ["scroll:down@18"]
            """
        )
    ]
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch clean.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
