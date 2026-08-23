# 01: Create command_node module with constructor and parser functions

**What to build:** The `command_node` module is born. It owns the `@class cling.CommandNode` annotation, a `new()` constructor that returns a well-formed `{ flags = {}, subcommands = {} }` node, and the three parsing functions (`parse`, `parse_help`, `parse_bash`) absorbed from the deleted `parser` module. All callers that previously required `parser` — the generator subprocess and the help crawler — now require `command_node`. The existing `parser_spec.lua` is renamed to `command_node_spec.lua` with its `require` line updated, and a new test for `new()` is added. The `parser` module is deleted. Parsing behavior is identical; the constructor exists and is used internally by the parser functions.

**Blocked by:** None (can start immediately)

**Status:** done

- [x] `command_node` module exists with `@class cling.CommandNode` annotation, `new()`, `parse()`, `parse_help()`, and `parse_bash()`
- [x] `new()` returns a table with `flags = {}` and `subcommands = {}` and no `completion_type` key
- [x] `parse()`, `parse_help()`, and `parse_bash()` behave identically to the current `parser` equivalents
- [x] The generator subprocess requires `command_node` instead of `parser` and works in the `nvim -l` context
- [x] The help crawler requires `command_node` instead of `parser` and works
- [x] `parser_spec.lua` is renamed to `command_node_spec.lua` with updated `require` line
- [x] Existing `parse_help` and `parse_bash` tests pass unchanged (except the `require` line)
- [x] New test: `new()` returns a node with `flags` and `subcommands` as empty tables, no `completion_type` key
- [x] `parser` module is deleted; no file in the codebase requires `cling.parser`