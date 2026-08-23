# ADR-001: Give CommandNode a home

## Status

Accepted — all 12 grilling questions resolved

## Context

The completion tree's shape is defined implicitly and duplicated across the
codebase, and no single module owns its lifecycle.

The `CommandNode` record — `flags`, `subcommands`, and optional
`completion_type` — is declared once as an annotation at
`lua/cling/parser.lua:3-6`, but its literal shape is reconstructed by hand in at
least six sites:

1. **parser.lua** — constructs nodes in `parse_help` (`:39`, return at `:61-64`)
   and `parse_bash` (`:113`, return at `:151-155`).
2. **utils.lua `serialize`** — hard-codes the three field names
   `completion_type` (`:33-35`), `flags` (`:36-40`), and `subcommands`
   (`:43-50`) to emit Lua source.
3. **cling.lua `setup()`** — builds the root literal
   `{ flags = {}, subcommands = {} }` (`:192`) and walks
   `subcommands`/`flags`/`completion_type` inside a ~49-line inline
   `complete_func` closure (`:201-249`).
4. **generator.lua** — builds the root literal `{ flags = {}, subcommands = {} }`
   (`:23`).
5. **help_crawler.lua** — returns the depth-limit sentinel
   `{ flags = {}, subcommands = {} }` (`:30`).
6. **completion_script_crawler.lua** — builds the root (`:81-83`) and mutates
   node fields directly (`:126-131`); it never even calls `parser`, so it
   carries an independent copy of the shape knowledge.

> **Note:** the original architecture review counted "4 places"; the actual
> count is higher because both crawlers and both parse functions each construct
> the literal independently. This only strengthens the rationale.

Consequences of this duplication:

- Adding a field (e.g., a per-node `exclude` list or an argument-hint field)
  requires editing every site with nothing — no type, no constructor, no test —
  forcing them to agree. The `@class` annotation is documentation only; Lua
  will not reject a node missing `flags` or `subcommands`.
- The query logic is trapped inside `setup()`, mixing three concerns: tree
  descent, a hard-coded root special case (`--reparse-completions`,
  `cling.lua:232-234`), and filesystem completion (`vim.fn.getcompletion`,
  `cling.lua:235-239`). It is testable only by driving the whole `setup()` +
  `nvim_create_user_command` machinery, which the current test suite does not
  cover (there is no spec exercising `complete_func`;
  `plugin_completion_spec.lua` tests only the separate `:Cling` command's
  callback).
- `utils.lua` fails the deletion test: it mixes generic file I/O
  (`write_file`/`read_file`, consumed by `core.lua:142-143`,
  `history.lua:72-73`, and `generator.lua:68,79-80` for three unrelated
  purposes) with a tree-specific serializer that is coupled to the node schema.
  The module has no single reason to exist.
- `parser.lua` is currently the *de facto* home of the `CommandNode`
  annotation, but it is really a text-scraping module, not a "node" module; the
  annotation and the scrapers are different responsibilities that happen to
  share a file.

## Decision

Create `lua/cling/command_node.lua` as the single owner of the completion-tree
lifecycle, and concentrate the node's shape there:

1. **Own the type and construction.** Move the `@class cling.CommandNode`
   annotation into `command_node.lua` and expose a constructor (e.g.,
   `command_node.new()`) that returns a well-formed
   `{ flags = {}, subcommands = {} }` node (with `completion_type` absent or
   normalized to `nil`). Every literal construction site is replaced with this
   constructor.

2. **Absorb build (parse).** Move `parse`, `parse_help`, and `parse_bash` from
   `parser.lua` into `command_node.lua`. `parser.lua` is deleted. One module
   owns the entire lifecycle: build, persist, query.

3. **Absorb persist (serialize).** Move `utils.serialize` into
   `command_node.lua` (as `serialize` or `to_lua`), keeping the emitted schema
   byte-compatible unless a deliberate schema migration is decided.

4. **Absorb query (`find`).** Extract the tree-walk and candidate-collection
   logic from the closure at `cling.lua:201-249` into
   `command_node.find(node, args, arglead)`. The `setup()` completion callback
   shrinks to roughly: split `cmdline` into `args`, call
   `command_node.find(completions, args, arglead)`, and return the result.

5. **Delete `utils.lua`.** Relocate `write_file`/`read_file` to a new
   `lua/cling/fs.lua` module. `serialize` has already moved to `command_node`.
   `utils.lua` is deleted.

6. **Keep the subprocess boundary intact.** `generator.lua` already does
   `vim.opt.rtp:prepend(plugin_root)` (`generator.lua:16`) before requiring
   modules, so `require "cling.command_node"` works in the `nvim -l` subprocess
   exactly as `require "cling.parser"`/`require "cling.utils"` do today.

## Consequences

### Positive

- **Single source of truth for the node shape.** The annotation, constructor,
  serializer, and query live in one module; adding a field means changing that
  module (and its `serialize`/`find`), and the constructor prevents malformed
  literals.
- **`find` becomes directly testable.** Given a constructed tree (via
  `command_node.new()`), `find(node, args, arglead)` can be exercised in
  isolation without `setup()`, `ensure_completion`, or the subprocess.
- **`setup()` loses ~45 lines of mixed concerns**, becoming orchestration
  rather than completion implementation.
- **`utils.lua` is deleted**, removing the grab-bag module and forcing the
  generic-vs-node-specific distinction to be made explicitly.
- **Crawlers stop hand-rolling node literals**, closing the hidden "6th site"
  gap in the original 4-place analysis.

### Negative / Neutral

