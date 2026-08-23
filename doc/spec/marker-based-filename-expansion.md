# Spec: Marker-based (`@`) filename expansion in Cling commands

## Problem Statement

As a cling.nvim user, I compose shell commands against my editing session — I
want to `cat %` the file I'm working on, grep for `<cword>`, or reference the
alternate file with `#`. Today Cling hands my command line straight to
`sh -c`, where Vim's special characters either do nothing (`%` passes through
literally), collide with live shell syntax (`#` starts a comment, so `#3` can
never work), or actively misbehave (`<cfile>` parses as stdin redirection, so
`grep <cword> x` reads a file named `cword`). There is no way to get
Vim-standard filename semantics out of a Cling command, and no way to know
which interpretation a given character will receive.

## Solution

Expansion becomes opt-in through an `@` marker. A command line stays
shell-literal by default — every existing command behaves exactly as before.
When I glue `@` to a recognized token (`@%`, `@#`, `@#3`, `@<cword>`,
`@<cWORD>`, `@<cfile>`), Cling consumes the marker and expands the token —
including filename-modifier chains like `@%:p:h:t` — before the shell ever
sees the string. Any other `@` passes through untouched, and `@@` yields a
literal `@`. Tokens resolve against the working directory I choose at the CWD
prompt, and my command history stores what I typed (`cat @%`), so replays
re-expand against whatever buffer is current when I run them.

## User Stories

1. As a plugin user, I want to type `cat @%` in the Cling prompt, so that the
   current file's path replaces the token before the command runs.
2. As a plugin user, I want to type `@#`, so that the alternate file's path is
   substituted and I can diff or toggle between two files in one command.
3. As a plugin user, I want to type `@#3`, so that buffer 3's file path is
   substituted without looking it up by name.
4. As a plugin user, I want to type `grep @<cword> src/`, so that the word
   under my cursor becomes the search pattern.
5. As a plugin user, I want to type `grep @<cWORD> src/`, so that a cursor
   WORD containing punctuation (e.g. `foo.bar`) survives as one argument.
6. As a plugin user, I want to type `make @<cfile>`, so that the file path
   under my cursor is passed to the command.
7. As a plugin user, I want modifier chains such as `@%:p`, `@%:h`, `@%:t`,
   `@%:r`, `@%:e`, `@%:~`, and `@%.`, so that I can derive directories,
   extensions, and relative forms inline.
8. As a plugin user, I want chained modifiers like `@%:p:h:t`, so that I can
   express multi-step path derivation in one token.
9. As a plugin user, I want `@%:S` and `@%:q`, so that filenames containing
   spaces arrive correctly quoted at the shell.
10. As a plugin user, I want any `@` NOT followed by a recognized token to
    pass through untouched, so that `me@example.com` and other incidental
    uses never corrupt my command.
11. As a plugin user, I want `@@` to produce a literal `@`, so that I can
    echo or document the marker syntax itself.
12. As a plugin user, I want unmarked `%`, `#`, `<`, and `>` to behave exactly
    as the shell treats them today, so that `printf '%s\n' hi`,
    `sort < list > out`, ``echo `date` `` and `make build # note` all keep
    working.
13. As a plugin user, I want expansion applied only to marked tokens, so that
    learning the feature costs nothing until I use it.
14. As a plugin user, I want the Cling command history to store the raw typed
    line (e.g. `cat @%`) rather than the expanded text, so that replaying an
    entry tomorrow expands against tomorrow's buffer and CWD.
15. As a plugin user, I want `run_last` to re-expand the stored raw command at
    execution time, so that repeating the last command reflects my current
    editing context.
16. As a plugin user, I want tokens resolved against the working directory I
    confirm at the CWD prompt, so that relative forms mean "relative to where
    this command runs".
17. As a plugin user, I want expansion available on the interactive prompt and
    the `--` argument path alike, so that both ways of handing Cling a raw
    shell line share the same semantics.
18. As a plugin user, I want wrapper commands (e.g. generated binary wrappers)
    to remain purely literal, so that their argument contracts do not silently
    change.
19. As a plugin user, I want a malformed marker (e.g. `@` at end of input, or
    `@x` where `x` matches nothing recognized) to pass through literally, so
    that partial knowledge of the grammar never destroys my command.
