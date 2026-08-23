# Spec: Extract terminal-output navigation from executor

## Problem Statement

As a maintainer of cling.nvim, I find that the most valuable behaviour in the
plugin — turning a line of terminal output into a navigable file location — is
buried inside an inline keymap callback in `core.executor`. The `<CR>` handler
is a ~45-line closure that captures `actual_cwd` and `original_window` from the
executor's call frame, performs a 10-line quickfix save/restore dance to parse
a line with a hard-coded `temp_efm` literal, resolves a file path, and opens it
via `win_execute`. The `ge` export handler is a separate free function
(`export_output`) that lives between unrelated window-lifecycle code. The test
suite needs 775 lines plus real terminal jobs in `/tmp` just to get a buffer
with keymaps attached; even then, it can only assert the `<CR>` keymap *exists*
(by fetching keymaps and checking `lhs`), not what it does. The export tests are
slightly better — they fetch the callback and invoke it directly — but they
still require `core.executor` to have run first. Bugs hide in how the callbacks
are called, not in them — there is no locality. I want the navigation behaviour
to live behind a small, testable interface so that bugs concentrate in one
module, tests run with plain buffers and temp files (no terminal jobs), and the
`temp_efm` literal stops being a disguised constant.

## Solution

Create a single `navigation` module that owns terminal-output navigation: a
`jump_to(line, cfile, cwd, target_win)` function that converts a line of
terminal output into a file open action, and an `export(buf, cmd, cwd,
filepath)` function that writes buffer content to a file with a metadata
footer. The executor's `<CR>` keymap callback shrinks to ~4 lines that extract
the current line and `<cfile>` from the cursor and delegate to `jump_to`. The
`ge` callback keeps the interactive file-path prompt (a UI concern) and
delegates the writing to `export`. The 10-line quickfix save/restore dance is
replaced with a single `vim.fn.getqflist({ lines = {...}, efm = DEFAULT_EFM })`
call that parses the line without polluting global state. `DEFAULT_EFM` becomes
a named module-local constant instead of an inline literal. All existing
behaviour is preserved exactly — this is a structural refactor, not a
behaviour change — including known limitations (the cfile-vs-efm-filename path
resolution discrepancy, the silent return on missing files, and the missing
empty-items guard) which are documented and deferred to separate changes.

## User Stories

1. As a plugin maintainer, I want the `<CR>` jump logic to live in a
   `navigation` module with a `jump_to(line, cfile, cwd, target_win)` function,
   so that the navigation behaviour is testable in isolation without driving
   the full `core.executor` pipeline.

2. As a plugin maintainer, I want the `ge` export logic to live in the same
   `navigation` module as an `export(buf, cmd, cwd, filepath)` function, so
   that both terminal-output operations have one home and are testable
   together.

3. As a plugin maintainer, I want the executor's `<CR>` keymap callback to
   shrink to extracting the current line and `<cfile>` from the cursor and
   delegating to `navigation.jump_to`, so that the callback is thin wiring
   rather than behaviour-rich logic.

4. As a plugin maintainer, I want the executor's `ge` keymap callback to keep
   only the interactive file-path prompt and delegate the writing to
   `navigation.export`, so that the UI concern (prompt) is separated from the
   data concern (read lines, format, write).

5. As a plugin maintainer, I want the 10-line quickfix save/restore dance in
   the `<CR>` handler replaced with a single
   `vim.fn.getqflist({ lines = {...}, efm = DEFAULT_EFM })` call, so that the
   line parsing does not pollute global quickfix state or `errorformat`.

6. As a plugin maintainer, I want the three errorformat patterns (`%f:%l:%c:%m`,
   `%f:%l:%c`, `%f:%l`) to be a named module-local constant (`DEFAULT_EFM`) in
   the navigation module, so that the format has a name, a single home, and is
   not reconstructed fresh on every keypress.

7. As a plugin maintainer, I want `actual_cwd` and `original_window` to remain
   as closure captures in the executor's keymap callbacks and be passed as
   parameters to `jump_to`, so that the wiring is simple and matches the
   current code structure.

