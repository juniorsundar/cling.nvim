# 02: Create fs module, move serialize to command_node, delete utils

**What to build:** The grab-bag `utils` module is eliminated. A new `fs` module absorbs the generic `write_file` and `read_file` functions. The tree-specific `serialize` function moves from `utils` into `command_node`. All three consumers of `utils` — `core.lua` (export output), `history.lua` (save/load), and `generator.lua` (persist completions) — are updated to require `fs` for I/O and `command_node` for serialization. The `utils` module is deleted. Serialization output is byte-compatible with existing cache files (same field order, `completion_type` omitted when nil). A new `serialize()` round-trip test is added to `command_node_spec.lua`.

**Blocked by:** 01 (Create command_node module with constructor and parser functions)

**Status:** ready-for-agent

- [x] `fs` module exists with `write_file(path, content)` and `read_file(path)` functions
- [x] `command_node.serialize(node)` produces byte-compatible output with the current `utils.serialize` (same field order, `completion_type` omitted when nil)
- [x] `core.lua` requires `fs` instead of `utils` for `write_file` in export output
- [x] `history.lua` requires `fs` instead of `utils` for `write_file` and `read_file`
- [x] `generator.lua` requires `command_node` for `serialize` and `fs` for `write_file` instead of `utils`
- [x] `utils` module is deleted; no file in the codebase requires `cling.utils`
- [x] New test: `serialize()` round-trip — build a tree via `new()`, serialize, `loadstring` back, assert shape preserved
- [x] New test: `serialize()` omits `completion_type` when nil
- [x] All existing tests pass
