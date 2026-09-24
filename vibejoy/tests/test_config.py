from __future__ import annotations

from pathlib import Path

import pytest

from vibejoy.config import (
    Config,
    ConfigError,
    GlobalConfig,
    MacroDef,
    MetaConfig,
    ProfileConfig,
    load_config,
    merge_configs,
    read_example_config,
    validate_config,
)


@pytest.fixture
def example_config_file(tmp_path: Path) -> Path:
    path = tmp_path / "config.toml"
    path.write_text(read_example_config(), encoding="utf-8")
    return path


def test_example_config_is_valid(example_config_file: Path) -> None:
    config = load_config(example_config_file)
    assert "right" in config.profiles
    assert "left" in config.profiles
    assert "claude_focus" in config.macros


def test_example_config_has_expected_macro(example_config_file: Path) -> None:
    config = load_config(example_config_file)
    macro = config.macros["claude_focus"]
    assert macro.if_app is not None
    assert any(step.startswith("type:") for step in macro.steps)


def test_example_codex_scroll_macros_are_native_gestures(example_config_file: Path) -> None:
    config = load_config(example_config_file)
    assert config.macros["codex_page_up"].steps == ("scroll:up@8",)
    assert config.macros["codex_page_down"].steps == ("scroll:down@8",)


def test_scroll_is_valid_on_sticks_and_invalid_on_buttons(tmp_path: Path) -> None:
    path_ok = tmp_path / "ok.toml"
    path_ok.write_text('[profile.right.stick]\nup = "scroll:up@8"\n', encoding="utf-8")
    config = load_config(path_ok)
    assert config.profiles["right"].stick["up"] == "scroll:up@8"

    path_bad = tmp_path / "bad.toml"
    path_bad.write_text('[profile.right.buttons]\na = "scroll:up@8"\n', encoding="utf-8")
    with pytest.raises(ConfigError, match="only supported on sticks or inside a macro"):
        load_config(path_bad)


def test_missing_file(tmp_path: Path) -> None:
    with pytest.raises(ConfigError, match="config file not found"):
        load_config(tmp_path / "nope.toml")


def test_invalid_toml(tmp_path: Path) -> None:
    path = tmp_path / "broken.toml"
    path.write_text("this = is = not toml", encoding="utf-8")
    with pytest.raises(ConfigError, match="invalid TOML"):
        load_config(path)


def test_unknown_top_level_section(tmp_path: Path) -> None:
    path = tmp_path / "bad.toml"
    path.write_text("[mystery]\nfoo = 1\n", encoding="utf-8")
    with pytest.raises(ConfigError, match="unknown top-level"):
        load_config(path)


def test_unknown_profile_side(tmp_path: Path) -> None:
    path = tmp_path / "bad.toml"
    path.write_text(
        '[profile.center.buttons]\na = "tap:enter"\n',
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="unknown profile"):
        load_config(path)


def test_bad_action_spec(tmp_path: Path) -> None:
    path = tmp_path / "bad.toml"
    path.write_text(
        '[profile.right.buttons]\na = "explode:world"\n',
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="unknown action verb"):
        load_config(path)


def test_unknown_key_name(tmp_path: Path) -> None:
    path = tmp_path / "bad.toml"
    path.write_text(
        '[profile.right.buttons]\na = "tap:explode"\n',
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="unknown key"):
        load_config(path)


def test_dangling_macro_reference(tmp_path: Path) -> None:
    path = tmp_path / "bad.toml"
    path.write_text(
        '[profile.right.buttons]\na = "macro:ghost"\n',
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="macro 'ghost' is not defined"):
        load_config(path)


def test_bad_stick_direction(tmp_path: Path) -> None:
    path = tmp_path / "bad.toml"
    path.write_text(
        '[profile.right.stick]\nnorth = "tap:up"\n',
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="unknown direction"):
        load_config(path)


def test_validate_global_ranges() -> None:
    cfg = Config(
        global_=GlobalConfig(deadzone=2.0, poll_hz=5000, long_press_ms=-1, stick_mode="weird"),  # type: ignore[arg-type]
        profiles={},
        macros={},
    )
    errors = validate_config(cfg)
    assert any("deadzone" in e for e in errors)
    assert any("poll_hz" in e for e in errors)
    assert any("long_press_ms" in e for e in errors)
    assert any("stick_mode" in e for e in errors)


def test_macro_rejects_nested_macro(tmp_path: Path) -> None:
    path = tmp_path / "bad.toml"
    path.write_text(
        '[macro.outer]\nsteps = ["macro:inner"]\n[macro.inner]\nsteps = ["tap:enter"]\n',
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="nested macro"):
        load_config(path)