8. As a plugin maintainer, I want the `q` keymap to stay in the executor as a
   call to `close_cling_window`, so that window lifecycle remains separate from
   navigation.

9. As a plugin maintainer, I want `build_split_cmd`, `configure_cling_window`,
   column capture state, `close_cling_window`, and `_untrack_window` to all
   stay in `core.lua`, so that the refactor is scoped to navigation only and
   does not pull in window-lifecycle or column-capture concerns.

10. As a plugin maintainer, I want the `export_output` free function removed
    from `core.lua` and its body moved into `navigation.export`, so that
    `core.lua` no longer contains a file-I/O function unrelated to window
    lifecycle.

11. As a plugin maintainer, I want the line-trimming behaviour preserved
    exactly — `line:find(cfile, 1, true)` to locate the cfile in the line, then
    `line:sub(start_idx)` to trim — so that the refactor is behaviour-preserving
    even though this causes a known path-resolution discrepancy.

12. As a plugin maintainer, I want the path resolution to use `cfile` (from the
    cursor) rather than the efm-parsed filename, so that the current behaviour
    is preserved; this discrepancy is documented as a known limitation and
    deferred to a separate change.

13. As a plugin maintainer, I want the path resolution fallback preserved
    exactly — try `vim.fs.joinpath(cwd, cfile)`, fall back to `cfile` if the
    joined path doesn't exist but `cfile` does, and silently return if neither
    exists — so that no user-facing behaviour changes.

14. As a plugin maintainer, I want the absence of an empty-items guard
    preserved — if efm doesn't match and the parsed list is empty, accessing
    `items[1].lnum` errors — so that the refactor is structural; the guard is
    deferred to a separate change.

15. As a plugin maintainer, I want the `col` type check preserved (`if type(col)
    == "number" and col > 0`), so that the column positioning behaviour is
    unchanged.

16. As a plugin maintainer, I want the `win_execute` + `set_current_win`
    sequence preserved, so that the target window opens the file and receives
    focus as before.

17. As a plugin maintainer, I want the "Original window is no longer valid"
    notification preserved when the target window is invalid, so that error
    reporting is unchanged.

18. As a plugin maintainer, I want the export metadata footer preserved
    exactly — Command, CWD, ISO 8601 Timestamp, `vim: ft=log` modeline — and
    internal to `navigation.export`, so that the output format is unchanged
    and callers don't need to know about footer formatting.

19. As a plugin maintainer, I want the export trailing-empty-line stripping
    preserved, so that exported files don't have spurious blank lines at the
    end.

20. As a plugin maintainer, I want the export to preserve raw ANSI escape
    codes in the buffer content, so that terminal output with colour codes is
    exported verbatim.

21. As a test author, I want to call `navigation.jump_to(line, cfile, cwd,
    target_win)` directly with a real temp file path and a real window, so that
    I can test the jump behaviour without spawning a terminal job.

22. As a test author, I want to call `navigation.export(buf, cmd, cwd,
    filepath)` directly with a plain created buffer, so that I can test the
    export behaviour without running `core.executor` first.

23. As a test author, I want the existing keymap-existence tests in
    `core_spec.lua` to remain (verifying that `<CR>`, `ge`, and `q` keymaps are
    registered on the buffer), so that wiring coverage is maintained.

24. As a test author, I want the existing export behaviour tests (exports with
    metadata, preserves ANSI, cancels on empty input) to move from
    `core_spec.lua` to `navigation_spec.lua`, so that they test the navigation
    interface directly instead of fetching keymap callbacks.

25. As a test author, I want a new test that verifies `jump_to` opens a file at
    the correct line number when the line contains a `file:line:col` pattern,
    so that the primary jump path is covered.

26. As a test author, I want a new test that verifies `jump_to` opens a file at
    the correct line and column when the line contains a `file:line:col:message`
    pattern, so that the column-positioning path is covered.