20. As a plugin user, I want cursor-based tokens read from the window under
    the cursor when I opened the prompt, so that "the word under my cursor"
    matches what I was looking at.
21. As a plugin user, I want documentation of the grammar in the help docs, so
    that I can discover tokens, modifiers, and the escape rule without reading
    source.

22. As a plugin maintainer, I want the expander isolated in its own module as
    a pure transformation from (command line, execution CWD) to expanded
    command line, so that the feature is independently testable and the
    orchestration layer stays thin.
23. As a plugin maintainer, I want editor-dependent inputs (cursor word, WORD,
    cfile) supplied through an injected context provider rather than read
    inside the expander, so that the expansion logic has no hard dependency on
    window/buffer state during tests.
24. As a plugin maintainer, I want the scanner rule expressed once — marker
    followed by recognized token expands, everything else passes through — so
    that there is exactly one place defining what counts as an expansion site.
25. As a plugin maintainer, I want each token resolved to an absolute path
    first and relative modifiers recomputed against the execution CWD
    afterward, so that execution-relative resolution is correct even when the
    editor's CWD differs.
26. As a plugin maintainer, I want modifiers applied left-to-right in chain
    order, so that chains match Vim's own modifier composition semantics.
27. As a plugin maintainer, I want the recognized-token set limited to `%`,
    `#`, `#N`, `<cword>`, `<cWORD>`, `<cfile>`, so that autocommand and script
    context tokens never silently expand to empty strings.
28. As a plugin maintainer, I want the substitution modifiers (`:s///`,
    `:gs///`) excluded from the supported set, so that the parser never needs
    delimiter-aware parsing of arbitrary regex text.
29. As a plugin maintainer, I want expansion to run after both prompts resolve
    (command and CWD), so that the execution-CWD frame is known before any
    relative modifier is computed.
30. As a plugin maintainer, I want the `.env` prefix-injection step in the
    executor to operate on the already-expanded command, so that environment
    sourcing cannot reorder or corrupt expansion output.
31. As a plugin maintainer, I want the feature wired into the two raw-line
    entry points only, so that wrapper callbacks, completion functions, and
    generator subprocesses are provably untouched.
32. As a plugin maintainer, I want the design rationale recorded in ADR-003,
    so that future contributors understand why expansion is marker-gated
    instead of following Vim's always-expand `:!` semantics.

33. As a test author, I want to drive the expander as a plain function call,
    so that expansion tests need no terminal jobs, splits, or prompt
    interactions.
34. As a test author, I want to inject fake cursor context (word, WORD,
    cfile) and fake buffer names, so that every token and modifier case is
    deterministic regardless of the host Neovim state.
35. As a test author, I want table-driven coverage of the passthrough rules
    (bare `@`, `@@`, emails, quoted percent, comments), so that the
    zero-casualty guarantee is regression-locked.

## Implementation Decisions

- **New expansion module.** A dedicated module owns scanning and expansion.
  Its public surface is one function: given the raw command line and the
  execution CWD, return the expanded command line. An options table carries
  an injectable cursor-context provider for the three cursor-based tokens;
  production wires the real provider (current window under the prompt),
  tests inject fakes.

- **Scanner rule (single source of truth).** Scan left to right. An `@`
  immediately followed by a recognized token opens an expansion site: the
  marker is consumed, the token plus its full modifier chain is expanded,
  and scanning resumes after it. Any other `@` is copied verbatim. `@@` is
  copied as a single literal `@`.

- **Recognized tokens:** `%`, `#`, `#<number>`, `<cword>`, `<cWORD>`,
  `<cfile>`. Autocommand and script-context tokens are deliberately outside
  the set (ADR-003).

