# 03: Add command_node.load() with field normalization

**What to build:** `command_node.load(path)` is added to the `command_node` module. It wraps `loadfile` + call, normalizes any missing `flags` or `subcommands` fields to empty tables, and returns a well-formed `CommandNode` or `nil`. Both raw `loadfile(cache_file)()` call sites in `cling.lua` (the synchronous cache-read path and the async completion callback) are replaced with `command_node.load()`. New tests cover: missing `flags`/`subcommands` normalized to `{}`, `nil` returned for a nonexistent file, `nil` returned for invalid Lua. Existing cache files load without errors.

**Blocked by:** 02 (Create fs module, move serialize to command_node, delete utils)

**Status:** ready-for-agent

- [x] `command_node.load(path)` exists and returns a well-formed node or `nil`
- [x] `load()` normalizes missing `flags` to `{}` and missing `subcommands` to `{}`
- [x] `load()` returns `nil` when the file does not exist
- [x] `load()` returns `nil` when the file contains invalid Lua
- [x] Both `loadfile(cache_file)()` call sites in `cling.lua` are replaced with `command_node.load()`
- [x] New test: missing fields normalized to `{}`
- [x] New test: `nil` for nonexistent file
- [x] New test: `nil` for invalid Lua
- [x] All existing tests pass