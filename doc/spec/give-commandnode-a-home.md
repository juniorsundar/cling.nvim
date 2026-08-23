# Spec: Give CommandNode a home

## Problem Statement

As a maintainer of cling.nvim, I find that the completion tree's shape — the
`CommandNode` record with its `flags`, `subcommands`, and optional
`completion_type` fields — is duplicated knowledge across at least six sites in
the codebase. Adding a single field means editing every site by hand, with
nothing — no type, no constructor, no test — forcing them to agree. The query
logic that walks the tree to produce completion candidates is trapped inside a
~45-line inline closure in `setup()`, mixing tree descent, a hard-coded plugin
special case, and filesystem completion. There are zero tests covering wrapper
completion today. The grab-bag `utils` module bundles generic file I/O with a
tree-specific serializer that hard-codes node field names, failing the deletion
test. I want the tree's shape to live in one place so that changes are local,
the query logic is testable in isolation, and the grab-bag module is gone.

## Solution

Create a single `command_node` module that owns the entire lifecycle of the
completion tree: building it (parse), persisting it (serialize, load), and
querying it (find). Every site that currently constructs a `CommandNode` by
hand — parsers, crawlers, generator, setup — uses a constructor from this
module instead. The inline completion closure in `setup()` shrinks to a thin
caller that splits the command line, calls `find()`, and appends the one
plugin-specific special flag. The query function is pure: filesystem completion
is injected, not hardcoded. A new `fs` module absorbs the generic file I/O
that was in `utils`, and both `utils` and `parser` are deleted.

## User Stories

1. As a plugin maintainer, I want the `CommandNode` shape (fields, defaults,
   constructor) defined in exactly one module, so that adding a field requires
   changing only that module and its serialize/find functions.

2. As a plugin maintainer, I want a `command_node.new()` constructor that
   returns a well-formed node with `flags` and `subcommands` initialized to
   empty tables, so that every node in the system — whether built by parsers,
   crawlers, generator, or tests — has guaranteed fields.

3. As a plugin maintainer, I want `parse`, `parse_help`, and `parse_bash` to
   live in the `command_node` module, so that the tree-building logic and the
   tree-shape definition are co-located and `parser` module can be deleted.

4. As a plugin maintainer, I want `serialize` to live in the `command_node`
   module, so that the on-disk format is owned by the same module that defines
   the shape, and field-name changes are local.

5. As a plugin maintainer, I want a `command_node.load(path)` function that
   reads a cache file, normalizes any missing fields to empty tables, and
   returns a well-formed node or nil, so that the full serialize-load round-trip
   is owned by one module and old cache files don't crash on load.

6. As a plugin maintainer, I want `find(node, args, arglead, opts)` extracted
   from the `setup()` closure into the `command_node` module, so that the
   tree-walking and candidate-collection logic is testable in isolation without
   driving the full `setup()` + user-command machinery.

7. As a plugin maintainer, I want `find()` to accept an optional
   `filesystem_completer` function via its `opts` parameter, so that tests can
   inject a mock and `find()` has no hard dependency on `vim.fn.getcompletion`.

8. As a plugin maintainer, I want `find()` to be pure (no Neovim side effects
   when `filesystem_completer` is injected), so that I can test completion
   behavior in a plain Lua harness without a running Neovim instance.

9. As a plugin maintainer, I want `find()` to preserve the exact current walk
   semantics — stop descending at `arglead`, stay at the current node when an
   arg doesn't match any subcommand, first occurrence of `arglead` stops the
   walk — so that the refactor is behavior-preserving.

10. As a plugin maintainer, I want `find()` to return only tree-derived
    candidates (subcommand names, flags, filesystem entries from
    `completion_type`), so that the module stays clean of plugin-specific
    concerns.

11. As a plugin maintainer, I want the `setup()` completion closure to append
    `--reparse-completions` at the root level after `find()` returns, so that
    the plugin-specific special flag lives in the plugin layer, not in the
    `command_node` module.

12. As a plugin maintainer, I want the crawlers (`help_crawler`,
    `completion_script_crawler`) to use `command_node.new()` instead of raw
    `{ flags = {}, subcommands = {} }` literals, so that the shape invariant is
    universal and there are no construction sites that bypass the constructor.

13. As a plugin maintainer, I want `find()` to drop all defensive nil-checks
    on `node.flags` and `node.subcommands`, so that the code is simpler and
    the shape guarantee is real, not aspirational.

14. As a plugin maintainer, I want a new `fs` module with `write_file` and
    `read_file`, so that generic file I/O has an honest single-purpose home
    and the `utils` grab-bag module can be deleted.