def test_meta_config_parsing(tmp_path: Path) -> None:
    path = tmp_path / "meta_test.toml"
    path.write_text(
        '[meta]\ndescription = "Coding profile"\napps = ["com.openai.codex", "Code"]\n',
        encoding="utf-8",
    )
    cfg = load_config(path)
    assert cfg.meta.description == "Coding profile"
    assert cfg.meta.apps == ("com.openai.codex", "Code")


def test_meta_config_single_app_string(tmp_path: Path) -> None:
    path = tmp_path / "single_app.toml"
    path.write_text(
        '[meta]\napps = "com.apple.Safari"\n',
        encoding="utf-8",
    )
    cfg = load_config(path)
    assert cfg.meta.apps == ("com.apple.Safari",)


def test_meta_config_unknown_key(tmp_path: Path) -> None:
    path = tmp_path / "bad_meta.toml"
    path.write_text(
        '[meta]\nunknown_field = "oops"\n',
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="unknown key.*in \\[meta\\]"):
        load_config(path)


def test_meta_config_invalid_apps_type(tmp_path: Path) -> None:
    path = tmp_path / "bad_apps.toml"
    path.write_text(
        "[meta]\napps = 123\n",
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="\\[meta\\]\\.apps must be a list"):
        load_config(path)


def test_meta_config_invalid_app_element(tmp_path: Path) -> None:
    path = tmp_path / "bad_elem.toml"
    path.write_text(
        "[meta]\napps = [123]\n",
        encoding="utf-8",
    )
    with pytest.raises(ConfigError, match="\\[meta\\]\\.apps\\[0\\] must be a string"):
        load_config(path)


def test_meta_config_validate_empty_app_string() -> None:
    cfg = Config(
        global_=GlobalConfig(),
        profiles={},
        macros={},
        meta=MetaConfig(apps=("",)),
    )
    errors = validate_config(cfg)
    assert any("meta.apps[0] must be a non-empty string" in e for e in errors)


def test_merge_configs() -> None:
    base = Config(
        global_=GlobalConfig(deadzone=0.35, poll_hz=250),
        profiles={
            "right": ProfileConfig(
                buttons={"a": "tap:enter", "b": "tap:escape"},
                stick={"up": "macro:page_up", "down": "macro:page_down"},
            ),
            "left": ProfileConfig(
                buttons={"right": "tap:space"},
                stick={},
            ),
        },
        macros={
            "page_up": MacroDef(steps=("scroll:up@8",)),
            "page_down": MacroDef(steps=("scroll:down@8",)),
        },
        meta=MetaConfig(description="Base profile"),
    )

    child = Config(
        global_=GlobalConfig(long_press_ms=500),
        profiles={
            "right": ProfileConfig(
                buttons={"a": "tap:space"},
                stick={"left": "macro:custom_left"},
            ),
        },
        macros={
            "custom_left": MacroDef(steps=("tap:left",)),
        },
        meta=MetaConfig(apps=("com.apple.Safari",), description="Child profile"),
    )

    merged = merge_configs(base, child)

    # Global config: non-default child overrides, omitted child fields fall back to base
    assert merged.global_.deadzone == 0.35  # inherited from base
    assert merged.global_.poll_hz == 250    # inherited from base
    assert merged.global_.long_press_ms == 500  # overridden by child
    assert merged.global_.stick_mode == "4dir"

    # Profiles: right buttons merged (a overridden, b inherited)
    assert merged.profiles["right"].buttons["a"] == "tap:space"
    assert merged.profiles["right"].buttons["b"] == "tap:escape"

    # Profiles: right stick merged (up and down inherited, left added)
    assert merged.profiles["right"].stick["up"] == "macro:page_up"
    assert merged.profiles["right"].stick["down"] == "macro:page_down"
    assert merged.profiles["right"].stick["left"] == "macro:custom_left"

    # Profiles: left profile inherited from base
    assert merged.profiles["left"].buttons["right"] == "tap:space"

    # Macros: inherited and added
    assert "page_up" in merged.macros
    assert merged.macros["page_up"].steps == ("scroll:up@8",)
    assert "page_down" in merged.macros
    assert "custom_left" in merged.macros
    assert merged.macros["custom_left"].steps == ("tap:left",)

    # Meta: child meta takes precedence
    assert merged.meta.apps == ("com.apple.Safari",)
    assert merged.meta.description == "Child profile"

