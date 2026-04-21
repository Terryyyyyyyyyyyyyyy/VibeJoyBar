<!--
Thanks for the PR. A checklist so review goes smoothly:

- One logical change per PR. Unrelated drive-bys go in a separate commit/PR.
- Conventional commits in the commit message (`feat:`, `fix:`, `docs:`, …).
- If you touched `src/vibejoy/`, also update or add tests under `tests/`.
- If you touched public DSL / CLI / config shape, update:
    - `README.md`
    - `src/vibejoy/config.example.toml`
    - `CHANGELOG.md` (under `[Unreleased]`)
- CI must be green before merge (ruff check + ruff format + pytest on 3 Pythons).
-->

## What & why

<!-- What does this PR change, and what problem does it solve? 1-3 sentences. -->

## How to verify

<!-- Commands a reviewer can run locally to confirm the change works. -->

```bash
uv sync
uv run pytest
uv run ruff check src tests
# additional manual test steps:
```

## Checklist

- [ ] Tests added / updated
- [ ] `README.md` updated if user-facing
- [ ] `CHANGELOG.md` `[Unreleased]` entry added
- [ ] `vibejoy validate` still passes on the bundled `config.example.toml`
- [ ] No new runtime dependencies, or a clear justification included
