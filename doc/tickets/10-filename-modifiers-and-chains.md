# 10: Filename modifiers + chains + execution-CWD resolution

**What to build:** The expansion module applies filename modifiers to marked
tokens, left-to-right, across three families: path (`:p`, `:~`, `:`.`),
anatomy (`:h`, `:t`, `:r`, `:e`), and shell-safety (`:S`, `:q`). Chains
compose in order (e.g. `@%:p:h:t`). Each token resolves to its absolute path
first, and relative modifiers (`:.`, `:~`) are then recomputed against the
execution CWD chosen at the second prompt — so `@%.` means "relative to where
this command runs" even when that CWD differs from the editor's. The
substitution modifiers (`:s///`, `:gs///`) are unsupported and, when
encountered, terminate token recognition so the whole marked site falls back
to passthrough rather than being partially parsed. Modifiers apply to every
supported token (`%`, `#`, `#N`, `<cword>`, `<cWORD>`, `<cfile>`).

This slice depends on the non-modifier tokens (ticket 02) so that modifiers
can be verified against the full token set — including the cursor tokens,
since the modifier engine must work for them too.

**Blocked by:** 08 (Expansion module foundation), 09 (Non-modifier tokens)

* **Status:** complete

- [x] `@%:p`, `@%:~`, `@%.` produce absolute, home-relative, and CWD-relative forms
- [x] `@%:h`, `@%:t`, `@%:r`, `@%:e` produce head (directory), tail (filename), root (no extension), and extension
- [x] `@%:S` and `@%:q` shell-quote the path so filenames containing spaces arrive correctly at the shell
- [x] Chains apply left-to-right (`@%:p:h:t` resolves step by step)
- [x] Relative modifiers (`:.`, `:~`) resolve against the execution CWD, not the editor CWD; a command run in a different CWD than the editor's sees `.`/`~` relative to where it runs
- [x] Modifiers apply to all supported tokens, not only `@%`
- [x] `@%:s/a/b/` and `@%:gs/a/b/` fall back to passthrough — the marked site is returned verbatim, not partially expanded
- [x] Module tests cover each modifier, multi-step chains, and execution-vs-editor CWD resolution cases