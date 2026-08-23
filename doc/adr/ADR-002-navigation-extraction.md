# ADR-002: Extract terminal-output navigation from executor

## Status

Accepted — all 15 grilling questions resolved

## Context

`core.executor` in `lua/cling/core.lua` is a ~160-line function (364 lines
counting the whole module) that mixes three concerns:

1. **Job spawning** — building the `sh -c` command string, opening the
   terminal split, setting buffer name.
2. **Key wiring** — registering `q`, `<CR>`, and `ge` keymaps on the terminal
   buffer.
3. **Navigation behaviour** — the `<CR>` callback (lines ~213-258) turns a
   line of terminal output into a navigable file location via a hard-coded
   `temp_efm`, quickfix save/restore, and `win_execute`; the `ge` callback
   exports buffer content to a file with a metadata footer.

The most valuable behaviour — turning terminal output into navigable locations
— hides inside an inline keymap callback. The test suite
(`tests/cling/core_spec.lua`, 775 lines) needs real terminal jobs in `/tmp`
just to get a buffer with keymaps; even then it can only assert the `<CR>`
keymap *exists* (`nvim_buf_get_keymap` + check `lhs`), not what it does. The
`ge` export tests fare slightly better — they fetch the callback and invoke it
directly — but they still require `core.executor` to have run first to produce
a buffer with the keymap attached.

Bugs hide in how the callbacks are called, not in them — there is no locality.
The `<CR>` handler is a closure that captures `actual_cwd` and
`original_window` from the `executor` call frame, making it impossible to test
in isolation.

### Specific problems

- **`temp_efm` is a disguised literal.** The three errorformat patterns
  (`%f:%l:%c:%m`, `%f:%l:%c`, `%f:%l`) are concatenated inline with no name, no
  constant, and no documentation of what they match.
- **The quickfix save/restore dance is unnecessary.** The handler saves the
  entire global quickfix state (`getqflist { all = 0 }`), saves
  `vim.go.errorformat`, sets a temp efm, calls `setqflist`, reads items, then
  restores both. Vim's `getqflist` supports parsing lines with a custom efm in
  a single call (`getqflist({ lines = {...}, efm = "..." })`) without touching
  the global list — the save/restore is 10 lines of fragile ceremony for
  something that should be one call.
- **Latent path resolution bug.** The handler finds `cfile` in the current
  line, trims the line to start from that position, and parses the trimmed
  line with efm. But it uses the original `cfile` (not the efm-parsed filename)
  for path resolution. When the line is `  src/main.lua:42:10: error` and
  `cfile` is `main.lua`, the efm sees `main.lua:42:10: error` (prefix
  stripped) while path resolution uses `main.lua` (not `src/main.lua`). This
  is pre-existing behaviour — the refactor preserves it and documents it as a
  known limitation.
- **No guard on empty parse results.** After `getqflist`, the code accesses
  `qf_items[1].lnum` with no check that the list is non-empty. If efm doesn't
  match, this errors. Pre-existing — preserved.
- **`export_output` is a free function.** It lives between
  `configure_cling_window` and `_untrack_window` in `core.lua`, unrelated to
  either. It does file I/O with a metadata footer — a responsibility that
  belongs with the terminal-output operations, not with window lifecycle.

## Decision

Create `lua/cling/navigation.lua` as the single owner of terminal-output
navigation, with a small interface:

### Interface

```lua
--- @class cling.Navigation
--- @field jump_to fun(line: string, cfile: string, cwd: string, target_win: integer)
--- @field export fun(buf: integer, cmd: string|nil, cwd: string|nil, filepath: string)

local M = {}

function M.jump_to(line, cfile, cwd, target_win) ... end
function M.export(buf, cmd, cwd, filepath) ... end

return M
```

### 1. Extract `jump_to`

Move the `<CR>` callback body into `navigation.jump_to(line, cfile, cwd,
target_win)`. The executor's keymap callback shrinks to:

```lua
callback = function()
    local line = vim.api.nvim_get_current_line()
    local cfile = vim.fn.expand "<cfile>"
    nav.jump_to(line, cfile, actual_cwd, original_window)
end
```

The caller extracts cursor state (`nvim_get_current_line`, `expand("<cfile>")`)
and passes it as parameters. `jump_to` owns the rest: line trimming, efm
parsing, path resolution, and `win_execute`.

### 2. Replace quickfix save/restore with inline parsing

Replace the 10-line save/restore dance with:

```lua
local items = vim.fn.getqflist {
    lines = { trimmed_line },
    efm = DEFAULT_EFM,
}
```

This returns parsed items directly without polluting the global quickfix list
or `errorformat`. `DEFAULT_EFM` is a module-local constant:

