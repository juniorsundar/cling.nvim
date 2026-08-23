# ADR-003: Marker-based (`@`) filename expansion in Cling commands

## Status

Accepted — all grilling questions resolved

## Context

Cling passes user-typed command lines to `sh -c 'cd <cwd> && <cmd>'`
(`core.executor`). Vim users instinctively type `%` for "current file",
`#`/`#n` for alternate/buffer files, `<cword>`/`<cWORD>`/`<cfile>` for
cursor content — but today these either do nothing useful or collide with
live shell syntax:

- `%` passes through literally (harmless in non-interactive `sh -c`, so
  expansion would *change* behaviour for existing literal uses like
  `printf '%s\n'`).
- `#` is the shell comment character; `#3` can never work unescaped.
- `<cword>` etc. parse as stdin/stdout redirection (`<`, `>`) —
  `grep <cword> x` silently reads a file named `cword`.

Two competing semantics exist:

1. **Vim `:!` semantics** — always expand, backslash suppresses (`\%`).
   Maximum Vim parity, but breaks every literal `%`-dense or `#`-comment
   shell one-liner unless the user remembers to escape.
2. **Shell-literal default with an opt-in marker** — nothing changes unless
   the user explicitly marks a token for expansion.

The design was settled through grilling (all questions resolved below).

## Decision

Expansion is **opt-in via an `@` marker**, applied at execution time:

> An `@` immediately followed by a recognized token is consumed by Cling and
> expands the token (plus modifier chain) before the command reaches the
> shell. Any other `@` passes through untouched. `@@` yields a literal `@`.

### Grammar

| Input | Expansion |
|---|---|
| `@%` | current file |
| `@#` | alternate file |
| `@#N` | file for buffer N |
| `@<cword>` / `@<cWORD>` | word / WORD under cursor |
| `@<cfile>` | file path under cursor |
| `@%:p:h:t:r:e:~:.:S:q` | modifier chains, resolved left-to-right |

Examples:

```
cat @%                → cat /path/to/current.lua
grep @<cWORD> src/    → grep WordUnderCursor src/
make @%:t:r.o         → make cling.o
echo me@example.com   → untouched   (@ not followed by a token)
printf '%s\n' hi      → untouched   (no marker, no expansion)
echo "type @@%"       → echo "type @%"
```

### Scope decisions

- **Tokens**: Cat 1 (`%`, `#`, `#n`) + cursor-based Cat 2 (`<cword>`,
  `<cWORD>`, `<cfile>`). Autocommand (`<afile>`/`<abuf>`/`<amatch>`) and
  script (`<sfile>`/`<slnum>`) expansions are excluded — meaningless outside
  their contexts.
- **Modifiers**: path (`:p :~ :.`), anatomy (`:h :t :r :e`), shell-safety
  (`:S :q`). Substitution modifiers (`:s///`, `:gs///`) are excluded.
- **History**: stores the **raw typed line** (`cat @%`), expanded at execute
  time — replay reflects tomorrow's buffer/CWD, not yesterday's.
- **Entry points**: the interactive prompt and the `--` fargs path only.
  Wrapper commands keep pure-literal semantics.
- **Resolution frame**: tokens resolve against the **execution CWD**
  (chosen in the second prompt), not the editor's CWD.

### Implementation shape

New module `lua/cling/expand.lua`: scanner + expander as a pure function
`(string, cwd) → string`. Because resolution is execution-CWD-relative,
each token resolves to its absolute path first, then remaining modifiers
(`:.`, `:~`) are recomputed against the chosen CWD — ordered modifier
application, not a single `expand()` call. Hooked into `on_cli_command`
after both prompts resolve, and into the `fargs[1] == "--"` branch.

## Consequences

- **Zero shell casualties**: `printf '%s\n'`, cron lines, comments,
  redirection, command substitution all behave exactly as before. The
  feature is invisible until the marker is typed.
- **Deliberate divergence from Vim**: bare `%` does *not* expand, and `\`
  plays no role in this feature's vocabulary at all. Users must learn one
  new character (`@`); Vim's always-expand reflex does not transfer.
- **Execution-CWD resolution costs code**: relative modifiers require
  ordered application against the exec CWD rather than delegating wholesale
  to `vim.fn.expand()` / `expandcmd()`.
- **`vim.fn.expandcmd()` is rejected** as the engine — it has no
  trigger-prefix mode, always-expands unconditionally, and additionally
  exposes backtick expression evaluation from the prompt.

## Alternatives Considered

1. **Always expand with backslash suppression (Vim `:!` semantics).**
   Rejected: taxes every `%`-dense shell snippet (`printf '%s\n'`,
   crontab entries) and kills `#` comments unless escaped. The user's
   priority was preserving applicable shell literals.
2. **Always expand + single-quote carve-out** (never expand inside single
   quotes). Rejected alongside (1): it patches most of (1)'s casualties but
   adds a quote-state scanner *and* keeps the divergence problems of
   unconditional expansion.
3. **Backtick marker** (`` cat `% ``). Rejected: backtick is live shell
   syntax for command substitution; although the scanner rule protects it,
   the collision surface was judged not worth it.
4. **Comma or backslash markers**. `,` — viable runner-up, unshifted typing,
   zero collisions, no mnemonic pull. `\` — rejected: `\%`/`\#` occur for
   real inside quoted strings (`grep '\%' f`), and its Vim association is
   inverted (in Vim, `\%` *suppresses*, never triggers).
5. **`%%` doubling instead of a separate marker.** Rejected: collides with
   real idioms (`printf '%%'`, doubled-hash comments).
6. **Editor-relative resolution** (native `expand()` frame). Rejected:
   surprising when the second prompt selects a different execution
   directory; the user chose explicit execution-relative semantics.

## Resolved Decisions (from grilling)

1. **Model (Q1)**: opt-in marker over shell-literal default — reversed an
   initial lean toward always-expand after the casualty analysis.
2. **Marker (Q9)**: `@`; inert in POSIX sh, visible when glued to a token,
   Vim-register mnemonic. Backslash re-examined late and declined on
   quoted-string collision risk.
3. **Literal escape (Q8′)**: `@@` → literal `@` (the `printf %%` trick).
4. **Token scope (Q4)**: three cursor expansions kept; autocmd/script
   expansions dropped.
5. **Modifier scope (Q5-discussion)**: `:S`/`:q` promoted from "substitution"
   to shell-safety essentials (spaces in filenames).
6. **History (Q5)**: raw typed line, expanded at execute time.
7. **Entry points (Q6)**: prompt + `--` path; wrappers stay literal.
8. **Resolution frame (Q7)**: execution CWD.

## All Open Questions Resolved

The design tree closed with no open branches. Implementation:
`lua/cling/expand.lua` + hooks in `on_cli_command`, tests under `tests/`.
