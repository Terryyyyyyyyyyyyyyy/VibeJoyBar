"""VibeJoy Spike — Joy-Con × macOS 可行性验证

在写正式代码之前，先用这个脚本确认三件事：
  1. Mac 蓝牙能配对并识别 Joy-Con
  2. pyjoycon 能读到按钮 / 摇杆 / 电量
  3. pynput 能在 Mac 上模拟键盘按键

运行：
    uv run scripts/spike_joycon.py

前置条件：
  - macOS 已通过蓝牙配对 Joy-Con（首次使用见下方指引）
  - uv sync（PyPI 的 hidapi 自带原生库，无需 brew install）
  - 首次运行 pynput 模拟按键时，系统会弹窗要求「辅助功能」授权
    → 系统设置 → 隐私与安全性 → 辅助功能 → 把你的终端勾上

如果卡住，每一步出错的地方都有具体指引。
"""

from __future__ import annotations

import sys
import time

# ---------- 漂亮的输出 ----------

GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
DIM = "\033[2m"
BOLD = "\033[1m"
RESET = "\033[0m"


def ok(msg: str) -> None:
    print(f"{GREEN}✅{RESET} {msg}")


def fail(msg: str) -> None:
    print(f"{RED}❌{RESET} {msg}")


def info(msg: str) -> None:
    print(f"{CYAN}•{RESET} {msg}")


def hint(msg: str) -> None:
    print(f"  {DIM}↳ {msg}{RESET}")


def section(title: str) -> None:
    print()
    print(f"{BOLD}━━━ {title} ━━━{RESET}")


# ---------- Joy-Con 配对指引 ----------

PAIR_GUIDE = f"""
{BOLD}Joy-Con ↔ macOS 蓝牙配对步骤{RESET}
  1. 打开「系统设置 → 蓝牙」保持窗口打开
  2. 长按 Joy-Con 滑轨内侧的 {BOLD}圆形 SYNC 小钮{RESET} 3 秒
     · 左手柄：SL/SR 之间的黑色小圆钮
     · 右手柄：同样位置，在卡扣侧
  3. 4 颗指示灯开始{YELLOW}来回跑{RESET}表示进入配对模式
  4. 蓝牙列表里出现 "Joy-Con (L)" 或 "Joy-Con (R)"，点击连接
  5. 指示灯变成{GREEN}常亮一颗{RESET}即配对成功

{DIM}注意：macOS 只能同时连接一个同名设备。如果要双手柄，
先配 L 再配 R，系统会显示两条蓝牙记录。{RESET}
"""


# ---------- 依赖检查 ----------

def check_deps() -> bool:
    section("步骤 1/4：检查 Python 依赖")
    missing = []

    try:
        import hid  # noqa: F401
        ok("hidapi 已安装（PyPI 版自带原生库）")
    except ImportError:
        fail("hidapi 未安装")
        hint("uv sync")
        missing.append("hidapi")

    try:
        import pyjoycon  # noqa: F401
        ok("joycon-python 已安装")
    except ImportError:
        fail("joycon-python 未安装")
        hint("uv sync")
        missing.append("joycon-python")

    try:
        import pynput  # noqa: F401
        ok("pynput 已安装")
    except ImportError:
        fail("pynput 未安装")
        hint("uv sync")
        missing.append("pynput")

    return not missing


# ---------- Joy-Con 检测 ----------

def detect_joycon():
    section("步骤 2/4：扫描已配对的 Joy-Con")
    from pyjoycon import JoyCon, get_L_id, get_R_id

    r_id = get_R_id()
    l_id = get_L_id()
    info(f"右手柄扫描结果: {r_id}")
    info(f"左手柄扫描结果: {l_id}")

    found = []
    if r_id[0] is not None:
        ok(f"发现右手柄 vid={r_id[0]:#06x} pid={r_id[1]:#06x}")
        found.append(("R", r_id))
    if l_id[0] is not None:
        ok(f"发现左手柄 vid={l_id[0]:#06x} pid={l_id[1]:#06x}")
        found.append(("L", l_id))

    if not found:
        fail("未检测到任何 Joy-Con")
        print(PAIR_GUIDE)
        print(f"{YELLOW}排查建议：{RESET}")
        hint("确认蓝牙面板里 Joy-Con 显示「已连接」(绿点)")
        hint("macOS 休眠后 Joy-Con 会自动断开，按一下任意键唤醒")
        hint("如果一直配不上，删掉旧记录再配一次（右键 X 移除）")
        hint("macOS 14+ 对某些克隆手柄兼容性差；原厂 Joy-Con 最稳")
        return None

    # 有就用第一个（右优先）
    side, dev_id = found[0]
    try:
        joycon = JoyCon(*dev_id)
        ok(f"成功连接 {side} 手柄")
        return joycon, side
    except OSError as e:
        fail(f"打开 HID 设备失败: {e}")
        hint("可能是权限问题。如果报 'open failed'，试试：")
        hint("  1. 系统设置 → 隐私与安全性 → 输入监控 → 勾上终端")
        hint("  2. 或者先用原生蓝牙断开 Joy-Con 再重新连接")
        return None


# ---------- 状态展示 ----------

