import enum
import sys
from unittest.mock import MagicMock

class _VK:
    def __init__(self, vk):
        self.vk = vk

VK_MAP = {
    "alt": 0x3A,
    "alt_l": 0x3A,
    "alt_r": 0x3D,
    "cmd": 0x37,
    "cmd_r": 0x36,
    "shift": 0x38,
    "shift_r": 0x3C,
    "ctrl": 0x3B,
    "ctrl_r": 0x3E,
    "tab": 0x30,
    "enter": 0x24,
    "esc": 0x35,
    "space": 0x31,
    "backspace": 0x33,
    "delete": 0x75,
}

class Key(enum.Enum):
    shift = _VK(VK_MAP.get("shift", 0x38))
    shift_r = _VK(VK_MAP.get("shift_r", 0x3C))
    ctrl = _VK(VK_MAP.get("ctrl", 0x3B))
    ctrl_r = _VK(VK_MAP.get("ctrl_r", 0x3E))
    alt = _VK(VK_MAP.get("alt", 0x3A))
    alt_r = _VK(VK_MAP.get("alt_r", 0x3D))
    alt_l = _VK(VK_MAP.get("alt_l", 0x3A))
    cmd = _VK(VK_MAP.get("cmd", 0x37))
    cmd_r = _VK(VK_MAP.get("cmd_r", 0x36))
    enter = _VK(VK_MAP.get("enter", 0x24))
    esc = _VK(VK_MAP.get("esc", 0x35))
    space = _VK(VK_MAP.get("space", 0x31))
    tab = _VK(VK_MAP.get("tab", 0x30))
    backspace = _VK(VK_MAP.get("backspace", 0x33))
    delete = _VK(VK_MAP.get("delete", 0x75))
    up = _VK(0x7E)
    down = _VK(0x7D)
    left = _VK(0x7B)
    right = _VK(0x7C)
    home = _VK(0x73)
    end = _VK(0x77)
    page_up = _VK(0x74)
    page_down = _VK(0x79)
    caps_lock = _VK(0x39)
    media_play_pause = _VK(None)
    media_volume_up = _VK(None)
    media_volume_down = _VK(None)
    media_volume_mute = _VK(None)
    media_next = _VK(None)
    media_previous = _VK(None)
    f1 = _VK(0x7A); f2 = _VK(0x78); f3 = _VK(0x63); f4 = _VK(0x76); f5 = _VK(0x60)
    f6 = _VK(0x61); f7 = _VK(0x62); f8 = _VK(0x64); f9 = _VK(0x65); f10 = _VK(0x6D)
    f11 = _VK(0x67); f12 = _VK(0x6F); f13 = _VK(0x69); f14 = _VK(0x6B); f15 = _VK(0x71)
    f16 = _VK(0x6A); f17 = _VK(0x40); f18 = _VK(0x4F); f19 = _VK(0x50); f20 = _VK(0x5A)

class KeyCode:
    def __init__(self, char=None, vk=None):
        self.char = char
        self.vk = vk

pynput_mock = MagicMock()
pynput_mock.keyboard.Key = Key
pynput_mock.keyboard.KeyCode = KeyCode
sys.modules["pynput"] = pynput_mock
sys.modules["pynput.keyboard"] = pynput_mock.keyboard
sys.modules["pynput._util"] = pynput_mock._util

quartz_mock = MagicMock()
quartz_mock.kCGHIDEventTap = 0
quartz_mock.kCGEventSourceStateHIDSystemState = 1
quartz_mock.kCGScrollEventUnitLine = 0
sys.modules["Quartz"] = quartz_mock

for mod in [
    "ApplicationServices",
    "hid",
    "glm",
    "pyglm",
    "pyjoycon",
    "pyjoycon.joycon",
    "pyjoycon.gyro",
]:
    if mod not in sys.modules:
        sys.modules[mod] = MagicMock()