15. As a plugin maintainer, I want `utils` module deleted, so that the
    tree-specific serializer and the generic I/O functions are no longer
    bundled in a module with no single reason to exist.

16. As a plugin maintainer, I want `parser` module deleted, so that there is
    no separate module whose only purpose was text scraping that happened to
    return `CommandNode` tables — that responsibility now lives in
    `command_node`.

17. As a test author, I want `parser_spec.lua` renamed to
    `command_node_spec.lua`, so that the test file name matches the module it
    tests, following the project convention of one spec file per module.

18. As a test author, I want existing `parse_help` and `parse_bash` tests to
    move to `command_node_spec.lua` with only the `require` line changed, so
    that the migration is mechanical and low-risk.

19. As a test author, I want new `find()` tests that hand-build trees via
    `command_node.new()`, inject a mock `filesystem_completer`, and assert the
    candidate list, so that wrapper completion is tested for the first time.

20. As a test author, I want `find()` tests that cover the three subtle walk
    semantics — stop at arglead, stay on unknown arg, first-occurrence stops —
    so that the behavior is locked and future changes are caught.

21. As a test author, I want a `find()` test that verifies prefix filtering
    (only candidates starting with `arglead` are returned), so that the
    filtering behavior is explicitly tested.

22. As a test author, I want a `find()` test that verifies subcommand names
    are collected from the current node's `subcommands` map, so that the
    primary completion path is covered.

23. As a test author, I want a `find()` test that verifies flags are collected
    from the current node's `flags` array, so that flag completion is covered.

24. As a test author, I want a `find()` test that verifies filesystem
    candidates are collected when `completion_type` is set and the injected
    `filesystem_completer` returns results, so that file/dir completion is
    covered.

25. As a test author, I want a `find()` test that verifies no filesystem
    candidates are collected when `completion_type` is absent, so that the
    absent-field case is covered.

26. As a test author, I want a `find()` test that verifies candidates are
    sorted before returning, so that the sort behavior is locked.

27. As a test author, I want a `serialize()` round-trip test that builds a
    tree, serializes it, loads the result back, and asserts the tree shape is
    preserved, so that the on-disk format is tested.

28. As a test author, I want a `serialize()` test that verifies
    `completion_type` is omitted from the output when nil, so that the
    existing byte-compatible format is preserved.

29. As a test author, I want a `load()` test that writes a cache file with
    missing `flags` and `subcommands` fields, loads it, and asserts the
    fields are normalized to empty tables, so that old cache files don't crash.

30. As a test author, I want a `load()` test that asserts nil is returned when
    the file doesn't exist or is invalid Lua, so that the error path is
    covered.

31. As a test author, I want a `new()` test that asserts the returned node has
    `flags` and `subcommands` as empty tables, so that the constructor
    defaults are locked.

32. As a plugin user, I want existing cache files to continue loading without
    errors after the refactor, so that I don't lose my cached completions on
    upgrade.

33. As a plugin user, I want wrapper command completion to work identically
    before and after the refactor, so that I don't experience any behavior
    change.

34. As a plugin user, I want `--reparse-completions` to still appear as a
    completion candidate at the root level, so that I can trigger
    regeneration as before.

35. As a plugin maintainer, I want the `completion_cmd` fallback path in the
    generator subprocess to still call `command_node.parse` (formerly
    `parser.parse`), so that the fallback works after the refactor.

36. As a plugin maintainer, I want the generator subprocess to be able to
    `require "cling.command_node"` via the existing `rtp:prepend` mechanism,
    so that no new subprocess setup is needed.

37. As a plugin maintainer, I want the `completion_type` gap in
    `completion_script_crawler` documented as a known limitation in the ADR,
    so that it is not forgotten and can be addressed in a separate change.

38. As a plugin maintainer, I want the cache format to remain byte-compatible
    with existing files (no version field added), so that users don't
    experience a forced cache flush on upgrade.

## Implementation Decisions

### Modules created

- **`command_node` module** — the single owner of the completion-tree
  lifecycle. Absorbs all functions from the deleted `parser` module, the
  `serialize` function from the deleted `utils` module, and the `find`
  function extracted from the `setup()` closure. Owns the `@class
  cling.CommandNode` annotation.

- **`fs` module** — a minimal single-purpose module with `write_file` and
  `read_file`, absorbing the generic I/O functions from the deleted `utils`
  module.

### Modules deleted

- **`parser` module** — all functions (`parse`, `parse_help`, `parse_bash`)
  move to `command_node`. The module is removed.

- **`utils` module** — `serialize` moves to `command_node`; `write_file` and
  `read_file` move to `fs`. The module is removed.

### Interfaces