- **Supported modifiers:** path (`:p`, `:~`, `:`.`), anatomy (`:h`, `:t`,
  `:r`, `:e`), shell-safety (`:S`, `:q`). Chains apply left-to-right.
  Substitution modifiers are unsupported and, if encountered, terminate
  token recognition (making the site fall back to passthrough) rather than
  being partially parsed.

- **Resolution frame.** Each marked token resolves to its absolute path
  first; relative modifiers (`:.`, `:~`) are then recomputed against the
  execution CWD chosen at the second prompt. This ordered application
  replaces delegating wholesale to built-in expansion helpers.

- **No reliance on `expandcmd()`.** The builtin has no trigger-prefix mode,
  always-expands unconditionally, and exposes backtick expression
  evaluation from the prompt. It is rejected as the engine (ADR-003).

- **Wiring points.** Expansion hooks into three sites, all of which handle
  raw shell lines: after both interactive prompts resolve, in the `--`
  passthrough branch (execution CWD = current working directory), and in
  the replay path for stored raw commands (`run_last`). The env-file flow
  needs no separate hook — its final prompt resolves through the
  interactive path. With unified (non-separated) history, replays re-enter
  through the interactive prompt and are covered by the first site.
  History recording continues to store the pre-expansion string; the
  executor's environment-file prefixing operates downstream of expansion.
  Wrapper command callbacks are unchanged.

- **History contract.** Both `last_cmd` and per-CWD history store raw lines;
  all consumers that re-execute (`run_last`, history replay) go back through
  expansion at execute time.

## Testing Decisions

- **What makes a good test here.** Tests assert the observable output of the
  expander — the returned command line — for a given input line, execution
  CWD, and injected context. They never inspect internal scanner state,
  helper functions, or how many times the context provider was called beyond
  what behavior requires. Wiring tests (that the two entry points actually
  invoke expansion) stay thin; behavior lives at the module seam.

- **The seam.** One new seam: the expansion module's function boundary, with
  the cursor-context provider injected. This is the highest seam at which
  the feature can be tested without driving prompts, splits, or terminal
  jobs; no other seams are added. Entry-point wiring is covered by asserting
  that executor receives expanded strings, mirroring how existing specs stub
  the executor boundary.

- **Modules tested.** The expansion module (exhaustively: every token, every
  modifier, chains, escaping, all passthrough classes, execution-CWD-relative
  resolution) and lightly, the command entry-point wiring.

- **Prior art.** Three existing patterns combine here:
  `navigation_spec.lua` established testing extracted modules directly with
  plain values and temp files instead of driving the executor;
  `command_node_find_spec.lua` establishes pure-function test style with
  injected dependencies (filesystem completer — the cursor-context provider
  is the analogous injection); and `cli_spec.lua` already wires
  `on_cli_command` end-to-end by stubbing `vim.fn.input` and `core.executor`
  and asserting exactly which string reaches the executor — expansion-wiring
  tests extend that file with marked inputs (`cat @%` in, expanded string
  asserted at the executor stub) plus a new case for the replay path.

- **Harness.** plenary.nvim + busted under headless Neovim via
  `minimal_init.lua`, consistent with the suite. Most cases are pure Lua and
  need no fixtures; execution-CWD cases use temporary directories.

## Out of Scope

- **Wrapper-command expansion.** Wrapped binaries keep literal arguments;
  changing their contract is a separate decision (ADR-003).
- **Autocommand and script tokens** (`<afile>`, `<abuf>`, `<amatch>`,
  `<sfile>`, `<slnum>`). Meaningless outside their contexts.
- **Substitution modifiers** (`:s///`, `:gs///`). Excluded by design.
- **Always-expand / backslash-suppression modes.** Rejected in ADR-003; the
  backslash plays no role in this feature's vocabulary.
- **Live preview or completion of expansions while typing.** The prompt shows
  raw text; expansion happens at execution time.
- **Editor-CWD resolution option or configurability of the marker.** The
  execution-CWD frame and `@` marker are fixed decisions (ADR-003);
  configurability is deferred until a concrete need appears.

## Further Notes

- This spec implements ADR-003 ("Marker-based (`@`) filename expansion"),
  produced through a grilling process in which all eight decision branches
  were explicitly resolved, including two reversals (model polarity flipped
  from always-expand to opt-in; backslash re-examined and declined as
  marker).
- Vocabulary follows `doc/glossary.md`; this feature introduces four new
  terms — **marker**, **expansion**, **token**, **modifier chain** — defined
  in ADR-003 and pending addition to the glossary.
- The zero-shell-casualty property (user story 12/35) is the load-bearing
  guarantee of this design: the entire existing behavior space of Cling
  commands is unchanged unless the marker appears.
