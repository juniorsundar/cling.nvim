# 06: Create navigation module with export function

**What to build:** The `navigation` module is born. It owns the `export(buf, cmd, cwd, filepath)` function, which reads all lines from a buffer, strips trailing empty lines, appends a four-line metadata footer (Command, CWD, ISO 8601 Timestamp, `vim: ft=log` modeline), and writes the result to the given filepath via `fs.write_file`. The `export_output` free function is removed from `core.lua`. The executor's `ge` keymap callback keeps the interactive `vim.fn.input` prompt (a UI concern) but delegates the writing to `navigation.export`, passing the resolved filepath. The existing export behavior tests — "exports buffer content to file with metadata" and "export preserves ANSI escape codes" — move from `core_spec.lua` to a new `navigation_spec.lua` where they call `nav.export` directly with a plain created buffer (no terminal job, no `core.executor` setup, no keymap fetching). The wiring test ("registers ge keymap on the output buffer") and the cancel test ("export cancels when input is empty") stay in `core_spec.lua` because they test executor-level wiring and prompt logic, not export behavior.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] `navigation` module exists with an `export(buf, cmd, cwd, filepath)` function
- [x] `export` reads all lines from the buffer via `nvim_buf_get_lines`
- [x] `export` strips trailing empty lines from the content
- [x] `export` appends metadata footer: Command, CWD, ISO 8601 Timestamp, `vim: ft=log` modeline
- [x] `export` writes the result to `filepath` via `fs.write_file`
- [x] `export` notifies the user on success ("Output exported to ...") and on failure ("Failed to export to ...")
- [x] The `export_output` free function is removed from `core.lua`
- [x] The executor's `ge` keymap callback keeps the `vim.fn.input` prompt and delegates to `navigation.export`
- [x] The `ge` callback returns early when the prompt is cancelled or returns an empty string (no `nav.export` call)
- [x] `core.lua` requires `cling.navigation` at the top
- [x] `navigation_spec.lua` exists with a test: `export` writes buffer content with metadata footer to a file (using a plain created buffer, calling `nav.export` directly)
- [x] `navigation_spec.lua` has a test: `export` preserves ANSI escape codes in the output
- [x] `navigation_spec.lua` has a test: `export` strips trailing empty lines before writing
- [x] `core_spec.lua` retains the "registers ge keymap on the output buffer" wiring test (unchanged)
- [x] `core_spec.lua` retains the "export cancels when input is empty" test (unchanged — tests the prompt logic in the executor callback)
- [x] The "exports buffer content to file with metadata" test is removed from `core_spec.lua` (now lives in `navigation_spec.lua`)
- [x] The "export preserves ANSI escape codes" test is removed from `core_spec.lua` (now lives in `navigation_spec.lua`)
- [x] All existing tests pass