- `command_node.new()` → returns `{ flags = {}, subcommands = {} }` (a
  well-formed node with no `completion_type` key).

- `command_node.parse(binary_name, content)` → dispatches to `parse_help` or
  `parse_bash` based on content sniffing. Returns a `CommandNode`. (Absorbed
  from `parser`.)

- `command_node.parse_help(content)` → scrapes "Usage:" style help text.
  Returns a `CommandNode`. (Absorbed from `parser`.)

- `command_node.parse_bash(binary_name, content)` → scrapes bash completion
  scripts. Returns a `CommandNode` with optional `completion_type`. (Absorbed
  from `parser`.)

- `command_node.serialize(node)` → emits Lua source string. Byte-compatible
  with the existing `utils.serialize` output (same field order, omits
  `completion_type` when nil). (Absorbed from `utils`.)

- `command_node.load(path)` → wraps `loadfile` + call, normalizes missing
  `flags`/`subcommands` to `{}`, returns a well-formed node or `nil`. (New
  function; replaces raw `loadfile()()` in `cling`.)

- `command_node.find(node, args, arglead, opts)` → walks the tree, collects
  candidates (subcommand names, flags, filesystem entries), filters by
  `arglead` prefix, sorts, returns the match list. `opts.filesystem_completer`
  is an optional function; defaults to `vim.fn.getcompletion` in production.
  (Extracted from the `setup()` closure.)

- `fs.write_file(path, content)` → generic file writer. (Absorbed from
  `utils`.)

- `fs.read_file(path)` → generic file reader. (Absorbed from `utils`.)

### Architectural decisions

- **Parser scope:** `parse`/`parse_help`/`parse_bash` are absorbed into
  `command_node`. The text-scraping code and the tree-shape definition live in
  the same module. This was chosen over keeping `parser` as a separate scraper
  to maximize the "one home" claim — one module serves build, persist, and
  query. See ADR-001, Resolved Decision 1.

- **`find()` purity:** `find()` accepts an optional `filesystem_completer`
  function via `opts`. Tests inject a mock; production passes
  `vim.fn.getcompletion`. `find()` has no hard `vim` dependency inside. See
  ADR-001, Resolved Decision 4.

- **`--reparse-completions`:** The caller in `setup()` appends this synthetic
  flag after `find()` returns, when at root. `command_node` does not know about
  it. The completion closure is ~5 lines (split, call find, append special,
  return), not 3 — the boundary is honest. See ADR-001, Resolved Decision 5.

- **Shape enforcement:** `command_node.new()` is used at every construction
  site — parsers, crawlers, generator, tests. Crawlers are fixed to use the
  constructor instead of raw literals. `find()` drops all defensive nil-checks.
  See ADR-001, Resolved Decision 7.

- **Deserialization:** `command_node.load(path)` normalizes missing fields and
  replaces raw `loadfile()()` in `cling`. The full serialize-load round-trip is
  owned by one module. See ADR-001, Resolved Decision 6.

- **Cache format:** Byte-compatible with existing files. No version field
  added. `load()` normalizes missing fields, which handles the realistic
  failure mode. Versioning is deferred to when a schema change is actually
  incompatible. See ADR-001, Resolved Decision 8.

- **Subprocess boundary:** The generator subprocess already prepends the
  plugin root to `rtp` before requiring modules. `require "cling.command_node"`
  works in the `nvim -l` subprocess exactly as `require "cling.parser"` does
  today. No new subprocess setup is needed. See ADR-001, Resolved Decision 12.

### Known limitations (deferred, not introduced by this refactor)

- `completion_script_crawler` never sets `completion_type` (only `parse_bash`
  does). This means the most common completion path
  (`completion_cmd`/`completion_file` via the script crawler) does not produce
  file/dir completion hints. This is a pre-existing bug documented in ADR-001,
  Resolved Decision 9. The fix is deferred to a separate change.

## Testing Decisions

### What makes a good test

Tests should exercise the `command_node` module's public API — `new`, `parse`,
`find`, `serialize`, `load` — and assert external behavior (returned values,
side effects on disk), not implementation details (internal helper functions,
private state). The highest seam is the module boundary: require the module,
call its functions, inspect the results. No test should drive `setup()`,
`nvim_create_user_command`, or the subprocess to test `command_node`'s logic.

### Modules tested

- **`command_node`** — the primary module under test. All new tests live in
  `command_node_spec.lua` (renamed from `parser_spec.lua`).

- **`fs`** — tested implicitly through `command_node.load()` (which reads
  files) and `command_node.serialize()` round-trip (which writes and reads
  files). No separate spec file needed unless `fs` grows beyond two functions.

### Test plan