- **Migration cost.** Every construction site and `require "cling.utils"` /
  `require "cling.parser"` call must be updated; this touches `cling.lua`,
  `generator.lua`, `help_crawler.lua`, `completion_script_crawler.lua`,
  `core.lua`, and `history.lua`.
- **`find` requires an injected `filesystem_completer`.** The caller must pass
  `vim.fn.getcompletion` (or a mock) as an optional parameter. This is a small
  wire-up cost in exchange for genuine purity — `find()` has no `vim`
  dependency inside.
- **On-disk cache compatibility risk.** Existing `<binary>.lua` caches contain
  no schema/version marker; if `serialize` changes field names or layout,
  `loadfile(cache_file)` returns a table lacking new fields and fails silently.
- **Naming.** `command_node` names a module that owns a tree and a query over
  it; `command_tree` was considered but rejected — the module owns the
  `CommandNode` *type* and all its operations, and the tree is just the
  recursive structure of nodes.

## Alternatives Considered

1. **Status quo (leave duplication in place).** Rejected: the schema is already
   diverging (see the `completion_type` asymmetry), and query logic is untested
   and embedded in `setup()`.

2. **Extract only `find()` (minimal refactor), leave build/persist where they
   are.** Rejected: this removes the biggest symptom but leaves the shape
   duplicated across `parser`, `utils.serialize`, `generator`, and both
   crawlers, and does not delete the failing `utils.lua`.

3. **Model `CommandNode` as an object/class with methods on instances
   (metatable-based).** Rejected: Lua completion trees are plain tables and the
   cache file is plain Lua source; a function-module over plain tables preserves
   that and keeps serialization/loadfile trivial.

4. **Make `serialize` fully generic (data-driven, no hard-coded field
   names).** Considered: a generic serializer would be reusable but removes the
   "node owns its fields" locality this ADR creates.

5. **Move `find` into `core.lua` or a separate `completion.lua` module.**
   Rejected: `find` needs to know the node shape to walk
   `subcommands`/`flags`/`completion_type`; placing it apart from `serialize`
   and the constructor re-creates the multi-site coupling this ADR eliminates.

## Resolved Decisions (from grilling)

### Round 1 — Scope & Boundaries

1. **Parser scope (Q1.1):** Absorb `parse`/`parse_help`/`parse_bash` into
   `command_node.lua`. `parser.lua` is deleted. One module owns the entire
   lifecycle: build, persist, query.

2. **Generic I/O (Q1.3):** Create a new `lua/cling/fs.lua` module with
   `write_file`/`read_file`. `utils.lua` is deleted. `serialize` moves to
   `command_node`; generic I/O moves to `cling.fs`.

3. **Module name (Q1.5):** `command_node` — the module owns the `CommandNode`
   type and all its operations. The tree is the recursive structure of nodes.

### Round 2 — Internal Design

4. **`find()` purity (Q2.1):** Inject an optional `filesystem_completer`
   function parameter. Tests pass a mock; production passes
   `vim.fn.getcompletion`. `find()` is genuinely pure — no vim dependency inside.

5. **`--reparse-completions` (Q2.3):** The caller in `setup()` appends it after
   `find()` returns, when at root. `command_node` stays clean of plugin-specific
   knowledge. The closure is ~5 lines, not 3, but the boundary is honest.

6. **Deserialization (Q2.4):** `command_node.load(path)` wraps `loadfile` +
   call, normalizes missing fields (`flags`/`subcommands` default to `{}`),
   and returns a well-formed node or `nil`. `cling.lua`'s raw `loadfile()()`
   calls are replaced.

7. **Shape enforcement (Q2.6):** `command_node.new()` is used everywhere —
   parser, crawlers, generator, tests. Crawlers are fixed to use the
   constructor instead of raw `{ flags = {}, subcommands = {} }` literals.
   `find()` drops all defensive nil-checks — fields are guaranteed to exist.

### Round 3 — Edge Cases & Migration

8. **Cache schema (Q3.1):** Keep byte-compatible, no version field. `load()`
   normalizes missing `flags`/`subcommands` to `{}`, which handles the
   realistic failure mode. Versioning is deferred to when a schema change is
   actually incompatible — adding it now would force a cache flush for zero
   benefit.

9. **`completion_type` crawler gap (Q3.4):** Documented as a known limitation.
   `completion_script_crawler` never sets `completion_type` (only `parse_bash`
   does). This is a pre-existing bug, not introduced by this refactor. The fix
   (detecting `compgen -d`/`compgen -f`/`_filedir` in the crawler) is deferred to
   a separate, testable change after the structural refactor lands.

10. **Walk semantics (Q3.5):** `find()` preserves the exact current behavior:
    stop descending at `arglead`, stay at current node on unknown args (no
    error, no skip), first occurrence of `arglead` stops the walk. Explicit
    specs lock these behaviors — the first tests in the project that cover
    wrapper completion.

11. **Test migration (Q3.6):** `parser_spec.lua` is renamed to
    `command_node_spec.lua`. Existing `parse_help`/`parse_bash` tests move over
    (changed `require` line). New specs added for `find()` (walk semantics,
    candidate collection, prefix filtering), `serialize()` (round-trip),
    `load()` (normalization of missing fields), and `new()` (constructor
    defaults). One spec file per module, following project convention.

12. **Subprocess reachability (Q3.7):** Confirmed — `generator.lua` already
    does `vim.opt.rtp:prepend(plugin_root)` before requiring modules, so
    `require "cling.command_node"` works in the `nvim -l` subprocess exactly as
    `require "cling.parser"` does today. The `completion_cmd` fallback path
    calls `command_node.parse` (formerly `parser.parse`) which remains
    reachable.

## All Open Questions Resolved

All 12 questions from the grilling process are resolved. The design is ready
for implementation.