```lua
local DEFAULT_EFM = table.concat({
    "%f:%l:%c:%m",
    "%f:%l:%c",
    "%f:%l",
}, ",")
```

### 3. Extract `export`

Move `export_output` into `navigation.export(buf, cmd, cwd, filepath)`. The
executor's `ge` keymap callback shrinks to:

```lua
callback = function()
    local ok, filepath = pcall(vim.fn.input,
        "Export to: ", vim.fn.getcwd() .. "/cling-output.log", "file")
    if not ok or not filepath or filepath == "" then
        return
    end
    nav.export(M.cling_buffer, M.last_cmd, actual_cwd, filepath)
end
```

The interactive prompt (`vim.fn.input`) stays in the executor — it is a UI
concern. `nav.export` receives the resolved filepath and owns: reading buffer
lines, stripping trailing empties, appending the metadata footer, and writing
the file.

### 4. Preserve all existing behaviour

This is a structural refactor, not a behaviour change:

- **Line trimming:** `jump_to` preserves the `line:find(cfile, 1, true)` +
  `line:sub(start_idx)` trimming. The efm-parsed filename is used only for
  `lnum`/`col` extraction; `cfile` is used for path resolution (the known
  limitation is documented below).
- **Path resolution:** `vim.fs.joinpath(cwd, cfile)` with fallback to `cfile`
  if the joined path doesn't exist but `cfile` does. Silent `return` if neither
  exists (no user notification).
- **No empty-items guard:** If efm doesn't match, `items[1].lnum` errors. This
  is current behaviour — preserved.
- **`col` type check:** `if type(col) == "number" and col > 0` — preserved.
- **`win_execute` + `set_current_win`:** The target window opens the file and
  receives focus — preserved.
- **Metadata footer:** Command, CWD, Timestamp (ISO 8601), `vim: ft=log`
  modeline — preserved exactly, internal to `nav.export`.

### 5. What stays in `core.lua`

- `build_split_cmd` — terminal window creation (not navigation)
- `configure_cling_window` + column capture state — window styling (Candidate
  4 territory)
- `close_cling_window` + `_untrack_window` — window lifecycle
- `executor` — job spawning + key wiring (thin callbacks)
- `_reset_column_capture` / `_track_window` — test helpers
- `q` keymap — calls `M.close_cling_window()`, window lifecycle

## Consequences

### Positive

- **Navigation bugs concentrate in one module.** `jump_to` and `export` are
  the most behaviour-rich parts of the executor; they now have a home where
  changes are localised and testable.
- **Tests hit the interface, not keymap callbacks.** `navigation_spec.lua`
  calls `nav.jump_to(line, cfile, cwd, win)` and `nav.export(buf, cmd, cwd,
  path)` directly — no `nvim_buf_get_keymap`, no terminal jobs, no
  `core.executor` setup.
- **`temp_efm` stops being a disguised literal.** It is a named constant
  (`DEFAULT_EFM`) in one place, with a clear purpose.
- **Quickfix save/restore is eliminated.** The inline `getqflist({ lines=...,
  efm=... })` call is one line, not ten, and does not touch global state.
- **`core_spec.lua`'s real-terminal jobs shrink to spawn coverage.** The
  export and jump tests move to `navigation_spec.lua` where they run with
  plain buffers and temp files. `core_spec.lua` retains only wiring tests
  (keymap registration) and lifecycle tests (spawn, close, column capture).

### Negative / Neutral

- **Migration cost.** `core.lua` loses `export_output` and the `<CR>` callback
  body; `navigation.lua` is a new file; `core_spec.lua` loses the export
  behaviour tests and gains thin wiring-only tests; `navigation_spec.lua` is
  new.
- **Known limitations preserved.** The cfile-vs-efm-filename path resolution
  discrepancy, the silent return on missing files, and the missing empty-items
  guard are all preserved. They are documented here and deferred to separate,
  testable changes.
- **Closure captures remain.** `actual_cwd` and `original_window` are still
  captured in the executor's closure and passed as parameters to `jump_to`.
  This is the simplest approach and matches the current structure, but means
  `jump_to` is not callable without the executor having run first (in
  production). Tests bypass this by calling `jump_to` directly with synthetic
  values.
- **`navigation.lua` depends on `vim.fn.getqflist`, `vim.uv.fs_stat`,
  `vim.fn.win_execute`, and `vim.fs`.** These are real vim APIs — tests use
  real buffers and temp files rather than mocks, which means tests still need
  a Neovim runtime (headless is fine). The trade-off is simpler tests at the
  cost of requiring the Neovim test harness.

## Alternatives Considered

