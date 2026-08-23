# 08: Expansion module foundation — `@%` across all entry points

**What to build:** The expansion module is born as a pure transformation
`(raw command line, execution CWD) → expanded command line`, with the
cursor-context provider made injectable through its options (even though this
slice only expands `%`, which needs no cursor state — the seam is established
for the non-modifier tokens in ticket 02). It recognizes exactly one token —
`@%`, the current file — and copies every other character verbatim, including
the `@@`→`@` escape and a bare `@` not followed by a recognized token.

This slice wires the feature into EVERY raw-line entry point so the tracer
bullet cuts the full path: the interactive prompt (after both prompts resolve,
execution CWD = the CWD chosen at the second prompt), the `--` passthrough
(execution CWD = current working directory), and the `run_last` replay path.
Because `run_last` re-executes stored history, history must keep the raw typed
line; the slice ensures `last_cmd` and per-CWD history record the raw line
(not the expanded text) so replays re-expand against the then-current buffer
and CWD.

A structural gotcha this slice must resolve: history is recorded inside
`core.executor` from whatever string it receives. Expanding before the
executor would make it store the expanded line, so replays would no longer
re-expand. The slice must preserve the raw typed line in history while the
expanded string reaches the shell, and must do so WITHOUT expanding wrapper
commands (which call the executor directly, bypassing the entry points).
Choose the mechanism (e.g. an opt-in flag the raw-line entry points set, or
recording raw at the entry point) so that all three spec constraints hold:
raw history, env-prefix downstream of expansion, wrappers literal.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] Expansion module exposes one function: expand(line, cwd, opts) → expanded line; cursor-context injectable via opts (unused by `%` this slice)
- [x] `@%` expands to the current file's path; demoable via the interactive prompt (`cat @%` cats the current file)
- [x] Scanner copies all non-marker input verbatim; `@@` yields a single literal `@`; a bare `@` not followed by a recognized token passes through
- [x] Unmarked `%`, `#`, `<`, `>`, and backticks pass through unchanged — existing commands unaffected (zero-casualty baseline)
- [x] The interactive prompt expands marked tokens after both prompts resolve, against the execution CWD
- [x] `:Cling -- cat @%` expands `@%`, execution CWD = current working directory
- [x] `:Cling last` re-expands the stored raw command at execution time against the current buffer and CWD
- [x] The env-file (`with-env`) flow expands marked tokens in its command prompt (covered via the interactive path)
- [x] History (`last_cmd` and per-CWD) records the raw typed line, not the expanded text; replays re-expand
- [x] The executor's `.env` prefix-injection operates on the already-expanded command
- [x] Wrapper commands do NOT expand marked tokens — their argument contract is unchanged
- [x] Module-seam test (table-driven, with a fake current file) covers `@%` and basic passthrough; wiring tests confirm a marked command is expanded before the shell receives it across all three entry points
