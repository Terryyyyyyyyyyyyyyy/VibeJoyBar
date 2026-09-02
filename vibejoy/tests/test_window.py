"""Window-switch cycle behavior without activating real applications."""

from __future__ import annotations

import vibejoy.window as window_mod
from vibejoy.window import AppInfo, WindowSwitcher


def test_repeated_same_binding_advances_instead_of_resetting(monkeypatch) -> None:
    apps = [
        AppInfo(pid=1, bundle_id="com.openai.codex", name="Codex", executable="Codex"),
        AppInfo(
            pid=2,
            bundle_id="com.google.Chrome",
            name="Google Chrome",
            executable="Google Chrome",
        ),
        AppInfo(
            pid=3,
            bundle_id="com.microsoft.VSCode",
            name="Visual Studio Code",
            executable="Code",
        ),
    ]
    activated: list[str] = []
    monkeypatch.setattr(window_mod, "list_running_apps", lambda: apps)
    monkeypatch.setattr(
        window_mod,
        "activate_app",
        lambda app: activated.append(app.name) or True,
    )

    queries = ("Codex", "Google Chrome", "Safari", "Visual Studio Code")
    switcher = WindowSwitcher(queries)

    for _ in range(4):
        # Mapper._do_press calls set_queries before every step.
        switcher.set_queries(queries)
        switcher.step()

    assert activated == ["Codex", "Google Chrome", "Visual Studio Code", "Codex"]


def test_changed_binding_resets_cycle(monkeypatch) -> None:
    apps = [
        AppInfo(pid=1, bundle_id="one", name="One", executable="One"),
        AppInfo(pid=2, bundle_id="two", name="Two", executable="Two"),
    ]
    activated: list[str] = []
    monkeypatch.setattr(window_mod, "list_running_apps", lambda: apps)
    monkeypatch.setattr(
        window_mod,
        "activate_app",
        lambda app: activated.append(app.name) or True,
    )

    switcher = WindowSwitcher(("One", "Two"))
    switcher.step()
    switcher.step()
    switcher.set_queries(("Two", "One"))
    switcher.step()

    assert activated == ["One", "Two", "Two"]


def test_codex_alias_prefers_real_codex_over_codexbar() -> None:
    apps = [
        AppInfo(pid=1, bundle_id="com.steipete.codexbar", name="CodexBar", executable="CodexBar"),
        AppInfo(pid=2, bundle_id="com.openai.codex", name="ChatGPT", executable="Codex"),
    ]
    assert window_mod._first_match(apps, "Codex").pid == 2


def test_exact_bundle_id_always_wins() -> None:
    apps = [
        AppInfo(pid=1, bundle_id="com.steipete.codexbar", name="CodexBar", executable="CodexBar"),
        AppInfo(pid=2, bundle_id="com.openai.codex", name="ChatGPT", executable="Codex"),
    ]
    assert window_mod._first_match(apps, "com.openai.codex").pid == 2


def test_find_app_uses_same_ranked_selection(monkeypatch) -> None:
    apps = [
        AppInfo(pid=1, bundle_id="com.steipete.codexbar", name="CodexBar", executable="CodexBar"),
        AppInfo(pid=2, bundle_id="com.openai.codex", name="ChatGPT", executable="Codex"),
    ]
    monkeypatch.setattr(window_mod, "list_running_apps", lambda: apps)
    assert window_mod.find_app("Codex").pid == 2