1. **Status quo (leave navigation inline in executor).** Rejected: the most
   valuable behaviour is untestable, `temp_efm` is a disguised literal, and
   the quickfix save/restore is unnecessary ceremony. The 775-line test suite
   cannot assert what `<CR>` does.

2. **Split `jump_to` into `parse_location` + `open_location` (Option C from
   grilling).** Rejected: the decomposition adds a third function and an
   intermediate type (`{file, lnum, col}`) for no testability gain — the real
   testing constraint is `vim.uv.fs_stat` and `vim.fn.win_execute`, not the
   parsing step. One function with a clear name is simpler.

3. **Make `nav` buffer-aware (`jump_to(buf, cwd, target_win)` reads cursor
   state itself).** Rejected: coupling `jump_to` to `nvim_get_current_line` and
   `expand("<cfile>")` makes it harder to test — tests would need to set cursor
   position in a buffer before calling. Passing `line` and `cfile` as
   parameters is trivially testable.

4. **Move the prompt into `nav.export`.** Rejected: `vim.fn.input` is a UI
   concern. Keeping it in the executor means `nav.export` is testable with a
   plain filepath string — no UI dependency.

5. **Also extract `build_split_cmd` or column capture.** Rejected as scope
   creep. `build_split_cmd` is about terminal window creation, not navigation.
   Column capture is Candidate 4's scope. This ADR is scoped to the
   navigation behaviour only.

## Resolved Decisions (from grilling)

### Round 1 — Interface & Boundary

1. **`jump_to` signature (Q1.1):** `nav.jump_to(line, cfile, cwd, target_win)`
   — the keymap callback extracts cursor state (`nvim_get_current_line`,
   `expand("<cfile>")`) and passes it as parameters. Nav owns parsing + path
   resolution + `win_execute`.

2. **Export scope (Q1.2):** Both `jump_to` and `export` in one
   `navigation.lua` module. Both operate on terminal output buffers.

3. **Quickfix parsing (Q1.3):** Replace the 10-line save/restore dance with
   `vim.fn.getqflist({ lines = {...}, efm = DEFAULT_EFM })`. No global state
   pollution. One line instead of ten.

### Round 2 — Internals & Wiring

4. **Line trimming (Q2.1):** Preserve current behaviour — `line:find(cfile)`
   + `line:sub(start_idx)` trimming, `cfile` for path resolution (not efm-parsed
   filename). Documented as a known limitation.

5. **Closure captures (Q2.2):** `actual_cwd` and `original_window` remain as
   closure captures in the executor's keymap callbacks. Passed as parameters
   to `jump_to`.

6. **Export prompt (Q2.3):** The `vim.fn.input` prompt stays in the executor's
   `ge` keymap callback. `nav.export(buf, cmd, cwd, filepath)` receives the
   resolved path.

7. **`q` keymap (Q2.4):** Stays in executor — calls `M.close_cling_window()`.
   Window lifecycle, not navigation.

### Round 3 — Errorformat, Paths & Testing

8. **`DEFAULT_EFM` location (Q3.1):** Module-local constant in
   `navigation.lua`. Callers never see it. Not a parameter, not exported.

9. **Path resolution edges (Q3.2):** Preserve all: silent `return` on missing
   file, `joinpath(cwd, cfile)` with fallback to `cfile`, no extra escaping
   beyond `fnameescape`. Documented as known limitations.

10. **Empty-items guard (Q3.3):** Preserve — no guard on `#items == 0`. If efm
    doesn't match, `items[1].lnum` errors. This is current behaviour.

11. **Testing strategy (Q3.4):** Real buffers, no terminal. `export` tested
    with plain created buffers (`nvim_create_buf` + `nvim_buf_set_lines`).
    `jump_to` tested with real temp files (`os.tmpname`) in headless Neovim —
    create a file, put its path in a line, call `jump_to`, assert the target
    window opened it at the right line/col.

### Round 4 — Module, Tests & Scope

12. **Module name (Q4.1):** `navigation.lua` (full name). `require
    "cling.navigation"`.

13. **Test migration (Q4.2):** Move export behaviour tests and add new
    `jump_to` tests to `tests/cling/navigation_spec.lua`. Keep keymap
    existence tests in `core_spec.lua` (they verify wiring). `core_spec.lua`
    loses export behaviour tests but keeps wiring and lifecycle tests.

14. **Scope (Q4.3):** Complete: only `export_output` and the `<CR>` callback
    body move. `build_split_cmd`, column capture, `close_cling_window`, and
    all other `core.lua` functions stay.

15. **Footer format (Q4.4):** Internal to `nav.export` — not configurable. The
    metadata footer (Command, CWD, Timestamp, modeline) is hard-coded inside
    the function.

## All Open Questions Resolved

All 15 questions from the grilling process are resolved. The design is ready
for implementation.