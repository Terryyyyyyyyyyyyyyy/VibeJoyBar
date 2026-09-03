from __future__ import annotations

import io
from pathlib import Path
from unittest.mock import patch

import pytest

from vibejoy.cli import main
from vibejoy.config import (
    ConfigError,
    active_profile_path,
    backup_config,
    create_profile,
    default_backups_dir,
    default_config_path,
    default_profiles_dir,
    delete_profile,
    ensure_profiles_initialized,
    get_active_profile,
    list_profiles,
    load_config,
    read_default_profile,
    set_active_profile,
    switch_profile,
    validate_config,
    validate_profile_name,
)


def test_default_profile_loads_and_validates(tmp_path: Path):
    content = read_default_profile()
    assert "[global]" in content
    assert "[profile.right.buttons]" in content
    assert "[profile.right.stick]" in content
    assert "app_switcher:system" in content
    assert "window_switch:com.openai.codex" in content
    assert "macro:codex_page_up" in content

    test_file = tmp_path / "default_test.toml"
    test_file.write_text(content, encoding="utf-8")

    cfg = load_config(test_file)
    errors = validate_config(cfg)
    assert errors == []

    right_buttons = cfg.profiles["right"].buttons
    assert right_buttons["a"] == "tap:enter"
    assert right_buttons["b"] == "tap:escape"
    assert right_buttons["x"] == "combo:option+0"
    assert right_buttons["y"] == "combo:option+1"
    assert right_buttons["r"] == "combo:option+2"
    assert right_buttons["zr"] == "app_switcher:system"
    assert right_buttons["plus"] == "combo:cmd+s"
    assert right_buttons["home"] == "window_switch:com.openai.codex"

    right_stick = cfg.profiles["right"].stick
    assert right_stick["up"] == "macro:codex_page_up"
    assert right_stick["down"] == "macro:codex_page_down"
    assert right_stick["left"] == "macro:codex_previous_thread"
    assert right_stick["right"] == "macro:codex_next_thread"

    assert "codex_page_up" in cfg.macros
    assert cfg.macros["codex_page_up"].steps == ("scroll:up@8",)
    assert cfg.macros["codex_page_up"].if_app == "com.openai.codex"


