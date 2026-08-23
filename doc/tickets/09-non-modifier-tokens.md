# 09: Non-modifier tokens — `@#`, `@#n`, `@<cword>`, `@<cWORD>`, `@<cfile>`

**What to build:** The expansion module's recognized-token set grows to cover
every remaining non-modifier token, so that after this slice a user can
reference any buffer or cursor location inline. Cat 1: `@#` (alternate file)
and `@#N` (buffer N's file, multi-digit N parsed). Cursor-based: `@<cword>`
(punctuation-delimited word under the cursor), `@<cWORD>` (whitespace-delimited
WORD, punctuation preserved so `foo.bar` survives as one argument), and
`@<cfile>` (file path under the cursor). The cursor state is supplied through
the injectable context provider established in ticket 01, read from the window
under the cursor when the prompt opened, so the expansion logic has no hard
dependency on window/buffer state and tests inject fakes. The existing `@%`
behavior from ticket 01 is unchanged, and all three entry points (interactive,
`--`, `run_last`) already wired in ticket 01 expand these new tokens for free.

**Blocked by:** 08 (Expansion module foundation)

**Status:** ready-for-agent

- [x] `@#` expands to the alternate file's path
- [x] `@#N` expands to buffer N's file path, with multi-digit N parsed correctly
- [x] `@<cword>` expands to the punctuation-delimited word under the cursor
- [x] `@<cWORD>` expands to the whitespace-delimited WORD under the cursor (punctuation preserved)
- [x] `@<cfile>` expands to the file path under the cursor
- [x] Cursor context is read through the injected context provider; production wires the real provider (current window under the prompt), tests inject fakes
- [x] Unmarked `#`, `#N`, `<`, and `>` pass through unchanged — shell comments and redirections unaffected
- [x] `@%` behavior from ticket 01 is unchanged
- [x] Module tests cover each token, buffer-number parsing, and unmarked-`#`/`<>` passthrough, using injected context with no host window/buffer dependency