def show_device_info(joycon, side: str) -> None:
    section("步骤 3/4：读取设备信息")
    try:
        level = joycon.get_battery_level()
        charging = joycon.get_battery_charging()
        pct = {0: "≤25%", 1: "≤50%", 2: "≤75%", 3: "满"}.get(level, "?")
        charge_str = "🔌充电中" if charging else "电池供电"
        ok(f"电量: {pct} ({level}/3)   状态: {charge_str}")
    except Exception as e:
        fail(f"读取电量失败: {e}")

    try:
        is_left = joycon.is_left()
        is_right = joycon.is_right()
        ok(f"自检: is_left={is_left}, is_right={is_right}（应与实际 {side} 一致）")
    except Exception as e:
        fail(f"读取类型失败: {e}")


# ---------- 实时轮询 ----------

def _active_buttons(status: dict) -> list[str]:
    """从 status 字典里抽出所有当前按下的按钮名。"""
    active = []
    for section_name in ("right", "left", "shared"):
        group = status.get("buttons", {}).get(section_name, {}) or {}
        for btn_name, val in group.items():
            if val:
                active.append(btn_name)
    return active


def _stick_snapshot(status: dict) -> tuple[int, int, int, int]:
    """(Lx, Ly, Rx, Ry) — 返回摇杆原始值，供打印。"""
    sticks = status.get("analog-sticks", {}) or {}
    left = sticks.get("left", {}) or {}
    right = sticks.get("right", {}) or {}
    return (
        int(left.get("horizontal", 0) or 0),
        int(left.get("vertical", 0) or 0),
        int(right.get("horizontal", 0) or 0),
        int(right.get("vertical", 0) or 0),
    )


def poll_loop(joycon, side: str, duration: float = 20.0) -> None:
    section(f"步骤 3/4：实时轮询 Joy-Con（{duration:.0f} 秒）")
    print(f"{DIM}请按任意按钮、推动摇杆，看是否被正确识别。按 Ctrl+C 可提前结束。{RESET}\n")

    start = time.monotonic()
    prev_signature = None
    lines_printed = 0

    try:
        while time.monotonic() - start < duration:
            try:
                status = joycon.get_status()
            except Exception as e:
                fail(f"读取 status 失败: {e}")
                break

            pressed = _active_buttons(status)
            sticks = _stick_snapshot(status)
            # 量化摇杆值，避免摇杆微抖一直刷屏（分辨率 ≈ 200）
            sx_q = tuple(v // 200 for v in sticks)
            signature = (tuple(pressed), sx_q)

            if signature != prev_signature:
                prev_signature = signature
                elapsed = time.monotonic() - start
                btn_str = " + ".join(pressed) if pressed else f"{DIM}(无){RESET}"
                lx, ly, rx, ry = sticks
                print(
                    f"  [{elapsed:5.1f}s] "
                    f"按键: {BOLD}{btn_str}{RESET}  "
                    f"{DIM}L-stick=({lx:+5d},{ly:+5d})  R-stick=({rx:+5d},{ry:+5d}){RESET}"
                )
                lines_printed += 1

            time.sleep(0.03)
    except KeyboardInterrupt:
        print(f"\n{DIM}(手动中断){RESET}")

    if lines_printed == 0:
        fail("整段时间内没有读到任何变化")
        hint("可能 Joy-Con 休眠了。按一下按钮或者重新连接蓝牙试试")
        hint("或者 pyjoycon 没权限打开 HID 流，见前面的输入监控授权")
    else:
        ok(f"轮询结束，捕获到 {lines_printed} 次状态变化")


# ---------- pynput 键盘模拟 ----------

def test_pynput() -> None:
    section("步骤 4/4：验证 pynput 键盘模拟")
    from pynput.keyboard import Controller, Key

    print(f"{DIM}即将模拟按一下 Shift 键（不会输入任何字符，只是安全的测试）。{RESET}")
    print(f"{DIM}如果是第一次，macOS 会弹窗要求「辅助功能」授权。{RESET}\n")

    for remaining in (3, 2, 1):
        print(f"  {remaining}...")
        time.sleep(1)

    try:
        kbd = Controller()
        kbd.press(Key.shift)
        time.sleep(0.05)
        kbd.release(Key.shift)
        ok("pynput 模拟成功")
    except Exception as e:
        fail(f"pynput 模拟失败: {type(e).__name__}: {e}")
        hint("打开「系统设置 → 隐私与安全性 → 辅助功能」")
        hint("把你正在跑这个脚本的程序（Terminal / iTerm / VS Code）勾上")
        hint("授权后需要完全退出并重新打开终端，设置才生效")


# ---------- 主流程 ----------

def main() -> int:
    print()
    print(f"{BOLD}{CYAN}╔════════════════════════════════════════════════════╗{RESET}")
    print(f"{BOLD}{CYAN}║  VibeJoy Spike — Joy-Con × macOS 可行性验证        ║{RESET}")
    print(f"{BOLD}{CYAN}╚════════════════════════════════════════════════════╝{RESET}")

    if not check_deps():
        print()
        fail("依赖不全，先修复再来一次")
        return 1

    result = detect_joycon()
    if result is None:
        return 1
    joycon, side = result

    show_device_info(joycon, side)
    poll_loop(joycon, side)
    test_pynput()

    section("结果")
    print(f"  如果上面 4 步全部 {GREEN}✅{RESET}，说明技术栈在你这台 Mac 上可行，")
    print("  可以开始写 VibeJoy 正式代码了。")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