| Area | Tests | Prior art |
|---|---|---|
| `new()` | Assert `flags` and `subcommands` are empty tables; assert no `completion_type` key | New (no constructor exists yet) |
| `parse_help()` | Existing tests move from `parser_spec.lua` — parse usage with commands/options, parse with different section headers | `parser_spec.lua` (same tests, changed `require`) |
| `parse_bash()` | Existing tests move from `parser_spec.lua` — detect file completion type, detect directory completion type | `parser_spec.lua` (same tests, changed `require`) |
| `find()` — walk semantics | Stop at arglead; stay on unknown arg; first occurrence stops | New — `plugin_completion_spec.lua` tested the `:Cling` command's complete func similarly (synthetic arglead/cmdline), but this is the first test of wrapper completion |
| `find()` — candidate collection | Subcommand names from current node; flags from current node; filesystem candidates when `completion_type` set + completer returns; no filesystem candidates when `completion_type` absent | New |
| `find()` — filtering | Only candidates starting with `arglead` are returned | New |
| `find()` — sorting | Candidates are sorted before returning | New |
| `find()` — purity | `filesystem_completer` mock is called with `arglead` and `completion_type`; no `vim.fn.getcompletion` call when mock is provided | New |
| `serialize()` | Round-trip: build tree, serialize, `loadstring` back, assert shape preserved; `completion_type` omitted when nil | New (currently untested) |
| `load()` | Missing `flags`/`subcommands` normalized to `{}`; nil returned for nonexistent file; nil returned for invalid Lua | New (currently raw `loadfile` is untested) |

### Test harness

Tests run under `plenary.nvim` with `busted`-style syntax (`describe`/`it`/
`assert`), inside headless Neovim via `minimal_init.lua`. The `find()` tests
with an injected `filesystem_completer` mock are pure — they don't need
`vim.fn.getcompletion` and could theoretically run in plain Lua, but they stay
in the plenary harness for consistency with the rest of the suite.

## Out of Scope

- **Fixing the `completion_type` gap in `completion_script_crawler`.** This is
  a pre-existing bug where the script crawler never detects file/dir
  completion hints. It is documented as a known limitation in ADR-001 and
  deferred to a separate change.

- **Adding a version field to the cache format.** The cache format remains
  byte-compatible. Versioning is deferred to when a schema change is actually
  incompatible.

- **Extracting terminal-output navigation from the executor.** This is
  Candidate 2 from the architecture review and is a separate refactoring
  effort.

- **One seam for completion generation (Candidate 3).** This is a separate
  refactoring effort that would make the generator module own the method
  dispatch table and depth limit.

- **Window column capture as its own module (Candidate 4).** This is a
  separate refactoring effort.

- **Modeling `CommandNode` as a metatable-based class.** Rejected in ADR-001
  (Alternative 3). Completion trees are plain tables and the cache file is
  plain Lua source; a function-module over plain tables preserves that.

- **Making `serialize` fully generic (data-driven).** Rejected in ADR-001
  (Alternative 4). A generic serializer would decouple serialization from
  schema but removes the "node owns its fields" locality this refactor creates.

- **Changing the subprocess boundary.** The `nvim -l` generator subprocess
  stays as-is. Only the `require` targets change (from `cling.parser`/
  `cling.utils` to `cling.command_node`/`cling.fs`).

## Further Notes

- This spec implements ADR-001 ("Give CommandNode a home"), which was produced
  by the `grill-with-docs` skill through a three-round grilling process. All 12
  design questions were resolved before this spec was written. See
  `doc/adr/ADR-001-command-node-home.md` for the full decision record.

- The domain glossary at `doc/glossary.md` defines the key terms used in this
  spec: `CommandNode`, `completion tree`, `wrapper`, `completion_type`,
  `flags`, `subcommands`, `completion candidate`, `arglead`, `crawler`,
  `generator`, `cache file`, `seam`, and the "deletion test."

- The original architecture review counted 4 duplication sites; the grilling
  process discovered the actual count is 6 (both crawlers and both parse
  functions each construct the literal independently). This strengthens the
  rationale and is reflected in the ADR.

- The grilling process also corrected several claims from the original
  architecture review:
  - The "pure" claim for `find()` was false (`vim.fn.getcompletion` is a side
    effect) — fixed by injecting `filesystem_completer`.
  - The "delete utils.lua" claim was overstated (`write_file`/`read_file` are
    generic I/O) — fixed by creating `cling.fs`.
  - The "three lines" claim for the closure was aspirational — it's ~5 lines
    once `--reparse-completions` is handled honestly by the caller.
  - Zero tests exist for wrapper completion — the `find()` extraction is the
    first opportunity to test it.