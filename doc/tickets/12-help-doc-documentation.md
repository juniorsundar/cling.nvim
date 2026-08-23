# 12: Document the expansion grammar in README.md

**What to build:** The expansion grammar is documented in `README.md` so users
can discover the marker, the supported tokens, the modifier families, the
`@@` escape, and the execution-CWD resolution rule without reading source. The
vimdoc (`doc/cling.nvim.txt`) is a *derived* artifact: the `docs.yml` workflow
runs `panvimdoc` over `README.md` on every push to `main` and auto-commits the
regenerated `cling.nvim.txt`. So this slice edits `README.md` only and must
**not** hand-edit `doc/cling.nvim.txt` — the workflow regenerates it. Written
once all behavior slices are stable and the guarantee matrix is locked, so the
docs describe the shipped behavior rather than aspirational detail.

**Blocked by:** 11 (Passthrough & escape guarantee matrix)

**Status:** ready-for-agent

- [ ] A new section in `README.md` describes the `@` marker and the opt-in (shell-literal-by-default) expansion model
- [ ] The section lists every supported token (`%`, `#`, `#N`, `<cword>`, `<cWORD>`, `<cfile>`) with examples
- [ ] The section lists the modifier families (path `:p :~ :.`, anatomy `:h :t :r :e`, shell-safety `:S :q`) with chain examples
- [ ] The section documents the `@@` escape and the passthrough of unmarked specials (`%`, `#`, `<`, `>`, backticks)
- [ ] The section notes that relative modifiers resolve against the execution CWD chosen at the prompt, not the editor's CWD
- [ ] The section notes that wrapper commands do not expand markers (out of scope, by design)
- [ ] `doc/cling.nvim.txt` is NOT hand-edited — it is left for the `docs.yml` workflow to regenerate from the updated `README.md`