<!-- codex-execution-mode:start -->
## Active Codex Execution Mode: Sol -> Luna -> Sol

GPT-5.6 Sol owns architecture, the concise plan, acceptance criteria, and final
review. Small work may remain in Sol. For substantial implementation, Sol uses
exactly one built-in worker with `model = "gpt-5.6-luna"`,
`reasoning_effort = "high"`, `fork_turns = "none"`, and task name
`luna_executor`. Use `reasoning_effort = "max"` only when explicitly requested
or when exceptionally difficult, quality-first work justifies it. Sol reviews
the actual changes and validation; corrections return to the same worker, with
at most two correction turns. A later explicit user instruction overrides this
mode.
<!-- codex-execution-mode:end -->

<!-- antigravity-execution-mode:start -->
## Active Antigravity Execution Mode: Sonnet -> Flash -> Sonnet

Claude Sonnet 4.6 (Thinking) owns high-level architecture, the concise plan,
acceptance criteria, CodeGraph impact analysis, and final review. Small or
purely investigatory work may remain in Sonnet. For substantial implementation
or multi-file coding, Sonnet delegates execution to a dedicated subagent with
`Model = "flash"` (Role: `Flash Executor`). The Flash worker carries out code
edits, runs tests/lints, and reports a concise summary back to Sonnet. Sonnet
reviews the changes and validation results before presenting them to the user.
A later explicit user instruction overrides this mode.
<!-- antigravity-execution-mode:end -->

<!-- CODEGRAPH_START -->
## CodeGraph & Cross-Agent Synergy (Codex + Antigravity)

This repository is indexed by CodeGraph (`.codegraph/` exists at the workspace root).
Both **Codex** (Sol / Luna) and **Antigravity** share this knowledge graph as the single source of truth for code intelligence and impact analysis:

- **Before Refactoring or Editing**:
  - Reach for CodeGraph BEFORE `grep`/`find` or mass file reading.
  - Via MCP tools (when available): use `codegraph_explore` or `codegraph_node` to inspect symbols, callers, callees, and the blast radius.
  - Via Shell (always available): run `codegraph explore "<symbol or query>"` or `codegraph node <symbol>`.
- **Cross-Language Coordination (`vibejoy` ↔ `VibeJoyBar`)**:
  - Any changes to action verbs/DSL, TOML schema, or IPC socket contracts in `vibejoy` (Python) must be verified against `VibeJoyBar` (Swift) UI/models using CodeGraph callers/callees.
- **Graph Synchronization**:
  - CodeGraph automatically watches and updates the AST index in `.codegraph/` as code changes occur.
<!-- CODEGRAPH_END -->