def test_ensure_profiles_initialized(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    profiles_dir = default_profiles_dir()
    assert not profiles_dir.exists()

    default_file = ensure_profiles_initialized()
    assert default_file.exists()
    assert default_file == profiles_dir / "default.toml"
    assert default_file.read_text(encoding="utf-8") == read_default_profile()

    # Should not overwrite custom changes if called again
    default_file.write_text("# custom modification", encoding="utf-8")
    ensure_profiles_initialized()
    assert default_file.read_text(encoding="utf-8") == "# custom modification"


def test_backup_config(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    config_file = tmp_path / "vibejoy" / "config.toml"
    config_file.parent.mkdir(parents=True, exist_ok=True)
    custom_content = "# custom user config\n[global]\ndeadzone = 0.4\n"
    config_file.write_text(custom_content, encoding="utf-8")

    backup_file = backup_config(config_file)
    assert backup_file.exists()
    assert backup_file.parent == default_backups_dir()
    assert backup_file.name.startswith("config.")
    assert backup_file.name.endswith(".bak.toml")
    assert backup_file.read_text(encoding="utf-8") == custom_content


def test_cli_profile_export_default(capsys: pytest.CaptureFixture[str]):
    rc = main(["profile", "export-default"])
    assert rc == 0
    captured = capsys.readouterr()
    assert captured.out == read_default_profile()


def test_cli_profile_list(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    rc = main(["profile", "list"])
    assert rc == 0
    captured = capsys.readouterr()
    assert "default" in captured.out
    assert "factory baseline" in captured.out


def test_cli_profile_reset_default_force(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    config_file = tmp_path / "vibejoy" / "config.toml"
    config_file.parent.mkdir(parents=True, exist_ok=True)
    custom_content = "# custom user config\n[global]\npoll_hz = 50\n"
    config_file.write_text(custom_content, encoding="utf-8")

    rc = main(["profile", "reset-default", "--force"])
    assert rc == 0
    captured = capsys.readouterr()
    assert "backed up active config to" in captured.out
    assert "restored default profile to" in captured.out

    # Verify backup exists
    backups = list(default_backups_dir().glob("*.bak.toml"))
    assert len(backups) == 1
    assert backups[0].read_text(encoding="utf-8") == custom_content

    # Verify active config is restored to default
    assert config_file.read_text(encoding="utf-8") == read_default_profile()


def test_cli_profile_reset_default_prompt_declined(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    config_file = tmp_path / "vibejoy" / "config.toml"
    config_file.parent.mkdir(parents=True, exist_ok=True)
    custom_content = "# keep me\n"
    config_file.write_text(custom_content, encoding="utf-8")

    with patch("builtins.input", return_value="n"):
        rc = main(["profile", "reset-default"])
    assert rc == 1
    captured = capsys.readouterr()
    assert "aborted" in captured.out
    assert config_file.read_text(encoding="utf-8") == custom_content


def test_cli_profile_reset_default_prompt_accepted(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    config_file = tmp_path / "vibejoy" / "config.toml"
    config_file.parent.mkdir(parents=True, exist_ok=True)
    custom_content = "# replace me\n"
    config_file.write_text(custom_content, encoding="utf-8")

    with patch("builtins.input", return_value="y"):
        rc = main(["profile", "reset-default"])
    assert rc == 0
    captured = capsys.readouterr()
    assert "restored default profile to" in captured.out
    assert config_file.read_text(encoding="utf-8") == read_default_profile()


def test_validate_profile_name():
    assert validate_profile_name("default") == "default"
    assert validate_profile_name("my_profile-1") == "my_profile-1"
    assert validate_profile_name("  办公模式  ") == "办公模式"

    with pytest.raises(ConfigError):
        validate_profile_name("")
    with pytest.raises(ConfigError):
        validate_profile_name("   ")
    with pytest.raises(ConfigError):
        validate_profile_name("../evil")
    with pytest.raises(ConfigError):
        validate_profile_name(".hidden")
    with pytest.raises(ConfigError):
        validate_profile_name("foo/bar")
    with pytest.raises(ConfigError):
        validate_profile_name("foo\\bar")
    with pytest.raises(ConfigError):
        validate_profile_name("foo*bar")


def test_active_profile_get_and_set(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    assert get_active_profile() == "default"

    set_active_profile("coding")
    assert get_active_profile() == "coding"
    assert active_profile_path().read_text("utf-8") == "coding"

    # Corrupt or empty active_profile should fallback to default
    active_profile_path().write_text("", encoding="utf-8")
    assert get_active_profile() == "default"

    active_profile_path().write_text("../invalid", encoding="utf-8")
    assert get_active_profile() == "default"


def test_list_and_create_and_switch_and_delete_profile(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))

    # Initially only default
    profiles = list_profiles()
    assert len(profiles) == 1
    assert profiles[0]["name"] == "default"
    assert profiles[0]["is_default"] is True
    assert profiles[0]["is_active"] is True

    # Create new profile from default
    new_path = create_profile("coding")
    assert new_path.exists()
    assert new_path.name == "coding.toml"

    # Creating with existing name raises
    with pytest.raises(ConfigError):
        create_profile("coding")

    # List profiles: default should come first, then sorted
    create_profile("alpha")
    profiles = list_profiles()
    assert [p["name"] for p in profiles] == ["default", "alpha", "coding"]

    # Switch profile
    switch_profile("coding")
    assert get_active_profile() == "coding"
    active_cfg = default_config_path()
    assert active_cfg.read_text("utf-8") == new_path.read_text("utf-8")

    profiles = list_profiles()
    coding_item = next(p for p in profiles if p["name"] == "coding")
    assert coding_item["is_active"] is True
    default_item = next(p for p in profiles if p["name"] == "default")
    assert default_item["is_active"] is False

    # Cannot delete default
    with pytest.raises(ConfigError, match="cannot delete factory default"):
        delete_profile("default")

    # Delete active profile switches back to default
    delete_profile("coding")
    assert not new_path.exists()
    assert get_active_profile() == "default"

    # Delete non-existent profile raises
    with pytest.raises(ConfigError):
        delete_profile("non_existent")


def test_cli_profile_current_and_create_and_switch(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))

    # Current
    rc = main(["profile", "current"])
    assert rc == 0
    assert capsys.readouterr().out.strip() == "default"

    # Create without switch
    rc = main(["profile", "create", "work"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "created profile 'work'" in out

    rc = main(["profile", "current"])
    assert rc == 0
    assert capsys.readouterr().out.strip() == "default"

    # Switch
    rc = main(["profile", "switch", "work"])
    assert rc == 0
    assert "switched active profile to 'work'" in capsys.readouterr().out

    rc = main(["profile", "current"])
    assert rc == 0
    assert capsys.readouterr().out.strip() == "work"

    # Create with --switch and --from
    rc = main(["profile", "create", "work2", "--from", "work", "-s"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "created profile 'work2'" in out
    assert "switched active profile to 'work2'" in out

    rc = main(["profile", "current"])
    assert rc == 0
    assert capsys.readouterr().out.strip() == "work2"

    # Delete prompt declined
    with patch("builtins.input", return_value="n"):
        rc = main(["profile", "delete", "work2"])
    assert rc == 1
    assert "aborted" in capsys.readouterr().out

    # Delete with --force
    rc = main(["profile", "delete", "work2", "--force"])
    assert rc == 0
    assert "deleted profile 'work2'" in capsys.readouterr().out

    # Should be back to default because work2 was active
    rc = main(["profile", "current"])
    assert rc == 0
    assert capsys.readouterr().out.strip() == "default"

