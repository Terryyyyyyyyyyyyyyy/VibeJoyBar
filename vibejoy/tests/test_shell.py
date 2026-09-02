"""Shell action plumbing — env construction + subprocess spawn contract."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import pytest

from vibejoy import shell as shell_mod
from vibejoy.shell import build_context_env, run_shell

# ---------- Fake Popen ----------


@dataclass
class FakePopen:
    calls: list[dict[str, Any]] = field(default_factory=list)
    pid: int = 9999
    raise_exc: Exception | None = None

    def __call__(self, argv, *, env=None, cwd=None, start_new_session=False, **kwargs):
        if self.raise_exc is not None:
            raise self.raise_exc
        self.calls.append(
            {
                "argv": list(argv),
                "env": dict(env or {}),
                "cwd": cwd,
                "start_new_session": start_new_session,
                "kwargs": kwargs,
            }
        )
        return self


@pytest.fixture
def fake_popen() -> FakePopen:
    return FakePopen()


# ---------- build_context_env ----------


class TestBuildContextEnv:
    def test_minimum(self) -> None:
        env = build_context_env(event="pressed")
        assert env == {"VIBEJOY_EVENT": "pressed"}

    def test_button_context(self) -> None:
        env = build_context_env(event="pressed", button="zr", side="right")
        assert env["VIBEJOY_BUTTON"] == "zr"
        assert env["VIBEJOY_SIDE"] == "right"

    def test_stick_context(self) -> None:
        env = build_context_env(event="released", side="left", direction="up-left")
        assert env["VIBEJOY_DIRECTION"] == "up-left"
        assert "VIBEJOY_BUTTON" not in env

    def test_frontmost_app_only_when_present(self) -> None:
        assert "VIBEJOY_FRONTMOST_APP" not in build_context_env(event="pressed")
        assert (
            build_context_env(event="pressed", frontmost_app="Safari")["VIBEJOY_FRONTMOST_APP"]
            == "Safari"
        )

    def test_empty_frontmost_app_is_dropped(self) -> None:
        # An empty string shouldn't leak through as a misleading var.
        assert "VIBEJOY_FRONTMOST_APP" not in build_context_env(
            event="pressed",
            frontmost_app="",
        )


# ---------- run_shell ----------


class TestRunShell:
    def test_invokes_sh_dash_c(self, fake_popen: FakePopen) -> None:
        run_shell("echo hi", _popen=fake_popen)
        assert len(fake_popen.calls) == 1
        assert fake_popen.calls[0]["argv"] == ["/bin/sh", "-c", "echo hi"]

    def test_detaches_session(self, fake_popen: FakePopen) -> None:
        run_shell("true", _popen=fake_popen)
        assert fake_popen.calls[0]["start_new_session"] is True

    def test_merges_extra_env_over_os_env(
        self, fake_popen: FakePopen, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("PATH", "/sentinel/path")
        run_shell("true", extra_env={"VIBEJOY_EVENT": "pressed"}, _popen=fake_popen)
        env = fake_popen.calls[0]["env"]
        assert env["VIBEJOY_EVENT"] == "pressed"
        assert env["PATH"] == "/sentinel/path"

    def test_extra_env_overrides_os_env(
        self, fake_popen: FakePopen, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("VIBEJOY_EVENT", "stale")
        run_shell("true", extra_env={"VIBEJOY_EVENT": "pressed"}, _popen=fake_popen)
        assert fake_popen.calls[0]["env"]["VIBEJOY_EVENT"] == "pressed"

    def test_cwd_forwarded(self, fake_popen: FakePopen) -> None:
        run_shell("true", cwd="/tmp", _popen=fake_popen)
        assert fake_popen.calls[0]["cwd"] == "/tmp"

    def test_empty_command_is_noop(self, fake_popen: FakePopen) -> None:
        assert run_shell("", _popen=fake_popen) is None
        assert run_shell("   ", _popen=fake_popen) is None
        assert fake_popen.calls == []

    def test_oserror_returns_none(self) -> None:
        fake = FakePopen(raise_exc=OSError("/bin/sh missing"))
        # Should not raise.
        assert run_shell("true", _popen=fake) is None


class TestIntegrationSmoke:
    """One lightweight real-process test so we know the plumbing actually works.

    Uses ``true``, which is on every macOS and most Linux installs.
    """

    def test_real_spawn(self) -> None:
        proc = run_shell("true")
        assert proc is not None
        # Reap it to avoid zombies in CI.
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
        assert proc.returncode == 0


def test_get_frontmost_app_never_raises() -> None:
    # Whether we're on macOS or not, the function must return cleanly.
    result = shell_mod.get_frontmost_app()
    assert result is None or isinstance(result, str)