27. As a test author, I want a new test that verifies `jump_to` resolves the
    file path relative to the provided `cwd`, so that the path-join behaviour
    is covered.

28. As a test author, I want a new test that verifies `jump_to` falls back to
    the `cfile` path when the joined path doesn't exist but `cfile` does, so
    that the fallback path is covered.

29. As a test author, I want a new test that verifies `jump_to` silently
    returns when the file doesn't exist at either path, so that the
    silent-return behaviour is locked.

30. As a test author, I want a new test that verifies `jump_to` notifies when
    the target window is no longer valid, so that the error-reporting path is
    covered.

31. As a test author, I want a new test that verifies `jump_to` trims the line
    to start from the `cfile` position before parsing, so that the trimming
    behaviour is explicitly tested (and the known limitation is visible).

32. As a test author, I want a new test that verifies `navigation.export` writes
    the metadata footer with Command, CWD, Timestamp, and modeline, so that
    the footer format is locked.

33. As a test author, I want a new test that verifies `navigation.export`
    strips trailing empty lines from the buffer content before writing, so
    that the stripping behaviour is covered.

34. As a test author, I want a new test that verifies `navigation.export`
    preserves ANSI escape codes in the output, so that colour-coded terminal
    output is exported verbatim.

35. As a test author, I want a new test that verifies `navigation.export`
    returns without writing when the filepath is empty or the prompt is
    cancelled, so that the cancel path is covered (the prompt itself stays in
    the executor; the test calls `export` with a pre-decided path or tests the
    executor's prompt logic separately).

36. As a plugin user, I want the `<CR>` key on a terminal output buffer to
    jump to the file/line under the cursor exactly as before, so that I
    experience no behaviour change.

37. As a plugin user, I want the `ge` key on a terminal output buffer to export
    the content to a file with the same metadata footer as before, so that
    exported files look identical.

38. As a plugin user, I want the `q` key to close the terminal window exactly
    as before, so that window lifecycle is unaffected.

39. As a plugin maintainer, I want `core_spec.lua` to retain its real-terminal
    spawn tests (executor opens a window, close_on_exit behaviour, split
    modes, column capture) but lose the export behaviour tests, so that the
    spec file focuses on what it tests best — executor wiring and lifecycle —
    while navigation behaviour is tested at its own seam.

40. As a plugin maintainer, I want the `require "cling.navigation"` call to
    work in `core.lua` with no additional setup, so that the module is a
    standard in-process require like the other `cling` modules.

## Implementation Decisions

### Modules created

- **`navigation` module** (`lua/cling/navigation.lua`) — the single owner of
  terminal-output navigation. Contains `jump_to`, `export`, and the
  `DEFAULT_EFM` constant.

### Modules modified

- **`core` module** (`lua/cling/core.lua`) — loses the `export_output` free
  function (moves to `navigation.export`), loses the `<CR>` callback body
  (moves to `navigation.jump_to`), and the `ge` callback shrinks to a prompt +
  thin delegation. Gains a `require "cling.navigation"` at the top. All other
  functions (`build_split_cmd`, `configure_cling_window`, `close_cling_window`,
  `_untrack_window`, `executor`, `_reset_column_capture`, `_track_window`) and
  module-level state (`_captured_columns`, `_winnew_autocmd_id`,
  `_cling_windows`) remain unchanged.

### Interfaces

- `navigation.jump_to(line, cfile, cwd, target_win)` — converts a line of
  terminal output into a file open action. Trims the line to start from
  `cfile`, parses the trimmed line with `DEFAULT_EFM` via
  `vim.fn.getqflist({ lines = {...}, efm = ... })`, extracts `lnum`/`col`,
  resolves the file path relative to `cwd` (with fallback to `cfile`), and
  opens the file in `target_win` via `win_execute` with the cursor positioned
  at the parsed line/column. Returns silently if the file doesn't exist.
  Notifies if the target window is invalid.

- `navigation.export(buf, cmd, cwd, filepath)` — writes terminal buffer
  content to a file with a metadata footer. Reads all lines from `buf`, strips
  trailing empty lines, appends a four-line footer (Command, CWD, ISO 8601
  Timestamp, `vim: ft=log` modeline), and writes the result via
  `fs.write_file`. The interactive prompt (`vim.fn.input`) is NOT part of this
  interface — the caller resolves the filepath before calling.

- `DEFAULT_EFM` (module-local constant) — `table.concat({ "%f:%l:%c:%m",
  "%f:%l:%c", "%f:%l" }, ",")`. Not exported, not a parameter. Used internally
  by `jump_to`.

### Architectural decisions

- **Caller extracts cursor state (ADR-002, Q1.1):** The `<CR>` keymap callback
  reads `vim.api.nvim_get_current_line()` and `vim.fn.expand("<cfile>")` and
  passes them as parameters to `jump_to`. This keeps `jump_to` free of cursor
  API coupling — tests call it with a line string and a cfile string directly.

- **Inline efm parsing (ADR-002, Q1.3):** The 10-line quickfix save/restore
  dance is replaced with `vim.fn.getqflist({ lines = { trimmed_line }, efm =
  DEFAULT_EFM })`. This returns parsed items directly without touching the
  global quickfix list or `errorformat`.

- **One module for jump + export (ADR-002, Q1.2):** Both functions live in
  `navigation.lua`. Both operate on terminal output buffers. The module is
  named "navigation" broadly — jump navigates to source, export navigates to
  file.

- **Prompt stays in executor (ADR-002, Q2.3):** The `vim.fn.input` call for the
  export file path stays in the `ge` keymap callback in `core.lua`.
  `navigation.export` receives the already-resolved filepath. This keeps
  `export` testable with a plain string — no UI dependency.

- **Closure captures (ADR-002, Q2.2):** `actual_cwd` and `original_window`
  remain as closure variables captured in the `executor` function's scope and
  passed as parameters to `jump_to` in the keymap callback. No module-level
  state is introduced for these values.

- **Behaviour preservation (ADR-002, Q2.1, Q3.2, Q3.3):** All existing
  behaviours are preserved exactly — line trimming, cfile-based path
  resolution, silent return on missing file, no empty-items guard, `col` type
  check, `win_execute` + `set_current_win`, metadata footer format, trailing
  empty line stripping, ANSI preservation. This is a structural refactor, not a
  behaviour change.

- **Scope boundary (ADR-002, Q2.4, Q4.3):** The `q` keymap, `build_split_cmd`,
  `configure_cling_window`, column capture state, `close_cling_window`, and
  `_untrack_window` all stay in `core.lua`. The refactor touches only
  `export_output` and the `<CR>` callback body.

### Known limitations (preserved, not introduced by this refactor)

- **cfile-vs-efm-filename discrepancy:** `jump_to` trims the line to start from
  `cfile` and parses with efm, but uses `cfile` (not the efm-parsed filename)
  for path resolution. When the line is `  src/main.lua:42:10: error` and
  `cfile` is `main.lua`, the efm sees `main.lua:42:10: error` (prefix stripped)
  while path resolution uses `main.lua` (not `src/main.lua`). Documented in
  ADR-002; fix deferred.

- **Silent return on missing file:** If the file doesn't exist at either the
  joined path or `cfile` itself, `jump_to` returns silently with no user
  feedback. Documented in ADR-002; fix deferred.

- **No empty-items guard:** If efm doesn't match the line, the parsed list is
  empty and accessing `items[1].lnum` errors. Documented in ADR-002; fix
  deferred.

## Testing Decisions

### What makes a good test

Tests should exercise the `navigation` module's public API — `jump_to` and
`export` — and assert external behaviour (files opened at the right line/col,
files written with the right content), not implementation details (internal
constants, private helpers). The highest seam is the module boundary: require
the module, call its functions, inspect the results. No test should drive
`core.executor` or fetch keymap callbacks to test navigation behaviour.

### Seams

1. **Navigation module interface (NEW):** The primary seam. Tests in
   `navigation_spec.lua` call `nav.jump_to(line, cfile, cwd, target_win)` and
   `nav.export(buf, cmd, cwd, filepath)` directly. `jump_to` tests use real temp
   files (`os.tmpname`) in headless Neovim — create a file, construct a line
   with its path, call `jump_to`, assert the target window opened the file at
   the right position. `export` tests use plain created buffers
   (`nvim_create_buf` + `nvim_buf_set_lines`) — no terminal jobs, no
   `core.executor` setup.

2. **Executor wiring (EXISTING):** The existing `core_spec.lua` seam. Keymap
   existence tests (verify `<CR>`, `ge`, `q` are registered) stay here — they
   test wiring, not behaviour. Lifecycle tests (spawn, close, column capture,
   split modes, close_on_exit) stay as-is. Export behaviour tests move to
   `navigation_spec.lua`.

### Modules tested

- **`navigation`** — the primary module under test. New tests in
  `navigation_spec.lua`.

- **`core` (executor)** — existing wiring and lifecycle tests stay in
  `core_spec.lua`. Export behaviour tests are removed (they now live in
  `navigation_spec.lua`). Keymap-existence tests remain.

### Test plan

| Area | Tests | Prior art |
|---|---|---|
| `jump_to` — basic jump | Line contains `file:line:col`; temp file exists; assert target window opened file at correct line and column | New — no jump_to tests exist currently (core_spec only asserts keymap exists) |
| `jump_to` — line:col only | Line contains `file:line:col` without message; assert line/col positioning | New |
| `jump_to` — line only | Line contains `file:line` without col; assert line positioning, no col movement | New |
| `jump_to` — path resolution via cwd | cfile is relative; joined with cwd the file exists; assert opened | New |
| `jump_to` — fallback to cfile | Joined path doesn't exist but cfile alone does; assert opened | New |
| `jump_to` — missing file | Neither path exists; assert silent return (no error, no window change) | New |
| `jump_to` — invalid target window | Target window is closed/invalid; assert notification is shown | New (existing handler has this path but it's untested) |
| `jump_to` — line trimming | Line has prefix before cfile; assert the line is trimmed from cfile position before parsing | New |
| `export` — metadata footer | Export a buffer; assert file contains Command, CWD, Timestamp, modeline lines | Prior art: `core_spec.lua` export tests (same assertions, now calling `nav.export` directly) |
| `export` — trailing empty strip | Buffer has trailing empty lines; assert they are removed in output | Prior art: `core_spec.lua` (implicitly tested) |
| `export` — ANSI preservation | Buffer contains ANSI escape codes; assert they appear in output verbatim | Prior art: `core_spec.lua` ANSI test |
| `export` — cancel on empty path | `export` is called with empty filepath; assert no file is created | Prior art: `core_spec.lua` cancel test (prompt logic tested at executor level) |
| `core` — keymap existence | `<CR>`, `ge`, `q` keymaps are registered on the buffer after executor runs | Prior art: existing `core_spec.lua` tests (unchanged) |
| `core` — lifecycle | Spawn, close, close_on_exit, column capture, split modes | Prior art: existing `core_spec.lua` tests (unchanged) |

### Test harness

Tests run under `plenary.nvim` with `busted`-style syntax (`describe`/`it`/
`assert`), inside headless Neovim via `minimal_init.lua`. The `jump_to` tests
use real `vim.fn.getqflist`, `vim.uv.fs_stat`, and `vim.fn.win_execute` — they
need a Neovim runtime but not a terminal job. The `export` tests use plain
buffers and `fs.write_file` — also need a Neovim runtime for buffer APIs. No
mocks are injected; the trade-off is simpler tests at the cost of requiring the
Neovim test harness.

## Out of Scope

- **Fixing the cfile-vs-efm-filename path resolution discrepancy.** This is a
  pre-existing bug where the line is trimmed from `cfile` but path resolution
  uses `cfile` (not the efm-parsed filename). It is documented as a known
  limitation in ADR-002 and deferred to a separate change.

- **Adding an empty-items guard to `jump_to`.** If efm doesn't match, the
  current code errors on `items[1].lnum`. This is pre-existing behaviour,
  preserved by this refactor. The guard is deferred to a separate change.

- **Adding user notification for missing files.** The current silent return when
  a file doesn't exist is preserved. Adding a notification is a behaviour
  change deferred to a separate change.

- **Making `DEFAULT_EFM` configurable.** The errorformat patterns are an
  internal constant. Making them a parameter would enable custom formats but
  adds interface surface for no current need.

- **Making the export metadata footer configurable.** The footer format
  (Command, CWD, Timestamp, modeline) is internal to `export`. Customisation
  is deferred until there is a concrete need.

- **Extracting `build_split_cmd` from `core.lua`.** It is about terminal window
  creation, not navigation. Moving it would be scope creep.

- **Extracting column capture into its own module (Candidate 4).** This is a
  separate refactoring effort from the architecture review. The column capture
  state (`_captured_columns`, `_winnew_autocmd_id`, `_cling_windows`,
  `configure_cling_window`, `_untrack_window`, `_reset_column_capture`,
  `_track_window`) stays in `core.lua` unchanged.

- **One seam for completion generation (Candidate 3).** This is a separate
  refactoring effort.

- **Injecting mocks for `vim.fn.getqflist`, `vim.uv.fs_stat`, or
  `vim.fn.win_execute`.** The grilling decided on real buffers + temp files
  rather than mocks. This keeps tests simpler and closer to production
  behaviour at the cost of requiring a Neovim runtime.

- **Splitting `jump_to` into `parse_location` + `open_location`.** The
  decomposition was considered (Option C in grilling) and rejected — it adds
  a third function and an intermediate type for no testability gain, since the
  testing constraint is `vim.uv.fs_stat` and `vim.fn.win_execute`, not the
  parsing step.

## Further Notes

- This spec implements ADR-002 ("Extract terminal-output navigation from
  executor"), which was produced by the `grill-with-docs` skill through a
  four-round grilling process. All 15 design questions were resolved before
  this spec was written. See `doc/adr/ADR-002-navigation-extraction.md` for the
  full decision record.

- The domain glossary at `doc/glossary.md` defines the key terms used in this
  spec: **Navigation (module)**, **jump_to**, **export (navigation)**,
  **DEFAULT_EFM**, **terminal output buffer**, and **location (parsed)**.
  These terms were added during the domain-modeling phase of the
  `grill-with-docs` skill.

- The previous spec (`doc/spec/give-commandnode-a-home.md`) implemented
  Candidate 1 from the architecture review. This spec implements Candidate 2.
  The architecture review ranked Candidate 2 as a "close second" to Candidate
  1, noting that it is the right choice "if terminal-output navigation is
  where you currently feel the pain."

- The grilling process corrected several claims from the original architecture
  review:
  - The review proposed `jump_to(lines)` — the actual code needs `line`, `cfile`,
    `cwd`, and `target_win`. The real interface is `jump_to(line, cfile, cwd,
    target_win)`.
  - The review proposed `export(buffer)` — the actual function needs `buf`,
    `cmd`, `cwd`, and `filepath`. The prompt is a UI concern that stays in the
    executor.
  - The review said "`temp_efm` stops being a disguised literal" — it becomes
    `DEFAULT_EFM`, a named module-local constant.
  - The review said "core_spec's real-terminal jobs shrink to spawn coverage"
    — the export tests move to `navigation_spec.lua` where they run with plain
    buffers; the spawn/lifecycle/wiring tests stay in `core_spec.lua`.
  - The review said "tests hit the interface, not `nvim_buf_get_keymap`" — the
    new `navigation_spec.lua` tests call `nav.jump_to` and `nav.export` directly;
    the existing keymap-existence tests in `core_spec.lua` (which do use
    `nvim_buf_get_keymap`) remain as wiring verification.