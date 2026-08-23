# 04: Extract find() into command_node

**What to build:** The tree-walk and candidate-collection logic is extracted from the ~45-line inline `complete_func` closure in `setup()` into `command_node.find(node, args, arglead, opts)`. The function walks the tree (stop descending at `arglead`, stay at current node on unknown args, first occurrence of `arglead` stops the walk), collects subcommand names and flags from the current node, collects filesystem candidates when `completion_type` is set (via the injected `opts.filesystem_completer`, which defaults to `vim.fn.getcompletion` in production), filters by `arglead` prefix, sorts, and returns the match list. The `setup()` closure shrinks to: split `cmdline` into `args`, call `command_node.find()`, append `--reparse-completions` at root, return. `find()` has no hard `vim` dependency inside — tests inject a mock `filesystem_completer`. These are the first tests for wrapper completion in the project.

**Blocked by:** 01 (Create command_node module with constructor and parser functions)

**Status:** ready-for-agent

- [x] `command_node.find(node, args, arglead, opts)` exists and returns a sorted list of candidate strings
- [x] `find()` accepts `opts.filesystem_completer` function; defaults to `vim.fn.getcompletion` when not provided
- [x] `find()` preserves exact walk semantics: stop descending at `arglead`, stay at current node on unknown args, first occurrence of `arglead` stops the walk
- [x] `find()` collects subcommand names from the current node's `subcommands` map
- [x] `find()` collects flags from the current node's `flags` array
- [x] `find()` collects filesystem candidates when `completion_type` is set and `filesystem_completer` returns results
- [x] `find()` collects no filesystem candidates when `completion_type` is absent
- [x] `find()` filters candidates to those starting with `arglead`
- [x] `find()` sorts candidates before returning
- [x] The `setup()` closure appends `--reparse-completions` at root after `find()` returns
- [x] The `setup()` closure no longer contains tree-walking or candidate-collection logic
- [x] New test: walk stops at `arglead`
- [x] New test: walk stays at current node on unknown arg
- [x] New test: first occurrence of `arglead` stops the walk
- [x] New test: subcommand names collected from current node
- [x] New test: flags collected from current node
- [x] New test: filesystem candidates collected when `completion_type` set + completer returns
- [x] New test: no filesystem candidates when `completion_type` absent
- [x] New test: prefix filtering works
- [x] New test: candidates sorted before returning
- [x] New test: `filesystem_completer` mock is called with `arglead` and `completion_type`; no `vim.fn.getcompletion` call when mock provided
- [x] All existing tests pass
