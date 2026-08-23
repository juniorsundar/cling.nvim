# 07: Add jump_to to navigation module

**What to build:** The `jump_to(line, cfile, cwd, target_win)` function is added to the `navigation` module. It converts a line of terminal output into a file open action: finds `cfile` in the line and trims to that position, parses the trimmed line with a module-local `DEFAULT_EFM` constant via `vim.fn.getqflist({ lines = {...}, efm = ... })` (replacing the 10-line quickfix save/restore dance), extracts `lnum`/`col` from the parsed result, resolves the file path relative to `cwd` with a fallback to `cfile` alone, and opens the file in `target_win` via `win_execute` with the cursor positioned at the parsed line/column. The executor's `<CR>` keymap callback shrinks to extracting the current line and `<cfile>` from the cursor and delegating to `navigation.jump_to`. All existing behaviour is preserved exactly — including the known limitations (cfile used for path resolution instead of the efm-parsed filename, silent return on missing file, no empty-items guard). These are the first tests for the jump behaviour in the project; they use real temp files in headless Neovim, no terminal jobs.

**Blocked by:** 06 (Create navigation module with export function)

**Status:** done

- [x] `navigation.jump_to(line, cfile, cwd, target_win)` exists in the navigation module
- [x] `DEFAULT_EFM` is a module-local constant (`table.concat({ "%f:%l:%c:%m", "%f:%l:%c", "%f:%l" }, ",")`), not exported, not a parameter
- [x] `jump_to` finds `cfile` in the line via `line:find(cfile, 1, true)` and trims with `line:sub(start_idx)` (preserving current trimming behaviour)
- [x] `jump_to` parses the trimmed line with `vim.fn.getqflist({ lines = { trimmed_line }, efm = DEFAULT_EFM })` — a single call, no global quickfix save/restore
- [x] `jump_to` extracts `lnum` and `col` from `items[1]` with no empty-items guard (preserving current behaviour)
- [x] `jump_to` resolves the path: `vim.fs.joinpath(cwd, cfile)`, falls back to `cfile` if the joined path doesn't exist but `cfile` does, silently returns if neither exists
- [x] `jump_to` checks `target_win` validity and notifies "Original window is no longer valid" if invalid
- [x] `jump_to` opens the file via `win_execute(target_win, "edit +" .. lnum .. " " .. fnameescape(full_path))`, appending `" | normal! " .. col .. "|"` when `col` is a number > 0
- [x] `jump_to` sets focus to `target_win` via `nvim_set_current_win`
- [x] The executor's `<CR>` keymap callback extracts `nvim_get_current_line()` and `expand("<cfile>")` and delegates to `nav.jump_to(line, cfile, actual_cwd, original_window)`
- [x] The `<CR>` callback no longer contains efm construction, quickfix manipulation, path resolution, or win_execute logic
- [x] `navigation_spec.lua` has a test: `jump_to` opens a file at the correct line and column when the line contains `file:line:col:message` (using a real temp file)
- [x] `navigation_spec.lua` has a test: `jump_to` opens a file at the correct line when the line contains `file:line` without column
- [x] `navigation_spec.lua` has a test: `jump_to` resolves the file path relative to the provided `cwd`
- [x] `navigation_spec.lua` has a test: `jump_to` falls back to `cfile` alone when the joined path doesn't exist but `cfile` does
- [x] `navigation_spec.lua` has a test: `jump_to` silently returns when the file doesn't exist at either path (no error, no window change)
- [x] `navigation_spec.lua` has a test: `jump_to` notifies when the target window is no longer valid
- [x] `navigation_spec.lua` has a test: `jump_to` trims the line to start from the `cfile` position before parsing
- [x] `core_spec.lua` retains any existing `<CR>` keymap existence test (unchanged — verifies wiring)
- [x] The 10-line quickfix save/restore dance is gone from `core.lua`
- [x] The `temp_efm` inline literal is gone from `core.lua` (replaced by `DEFAULT_EFM` in navigation)
- [x] All existing tests pass